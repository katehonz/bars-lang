use crate::ast::{Expr, Pattern, Program, Span, Type as AstType};
use crate::ownership::state::OwnershipState;
use std::collections::HashMap;
use thiserror::Error;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum OwnershipError {
    #[error("Use after move: variable '{0}' was moved and cannot be used again (at line {1}, col {2})")]
    UseAfterMove(String, usize, usize),
    #[error("Cannot borrow '{0}' as mutable because it is already borrowed (at line {1}, col {2})")]
    AlreadyBorrowed(String, usize, usize),
    #[error("Cannot borrow '{0}' as immutable because it is already mutably borrowed (at line {1}, col {2})")]
    AlreadyMutBorrowed(String, usize, usize),
    #[error("Cannot move '{0}' because it is currently borrowed (at line {1}, col {2})")]
    MoveWhileBorrowed(String, usize, usize),
    #[error("Variable '{0}' not found in scope (at line {1}, col {2})")]
    NotFound(String, usize, usize),
    #[error("Resource leak: '{0}' is owned but never consumed or dropped before it goes out of scope (at line {1}, col {2})")]
    ResourceLeak(String, usize, usize),
}

/// Registry of function signatures discovered during pre-scan
#[derive(Debug, Clone, Default)]
pub struct FunctionRegistry {
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

    /// Merge another environment conservatively (used after if/match branches).
    pub fn merge(&mut self, other: &OwnershipEnv) {
        if let (Some(self_top), Some(other_top)) = (self.scopes.last_mut(), other.scopes.last()) {
            for (name, other_state) in other_top.iter() {
                if let Some(self_state) = self_top.get(name) {
                    let merged = match (self_state, other_state) {
                        (OwnershipState::Moved, _) | (_, OwnershipState::Moved) => OwnershipState::Moved,
                        (OwnershipState::MutBorrowed, _) | (_, OwnershipState::MutBorrowed) => OwnershipState::Owned,
                        (OwnershipState::Borrowed { .. }, _) | (_, OwnershipState::Borrowed { .. }) => OwnershipState::Owned,
                        (OwnershipState::Copy, OwnershipState::Copy) => OwnershipState::Copy,
                        _ => OwnershipState::Owned,
                    };
                    self_top.insert(name.clone(), merged);
                }
            }
        }
    }

    /// NLL: after each statement in a Do block, release active borrows
    pub fn release_borrows(&mut self) {
        if let Some(top) = self.scopes.last_mut() {
            for (_, state) in top.iter_mut() {
                if matches!(state, OwnershipState::Borrowed { .. } | OwnershipState::MutBorrowed) {
                    *state = OwnershipState::Owned;
                }
            }
        }
    }

    /// Collect variables that are Owned (not Copy, not Moved) in the current scope
    pub fn owned_vars(&self) -> Vec<(String, OwnershipState)> {
        let mut result = Vec::new();
        if let Some(top) = self.scopes.last() {
            for (name, state) in top.iter() {
                if matches!(state, OwnershipState::Owned | OwnershipState::MutBorrowed) {
                    result.push((name.clone(), state.clone()));
                }
            }
        }
        result
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
        check_expr(expr, &mut env, &registry, expr.span())?;
    }
    Ok(())
}

/// Get a meaningful span for error reporting.
/// Atoms like Symbol/Number have (0,0) span; use parent_span instead.
fn err_span(expr: &Expr, parent: Span) -> Span {
    let s = expr.span();
    if s.line == 0 && s.col == 0 { parent } else { s }
}

/// Determine if an expression evaluates to a Copy type
fn expr_is_copy(expr: &Expr, _registry: &FunctionRegistry) -> bool {
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
        Expr::Symbol(_sym) => false,
        _ => false,
    }
}

