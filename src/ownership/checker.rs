use crate::ast::{Expr, Pattern, Program, Type as AstType};
use crate::ownership::state::OwnershipState;
use std::collections::HashMap;
use thiserror::Error;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum OwnershipError {
    #[error("Use after move: variable '{0}' was moved and cannot be used again")]
    UseAfterMove(String),
    #[error("Cannot borrow '{0}' as mutable because it is already borrowed")]
    AlreadyBorrowed(String),
    #[error("Cannot borrow '{0}' as immutable because it is already mutably borrowed")]
    AlreadyMutBorrowed(String),
    #[error("Cannot move '{0}' because it is currently borrowed")]
    MoveWhileBorrowed(String),
    #[error("Variable '{0}' not found in scope")]
    NotFound(String),
}

/// Registry of function signatures discovered during pre-scan
#[derive(Debug, Clone, Default)]
pub struct FunctionRegistry {
    /// Maps function name to parameter types
    pub signatures: HashMap<String, Vec<Option<AstType>>>,
}

impl FunctionRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn from_program(program: &Program) -> Self {
        let mut reg = Self::new();
        for expr in &program.exprs {
            if let Expr::Defn { name, params, .. } = expr {
                let param_types: Vec<Option<AstType>> = params.iter().map(|(_, ty)| ty.clone()).collect();
                reg.signatures.insert(name.0.clone(), param_types);
            }
        }
        reg
    }

    pub fn get(&self, name: &str) -> Option<&Vec<Option<AstType>>> {
        self.signatures.get(name)
    }
}

/// A stack of scopes, each mapping variable names to their ownership state
#[derive(Debug, Clone)]
pub struct OwnershipEnv {
    scopes: Vec<HashMap<String, OwnershipState>>,
}

impl OwnershipEnv {
    pub fn new() -> Self {
        Self {
            scopes: vec![HashMap::new()],
        }
    }

    pub fn push_scope(&mut self) {
        self.scopes.push(HashMap::new());
    }

    pub fn pop_scope(&mut self) {
        self.scopes.pop();
    }

    pub fn get(&self, name: &str) -> Option<&OwnershipState> {
        for scope in self.scopes.iter().rev() {
            if let Some(state) = scope.get(name) {
                return Some(state);
            }
        }
        None
    }

    pub fn insert(&mut self, name: String, state: OwnershipState) {
        if let Some(scope) = self.scopes.last_mut() {
            scope.insert(name, state);
        }
    }

    pub fn update(&mut self, name: &str, state: OwnershipState) {
        for scope in self.scopes.iter_mut().rev() {
            if scope.contains_key(name) {
                scope.insert(name.to_string(), state);
                return;
            }
        }
    }

    /// Merge another environment into this one conservatively.
    /// Used after if-branches: if a variable is moved in either branch, it's moved after.
    pub fn merge(&mut self, other: &OwnershipEnv) {
        if let (Some(self_top), Some(other_top)) = (self.scopes.last_mut(), other.scopes.last()) {
            for (name, other_state) in other_top.iter() {
                if let Some(self_state) = self_top.get(name) {
                    let merged = match (self_state, other_state) {
                        (OwnershipState::Moved, _) | (_, OwnershipState::Moved) => {
                            OwnershipState::Moved
                        }
                        (OwnershipState::MutBorrowed, _) | (_, OwnershipState::MutBorrowed) => {
                            OwnershipState::Owned
                        }
                        (OwnershipState::Borrowed { .. }, _) | (_, OwnershipState::Borrowed { .. }) => {
                            OwnershipState::Owned
                        }
                        (OwnershipState::Copy, OwnershipState::Copy) => OwnershipState::Copy,
                        _ => OwnershipState::Owned,
                    };
                    self_top.insert(name.clone(), merged);
                }
            }
        }
    }
}

impl Default for OwnershipEnv {
    fn default() -> Self {
        Self::new()
    }
}

/// Check a whole program for ownership violations
pub fn check_program(program: &Program) -> Result<(), OwnershipError> {
    let registry = FunctionRegistry::from_program(program);
    let mut env = OwnershipEnv::new();
    for expr in &program.exprs {
        check_expr(expr, &mut env, &registry)?;
    }
    Ok(())
}

/// Determine if an expression evaluates to a Copy type
fn expr_is_copy(expr: &Expr, registry: &FunctionRegistry) -> bool {
    match expr {
        Expr::Number(_) | Expr::Bool(_) | Expr::Float(_) => true,
        Expr::FnCall { func, .. } => {
            if let Expr::Symbol(sym) = func.as_ref() {
                matches!(sym.0.as_str(),
                    "+" | "-" | "*" | "/" | "%" |
                    "=" | "!=" | "<" | ">" | "<=" | ">=" |
                    "not" | "and" | "or" |
                    "count" | "get" | "map-get" | "map-count" |
                    "inc" | "dec" | "abs" | "max" | "min" |
                    "even?" | "odd?" | "zero?" | "pos?" | "neg?" |
                    "empty?" | "contains?" | "index-of" | "str-count" |
                    "square" | "cube" | "gcd" | "lcm" | "factorial" | "fib" |
                    "sum" | "product" | "first" | "last" | "nth"
                )
            } else {
                false
            }
        }
        Expr::Symbol(sym) => {
            // If it's a known function name that returns copy, but here it's used as value
            // we can't know without type info. Default to non-Copy for symbols.
            false
        }
        _ => false,
    }
}