/// Add pattern bindings to the environment
fn add_pattern_bindings(
    pattern: &Pattern,
    env: &mut OwnershipEnv,
    _registry: &FunctionRegistry,
) {
    match pattern {
        Pattern::Binding(sym) => {
            env.insert(sym.0.clone(), OwnershipState::Owned);
        }
        Pattern::Vector(patterns, _) | Pattern::List(patterns, _) | Pattern::Struct { fields: patterns, .. } => {
            for p in patterns {
                add_pattern_bindings(p, env, _registry);
            }
        }
        _ => {}
    }
}

/// Check an expression, returning the ownership state of its result.
/// `parent_span` is the span of the enclosing expression for error reporting on atoms.
fn check_expr(
    expr: &Expr,
    env: &mut OwnershipEnv,
    registry: &FunctionRegistry,
    parent_span: Span,
) -> Result<OwnershipState, OwnershipError> {
    let span = err_span(expr, parent_span);

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
                    Err(OwnershipError::UseAfterMove(name.clone(), span.line, span.col))
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
                let _val_state = check_expr(val_expr, env, registry, span.clone())?;
                // NLL: after binding initializer, release borrows
                env.release_borrows();

                if let Expr::Symbol(sym) = val_expr {
                    match env.get(&sym.0) {
                        Some(OwnershipState::Borrowed { .. }) => {
                            return Err(OwnershipError::MoveWhileBorrowed(sym.0.clone(), span.line, span.col));
                        }
                        Some(OwnershipState::MutBorrowed) => {
                            return Err(OwnershipError::MoveWhileBorrowed(sym.0.clone(), span.line, span.col));
                        }
                        Some(OwnershipState::Copy) => {}
                        _ => {
                            env.update(&sym.0, OwnershipState::Moved);
                        }
                    }
                }
                if expr_is_copy(val_expr, registry) {
                    env.insert(name.0.clone(), OwnershipState::Copy);
                } else {
                    env.insert(name.0.clone(), OwnershipState::Owned);
                }
            }
            let body_state = check_expr(body, env, registry, span.clone())?;
            // NLL: release borrows before scope ends
            env.release_borrows();
            env.pop_scope();
            Ok(body_state)
        }

        Expr::If { cond, then_branch, else_branch, span: if_span } => {
            check_expr(cond, env, registry, if_span.clone())?;
            // NLL: release borrows after condition
            env.release_borrows();

            let mut then_env = env.clone();
            check_expr(then_branch, &mut then_env, registry, if_span.clone())?;

            let mut else_env = env.clone();
            check_expr(else_branch, &mut else_env, registry, if_span.clone())?;

            env.merge(&then_env);
            env.merge(&else_env);
            // NLL: release borrows after branch merge
            env.release_borrows();

            Ok(OwnershipState::Owned)
        }

        Expr::Match { expr: matched, arms, span: match_span } => {
            check_expr(matched, env, registry, match_span.clone())?;
            env.release_borrows();

            let mut arm_envs = Vec::new();
            for (pattern, body) in arms {
                let mut arm_env = env.clone();
                arm_env.push_scope();
                add_pattern_bindings(pattern, &mut arm_env, registry);
                check_expr(body, &mut arm_env, registry, match_span.clone())?;
                arm_env.pop_scope();
                arm_envs.push(arm_env);
            }
            for arm_env in arm_envs {
                env.merge(&arm_env);
            }
            env.release_borrows();
            Ok(OwnershipState::Owned)
        }

        Expr::Do { exprs, .. } => {
            let mut last = OwnershipState::Owned;
            for e in exprs {
                last = check_expr(e, env, registry, span.clone())?;
                // NLL: release borrows after each statement
                env.release_borrows();
            }
            Ok(last)
        }

        Expr::Def { name, value, span: def_span } => {
            let _val_state = check_expr(value, env, registry, def_span.clone())?;
            env.release_borrows();

            if let Expr::Symbol(sym) = value.as_ref() {
                match env.get(&sym.0) {
                    Some(OwnershipState::Borrowed { .. }) => {
                        return Err(OwnershipError::MoveWhileBorrowed(sym.0.clone(), def_span.line, def_span.col));
                    }
                    Some(OwnershipState::MutBorrowed) => {
                        return Err(OwnershipError::MoveWhileBorrowed(sym.0.clone(), def_span.line, def_span.col));
                    }
                    Some(OwnershipState::Copy) => {}
                    _ => {
                        env.update(&sym.0, OwnershipState::Moved);
                    }
                }
            }
            if expr_is_copy(value, registry) {
                env.insert(name.0.clone(), OwnershipState::Copy);
            } else {
                env.insert(name.0.clone(), OwnershipState::Owned);
            }
            Ok(OwnershipState::Owned)
        }

        Expr::Defn { name: _, params, body, span: defn_span, .. } => {
            // Insert params into the current scope so they survive release_borrows in the body.
            for (param, param_ty) in params {
                let state = match param_ty {
                    Some(AstType::MutRef(_)) => OwnershipState::MutBorrowed,
                    Some(AstType::Ref(_)) => OwnershipState::Borrowed { count: 1 },
                    _ => OwnershipState::Owned,
                };
                env.insert(param.0.clone(), state);
            }
            env.push_scope();
            check_expr(body, env, registry, defn_span.clone())?;

            // Drop check: warn about owned resources not consumed before function end.
            // Skip function parameters — they are owned by the caller, not locally allocated.
            let param_names: std::collections::HashSet<String> = params.iter().map(|(p, _)| p.0.clone()).collect();
            for (var_name, _state) in env.owned_vars() {
                if !param_names.contains(&var_name) {
                    return Err(OwnershipError::ResourceLeak(
                        var_name, defn_span.line, defn_span.col,
                    ));
                }
            }

            env.release_borrows();
            env.pop_scope();
            Ok(OwnershipState::Owned)
        }

        Expr::FnCall { func: func_expr, args, span: call_span } => {
            check_expr(func_expr, env, registry, call_span.clone())?;

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
                                    return Err(OwnershipError::UseAfterMove(name.clone(), call_span.line, call_span.col));
                                }
                                Some(OwnershipState::Copy) => {}
                                Some(OwnershipState::MutBorrowed) => {
                                    return Err(OwnershipError::AlreadyBorrowed(name.clone(), call_span.line, call_span.col));
                                }
                                Some(OwnershipState::Borrowed { .. }) if *is_mut => {
                                    return Err(OwnershipError::AlreadyBorrowed(name.clone(), call_span.line, call_span.col));
                                }
                                Some(OwnershipState::Borrowed { .. }) => {}
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
                        check_expr(inner, env, registry, call_span.clone())?;
                    }
                    Expr::Symbol(sym) => {
                        // If function expects a borrow but symbol is passed directly, error
                        // unless it's already borrowed (reborrow) or we can do an implicit borrow.
                        if matches!(expected_ty, Some(AstType::Ref(_)) | Some(AstType::MutRef(_))) {
                            match env.get(&sym.0) {
                                Some(OwnershipState::Borrowed { .. })
                                | Some(OwnershipState::MutBorrowed) => {
                                    // Reborrow of an already-borrowed value is allowed.
                                }
                                Some(OwnershipState::Owned) => {
                                    // Implicit borrow for owned values passed to borrow parameters.
                                    if matches!(expected_ty, Some(AstType::MutRef(_))) {
                                        env.update(&sym.0, OwnershipState::MutBorrowed);
                                    } else {
                                        env.update(&sym.0, OwnershipState::Borrowed { count: 1 });
                                    }
                                }
                                Some(OwnershipState::Copy) => {
                                    // Copy types don't need explicit borrow, they are trivially copyable.
                                }
                                _ => {
                                    return Err(OwnershipError::AlreadyBorrowed(format!(
                                        "passing '{}' to function expecting borrow - use '^{}' instead",
                                        sym.0, sym.0
                                    ), call_span.line, call_span.col));
                                }
                            }
                        }
                        check_expr(arg, env, registry, call_span.clone())?;
                    }
                    other => {
                        check_expr(other, env, registry, call_span.clone())?;
                    }
                }
            }
            // NLL: after function call, release borrows taken for this call
            env.release_borrows();
            Ok(OwnershipState::Owned)
        }

        Expr::Borrow(inner, is_mut, _) => {
            if let Expr::Symbol(sym) = inner.as_ref() {
                let name = &sym.0;
                match env.get(name) {
                    Some(OwnershipState::Moved) => {
                        return Err(OwnershipError::UseAfterMove(name.clone(), span.line, span.col));
                    }
                    Some(OwnershipState::Copy) => {}
                    Some(OwnershipState::MutBorrowed) => {
                        return Err(OwnershipError::AlreadyMutBorrowed(name.clone(), span.line, span.col));
                    }
                    Some(OwnershipState::Borrowed { .. }) if *is_mut => {
                        return Err(OwnershipError::AlreadyBorrowed(name.clone(), span.line, span.col));
                    }
                    Some(OwnershipState::Borrowed { .. }) => {}
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
            check_expr(inner, env, registry, span)
        }

        Expr::Loop { bindings, body, span: loop_span } => {
            env.push_scope();
            for (name, val_expr) in bindings {
                let _val_state = check_expr(val_expr, env, registry, loop_span.clone())?;
                env.release_borrows();
                if let Expr::Symbol(sym) = val_expr {
                    env.update(&sym.0, OwnershipState::Moved);
                }
                env.insert(name.0.clone(), OwnershipState::Owned);
            }
            let body_state = check_expr(body, env, registry, loop_span.clone())?;
            env.release_borrows();
            env.pop_scope();
            Ok(body_state)
        }

        Expr::Recur { args, span: recur_span } => {
            for arg in args {
                check_expr(arg, env, registry, recur_span.clone())?;
            }
            env.release_borrows();
            Ok(OwnershipState::Owned)
        }

        Expr::DefMacro { params, body, span: macro_span, .. } => {
            for (param, _) in params {
                env.insert(param.0.clone(), OwnershipState::Owned);
            }
            env.push_scope();
            check_expr(body, env, registry, macro_span.clone())?;
            env.release_borrows();
            env.pop_scope();
            Ok(OwnershipState::Owned)
        }

        Expr::Lambda { params, body, span: lambda_span } => {
            for (param, param_ty) in params {
                let state = match param_ty {
                    Some(AstType::MutRef(_)) => OwnershipState::MutBorrowed,
                    Some(AstType::Ref(_)) => OwnershipState::Borrowed { count: 1 },
                    _ => OwnershipState::Owned,
                };
                env.insert(param.0.clone(), state);
            }
            env.push_scope();
            check_expr(body, env, registry, lambda_span.clone())?;
            env.release_borrows();
            env.pop_scope();
            Ok(OwnershipState::Owned)
        }

        Expr::SyntaxQuote(inner, _) | Expr::Unquote(inner, _) | Expr::Splicing(inner, _) => {
            check_expr(inner, env, registry, span)
        }

        Expr::DefStruct { .. } => Ok(OwnershipState::Owned),

        Expr::FieldAccess { expr: inner, field, span: field_span } => {
            if let Expr::Symbol(sym) = inner.as_ref() {
                match env.get(&sym.0) {
                    Some(OwnershipState::Moved) => {
                        return Err(OwnershipError::UseAfterMove(
                            format!("{} (field .{})", sym.0, field.0),
                            field_span.line, field_span.col,
                        ));
                    }
                    _ => {}
                }
            }
            check_expr(inner, env, registry, field_span.clone())
        }

        Expr::List(_, _) | Expr::Vector(_, _) | Expr::Quote(_, _) => {
            Ok(OwnershipState::Owned)
        }
    }
}