/// Add pattern bindings to the environment
fn add_pattern_bindings(
    pattern: &Pattern,
    env: &mut OwnershipEnv,
    registry: &FunctionRegistry,
) {
    match pattern {
        Pattern::Binding(sym) => {
            env.insert(sym.0.clone(), OwnershipState::Owned);
        }
        Pattern::Vector(patterns, _) | Pattern::List(patterns, _) => {
            for p in patterns {
                add_pattern_bindings(p, env, registry);
            }
        }
        _ => {}
    }
}

/// Check an expression, returning the ownership state of its result
fn check_expr(
    expr: &Expr,
    env: &mut OwnershipEnv,
    registry: &FunctionRegistry,
) -> Result<OwnershipState, OwnershipError> {
    match expr {
        Expr::Number(_) | Expr::Float(_) | Expr::Bool(_) => {
            Ok(OwnershipState::Copy)
        }
        Expr::String(_) | Expr::Keyword(_) => {
            Ok(OwnershipState::Owned)
        }

        Expr::Symbol(sym) => {
            let name = &sym.0;
            match env.get(name) {
                Some(OwnershipState::Moved) => {
                    Err(OwnershipError::UseAfterMove(name.clone()))
                }
                Some(OwnershipState::Copy) => Ok(OwnershipState::Copy),
                Some(OwnershipState::MutBorrowed) => Ok(OwnershipState::Owned),
                Some(OwnershipState::Borrowed { .. }) => Ok(OwnershipState::Owned),
                Some(OwnershipState::Owned) => Ok(OwnershipState::Owned),
                None => Ok(OwnershipState::Owned),
            }
        }

        Expr::Let { bindings, body, .. } => {
            env.push_scope();
            for (name, val_expr) in bindings {
                let _val_state = check_expr(val_expr, env, registry)?;
                if let Expr::Symbol(sym) = val_expr {
                    if !matches!(env.get(&sym.0), Some(OwnershipState::Copy)) {
                        env.update(&sym.0, OwnershipState::Moved);
                    }
                }
                if expr_is_copy(val_expr, registry) {
                    env.insert(name.0.clone(), OwnershipState::Copy);
                } else {
                    env.insert(name.0.clone(), OwnershipState::Owned);
                }
            }
            let body_state = check_expr(body, env, registry)?;
            env.pop_scope();
            Ok(body_state)
        }

        Expr::If { cond, then_branch, else_branch, .. } => {
            check_expr(cond, env, registry)?;

            let mut then_env = env.clone();
            check_expr(then_branch, &mut then_env, registry)?;

            let mut else_env = env.clone();
            check_expr(else_branch, &mut else_env, registry)?;

            env.merge(&then_env);
            env.merge(&else_env);

            Ok(OwnershipState::Owned)
        }

        Expr::Match { expr, arms, .. } => {
            check_expr(expr, env, registry)?;
            let mut arm_envs = Vec::new();
            for (pattern, body) in arms {
                let mut arm_env = env.clone();
                arm_env.push_scope();
                add_pattern_bindings(pattern, &mut arm_env, registry);
                check_expr(body, &mut arm_env, registry)?;
                arm_env.pop_scope();
                arm_envs.push(arm_env);
            }
            for arm_env in arm_envs {
                env.merge(&arm_env);
            }
            Ok(OwnershipState::Owned)
        }

        Expr::Do { exprs, .. } => {
            let mut last = OwnershipState::Owned;
            for e in exprs {
                last = check_expr(e, env, registry)?;
            }
            Ok(last)
        }

        Expr::Def { name, value, .. } => {
            let _val_state = check_expr(value, env, registry)?;
            if let Expr::Symbol(sym) = value.as_ref() {
                if !matches!(env.get(&sym.0), Some(OwnershipState::Copy)) {
                    env.update(&sym.0, OwnershipState::Moved);
                }
            }
            if expr_is_copy(value, registry) {
                env.insert(name.0.clone(), OwnershipState::Copy);
            } else {
                env.insert(name.0.clone(), OwnershipState::Owned);
            }
            Ok(OwnershipState::Owned)
        }

        Expr::Defn { name: _, params, body, .. } => {
            env.push_scope();
            for (param, param_ty) in params {
                let state = match param_ty {
                    Some(AstType::MutRef(_)) => OwnershipState::MutBorrowed,
                    Some(AstType::Ref(_)) => OwnershipState::Borrowed { count: 1 },
                    _ => OwnershipState::Owned,
                };
                env.insert(param.0.clone(), state);
            }
            check_expr(body, env, registry)?;
            env.pop_scope();
            Ok(OwnershipState::Owned)
        }

        Expr::FnCall { func: func_expr, args, .. } => {
            check_expr(func_expr, env, registry)?;

            // Determine parameter types from registry if available
            let func_name = match func_expr.as_ref() {
                Expr::Symbol(sym) => Some(sym.0.clone()),
                _ => None,
            };
            let param_types: Option<&Vec<Option<AstType>>> = func_name.as_ref().and_then(|n| registry.get(n));

            for (i, arg) in args.iter().enumerate() {
                let expected_ty = param_types.and_then(|pt| pt.get(i).cloned().flatten());

                match arg {
                    Expr::Borrow(inner, is_mut, _) => {
                        if let Expr::Symbol(sym) = inner.as_ref() {
                            let name = &sym.0;
                            match env.get(name) {
                                Some(OwnershipState::Moved) => {
                                    return Err(OwnershipError::UseAfterMove(name.clone()));
                                }
                                Some(OwnershipState::Copy) => {
                                    // Copy types can always be borrowed
                                }
                                Some(OwnershipState::MutBorrowed) => {
                                    return Err(OwnershipError::AlreadyBorrowed(name.clone()));
                                }
                                Some(OwnershipState::Borrowed { .. }) if *is_mut => {
                                    return Err(OwnershipError::AlreadyBorrowed(name.clone()));
                                }
                                Some(OwnershipState::Borrowed { .. }) => {
                                    // Multiple immutable borrows are OK
                                }
                                Some(OwnershipState::Owned) => {
                                    if *is_mut {
                                        env.update(name, OwnershipState::MutBorrowed);
                                    } else {
                                        env.update(name, OwnershipState::Borrowed { count: 1 });
                                    }
                                }
                                None => {}
                            }
                        }
                        check_expr(inner, env, registry)?;
                    }
                    Expr::Symbol(sym) => {
                        let name = &sym.0;
                        // If function expects a borrow but symbol is passed directly, error
                        if matches!(expected_ty, Some(AstType::Ref(_)) | Some(AstType::MutRef(_))) {
                            return Err(OwnershipError::AlreadyBorrowed(format!(
                                "passing '{}' to function expecting borrow - use '^{}' instead",
                                name, name
                            )));
                        }
                        check_expr(arg, env, registry)?;
                    }
                    other => {
                        check_expr(other, env, registry)?;
                    }
                }
            }
            Ok(OwnershipState::Owned)
        }

        Expr::Borrow(inner, is_mut, _) => {
            if let Expr::Symbol(sym) = inner.as_ref() {
                let name = &sym.0;
                match env.get(name) {
                    Some(OwnershipState::Moved) => {
                        return Err(OwnershipError::UseAfterMove(name.clone()));
                    }
                    Some(OwnershipState::Copy) => {
                        // Copy types can always be borrowed
                    }
                    Some(OwnershipState::MutBorrowed) => {
                        return Err(OwnershipError::AlreadyMutBorrowed(name.clone()));
                    }
                    Some(OwnershipState::Borrowed { .. }) if *is_mut => {
                        return Err(OwnershipError::AlreadyBorrowed(name.clone()));
                    }
                    Some(OwnershipState::Borrowed { .. }) => {
                        // Multiple immutable borrows are OK
                    }
                    Some(OwnershipState::Owned) => {
                        if *is_mut {
                            env.update(name, OwnershipState::MutBorrowed);
                        } else {
                            env.update(name, OwnershipState::Borrowed { count: 1 });
                        }
                    }
                    None => {}
                }
            }
            check_expr(inner, env, registry)
        }

        Expr::Loop { bindings, body, .. } => {
            env.push_scope();
            for (name, val_expr) in bindings {
                let _val_state = check_expr(val_expr, env, registry)?;
                if let Expr::Symbol(sym) = val_expr {
                    env.update(&sym.0, OwnershipState::Moved);
                }
                env.insert(name.0.clone(), OwnershipState::Owned);
            }
            let body_state = check_expr(body, env, registry)?;
            env.pop_scope();
            Ok(body_state)
        }

        Expr::Recur { args, .. } => {
            for arg in args {
                check_expr(arg, env, registry)?;
            }
            Ok(OwnershipState::Owned)
        }

        Expr::DefMacro { params, body, .. } => {
            env.push_scope();
            for (param, _) in params {
                env.insert(param.0.clone(), OwnershipState::Owned);
            }
            check_expr(body, env, registry)?;
            env.pop_scope();
            Ok(OwnershipState::Owned)
        }

        Expr::SyntaxQuote(expr, _) | Expr::Unquote(expr, _) | Expr::Splicing(expr, _) => {
            check_expr(expr, env, registry)
        }

        Expr::List(_, _) | Expr::Vector(_, _) | Expr::Map(_, _) | Expr::Quote(_, _) => {
            Ok(OwnershipState::Owned)
        }
    }
}
