use crate::ast::{self, Expr, Program};
use std::collections::HashMap;
use std::fmt;

// ── Inference Types ──────────────────────────────────────────────────────────

pub type TypeVarId = usize;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Type {
    I64,
    F64,
    Bool,
    Void,
    String,
    /// A type variable (to be unified)
    Var(TypeVarId),
    /// Function type: params → return
    Fun(Vec<Type>, Box<Type>),
    /// Named type (structs, aliases)
    Named(String),
}

impl fmt::Display for Type {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Type::I64 => write!(f, "i64"),
            Type::F64 => write!(f, "f64"),
            Type::Bool => write!(f, "bool"),
            Type::Void => write!(f, "void"),
            Type::String => write!(f, "string"),
            Type::Var(id) => write!(f, "'t{}", id),
            Type::Fun(params, ret) => {
                write!(f, "(")?;
                for (i, p) in params.iter().enumerate() {
                    if i > 0 { write!(f, ", ")?; }
                    write!(f, "{}", p)?;
                }
                write!(f, ") → {}", ret)
            }
            Type::Named(n) => write!(f, "{}", n),
        }
    }
}

/// A type scheme: forall vars. type
#[derive(Debug, Clone)]
pub struct TypeScheme {
    pub vars: Vec<TypeVarId>,
    pub ty: Type,
}

impl TypeScheme {
    pub fn mono(ty: Type) -> Self {
        Self { vars: vec![], ty }
    }
}

/// Type environment: maps variable names to their type schemes
pub type TypeEnv = HashMap<String, TypeScheme>;

/// A substitution from type variables to types
pub type Substitution = HashMap<TypeVarId, Type>;

// ── Constraints ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct Constraint(pub Type, pub Type);

// ── Inference Context ────────────────────────────────────────────────────────

pub struct InferCtx {
    var_counter: TypeVarId,
    constraints: Vec<Constraint>,
}

impl InferCtx {
    pub fn new() -> Self {
        Self { var_counter: 0, constraints: Vec::new() }
    }

    pub fn fresh_var(&mut self) -> Type {
        let id = self.var_counter;
        self.var_counter += 1;
        Type::Var(id)
    }

    pub fn constrain(&mut self, a: Type, b: Type) {
        self.constraints.push(Constraint(a, b));
    }

    /// Convert `ast::Type` annotation to inference `Type`.
    /// Ref/MutRef annotations are ignored during inference (handled by ownership checker).
    fn from_ast_type(ty: &ast::Type) -> Type {
        match ty {
            ast::Type::I64 => Type::I64,
            ast::Type::F64 => Type::F64,
            ast::Type::Bool => Type::Bool,
            ast::Type::Void => Type::Void,
            ast::Type::Ref(inner) => Self::from_ast_type(inner),
            ast::Type::MutRef(inner) => Self::from_ast_type(inner),
            ast::Type::Unknown => Type::Var(usize::MAX), // will be replaced
            ast::Type::Named(n) => Type::Named(n.clone()),
        }
    }
}

// ── Inference ────────────────────────────────────────────────────────────────

impl InferCtx {
/// Infer types for all top-level expressions in a program.
    /// Returns substitution AND a map of definition name → inferred type.
    pub fn infer_program(&mut self, program: &Program) -> Result<(Substitution, Vec<(String, Type)>), TypeError> {
        let mut env: TypeEnv = self.builtin_env();
        let mut defn_types: Vec<(String, Type)> = Vec::new();

        // Register struct names as constructors
        for expr in &program.exprs {
            if let Expr::DefStruct { name, fields, .. } = expr {
                env.insert(name.0.clone(), TypeScheme::mono(Type::Named(name.0.clone())));
                let param_tys: Vec<Type> = (0..fields.len()).map(|_| self.fresh_var()).collect();
                let ctor_ty = Type::Fun(param_tys, Box::new(Type::Named(name.0.clone())));
                env.insert(name.0.clone(), TypeScheme::mono(ctor_ty));
            }
        }

        // Infer types for all top-level expressions
        for expr in &program.exprs {
            match expr {
                Expr::Defn { name, params, body, ret_type, .. } => {
                    let mut func_env = env.clone();
                    let mut param_types = Vec::new();
                    for (pname, ptype) in params {
                        let ity = match ptype {
                            Some(at) => Self::from_ast_type(at),
                            None => self.fresh_var(),
                        };
                        func_env.insert(pname.0.clone(), TypeScheme::mono(ity.clone()));
                        param_types.push(ity);
                    }
                    let body_ty = self.infer_expr(&mut func_env, body)?;
                    let fresh_ret = self.fresh_var();
                    let ret_constraint = match ret_type {
                        Some(at) => Self::from_ast_type(at),
                        None => fresh_ret,
                    };
                    self.constrain(body_ty.clone(), ret_constraint);
                    let fn_ty = Type::Fun(param_types, Box::new(body_ty.clone()));
                    env.insert(name.0.clone(), TypeScheme::mono(fn_ty));
                    defn_types.push((name.0.clone(), body_ty));
                }
                Expr::Def { name, value, .. } => {
                    let val_ty = self.infer_expr(&mut env.clone(), value)?;
                    env.insert(name.0.clone(), TypeScheme::mono(val_ty.clone()));
                    defn_types.push((name.0.clone(), val_ty));
                }
                Expr::FnCall { .. } => {
                    let _ = self.infer_expr(&mut env.clone(), expr)?;
                }
                _ => {}
            }
        }

        let subst = self.solve()?;
        // Apply substitution to defn_types
        let defn_types = defn_types.into_iter()
            .map(|(name, ty)| (name, apply_subst(&subst, &ty)))
            .collect();
        Ok((subst, defn_types))
    }

    fn infer_expr(&mut self, env: &mut TypeEnv, expr: &Expr) -> Result<Type, TypeError> {
        let span = expr.span();
        match expr {
            Expr::Number(_) => Ok(Type::I64),
            Expr::Float(_) => Ok(Type::F64),
            Expr::Bool(_) => Ok(Type::Bool),
            Expr::String(_) => Ok(Type::String),
            Expr::Symbol(sym) => {
                match env.get(&sym.0) {
                    Some(scheme) => {
                        let ty = self.instantiate(scheme);
                        Ok(ty)
                    }
                    None => Err(TypeError::UndefinedVar(sym.0.clone(), span.line, span.col)),
                }
            }
            Expr::Keyword(_) => Ok(Type::String),

            Expr::Let { bindings, body, span: _let_span } => {
                for (name, val_expr) in bindings {
                    let val_ty = self.infer_expr(env, val_expr)?;
                    env.insert(name.0.clone(), TypeScheme::mono(val_ty));
                }
                self.infer_expr(env, body)
            }

            Expr::If { cond, then_branch, else_branch, span: _if_span } => {
                let cond_ty = self.infer_expr(env, cond)?;
                let then_ty = self.infer_expr(env, then_branch)?;
                let else_ty = self.infer_expr(env, else_branch)?;
                self.constrain(then_ty.clone(), else_ty);
                self.constrain(cond_ty, Type::Bool);
                Ok(then_ty)
            }

            Expr::Do { exprs, .. } => {
                let mut last = Type::Void;
                for e in exprs {
                    last = self.infer_expr(env, e)?;
                }
                Ok(last)
            }

            Expr::Def { name, value, span: _def_span } => {
                let val_ty = self.infer_expr(env, value)?;
                env.insert(name.0.clone(), TypeScheme::mono(val_ty.clone()));
                Ok(val_ty)
            }

            Expr::Defn { .. } => {
                // Handled at top level
                Ok(Type::Void)
            }

            Expr::FnCall { func, args, span: _call_span } => {
                let func_ty = self.infer_expr(env, func)?;
                let mut arg_types = Vec::new();
                for arg in args {
                    let aty = self.infer_expr(env, arg)?;
                    arg_types.push(aty);
                }
                let ret_ty = self.fresh_var();
                // If known function type, unify; otherwise use fresh vars for params
                match &func_ty {
                    Type::Fun(params, ret) => {
                        for (i, aty) in arg_types.iter().enumerate() {
                            if i < params.len() {
                                self.constrain(aty.clone(), params[i].clone());
                            }
                            // extra args are accepted (variadic)
                        }
                        self.constrain(ret_ty.clone(), ret.as_ref().clone());
                    }
                    _ => {
                        // Unknown function type — treat args freely
                        let param_tys: Vec<Type> = arg_types.iter().map(|_| self.fresh_var()).collect();
                        self.constrain(func_ty.clone(), Type::Fun(param_tys, Box::new(ret_ty.clone())));
                    }
                }
                Ok(ret_ty)
            }

            Expr::Loop { bindings, body, span: _loop_span } => {
                for (name, val_expr) in bindings {
                    let val_ty = self.infer_expr(env, val_expr)?;
                    env.insert(name.0.clone(), TypeScheme::mono(val_ty));
                }
                self.infer_expr(env, body)
            }

            Expr::Recur { args, .. } => {
                for arg in args {
                    let _ = self.infer_expr(env, arg)?;
                }
                // recur never returns — return a fresh type var that unifies with anything
                Ok(self.fresh_var())
            }

            Expr::Match { expr: matched, arms, span: _match_span } => {
                let _mat_ty = self.infer_expr(env, matched)?;
                let result_ty = self.fresh_var();
                for (_, body) in arms {
                    let arm_ty = self.infer_expr(env, body)?;
                    self.constrain(result_ty.clone(), arm_ty);
                }
                Ok(result_ty)
            }

            Expr::DefStruct { name, fields: _, .. } => {
                env.insert(name.0.clone(), TypeScheme::mono(Type::Named(name.0.clone())));
                Ok(Type::Void)
            }

            Expr::FieldAccess { expr: inner, field: _, span: _field_span } => {
                let _base_ty = self.infer_expr(env, inner)?;
                // Field access: return a fresh var for the field type
                // (proper struct field typing requires struct field type info)
                Ok(self.fresh_var())
            }

            Expr::Borrow(inner, _, _) => {
                self.infer_expr(env, inner)
            }

            // Fallthrough for unhandled forms
            Expr::SyntaxQuote(inner, _)
            | Expr::Unquote(inner, _)
            | Expr::Splicing(inner, _)
            | Expr::Quote(inner, _) => {
                self.infer_expr(env, inner)
            }

            Expr::Lambda { params, body, .. } => {
                let mut param_types = Vec::new();
                for (pname, ptype) in params {
                    let ity = match ptype {
                        Some(at) => InferCtx::from_ast_type(at),
                        None => self.fresh_var(),
                    };
                    env.insert(pname.0.clone(), TypeScheme::mono(ity.clone()));
                    param_types.push(ity);
                }
                let body_ty = self.infer_expr(env, body)?;
                Ok(Type::Fun(param_types, Box::new(body_ty)))
            }

            Expr::DefMacro { .. } => Ok(Type::Void),
            Expr::Vector(_, _) | Expr::List(_, _) => {
                Ok(Type::Named("collection".to_string()))
            }
        }
    }

    /// Instantiate a type scheme: replace bound vars with fresh ones
    fn instantiate(&mut self, scheme: &TypeScheme) -> Type {
        let mut subst: Substitution = HashMap::new();
        for var in &scheme.vars {
            subst.insert(*var, self.fresh_var());
        }
        apply_subst(&subst, &scheme.ty)
    }

    /// Pre-populated environment with built-in functions
    fn builtin_env(&mut self) -> TypeEnv {
        let mut env = HashMap::new();

        // Arithmetic: (i64, i64) → i64
        let arith = TypeScheme::mono(Type::Fun(vec![Type::I64, Type::I64], Box::new(Type::I64)));
        let cmp = TypeScheme::mono(Type::Fun(vec![Type::I64, Type::I64], Box::new(Type::Bool)));
        let unary = TypeScheme::mono(Type::Fun(vec![Type::I64], Box::new(Type::I64)));
        let unary_bool = TypeScheme::mono(Type::Fun(vec![Type::I64], Box::new(Type::Bool)));

        for name in &["+", "-", "*", "/", "%", "max", "min", "gcd", "lcm"] {
            env.insert(name.to_string(), arith.clone());
        }
        for name in &["=", "!=", "<", ">", "<=", ">="] {
            env.insert(name.to_string(), cmp.clone());
        }
        for name in &["inc", "dec", "abs", "square", "cube", "factorial", "fib"] {
            env.insert(name.to_string(), unary.clone());
        }
        for name in &["even?", "odd?", "zero?", "pos?", "neg?"] {
            env.insert(name.to_string(), unary_bool.clone());
        }
        env.insert("not".to_string(), TypeScheme::mono(Type::Fun(vec![Type::Bool], Box::new(Type::Bool))));

        // I/O: (i64) → i64 (returns 0)
        let print_i64 = TypeScheme::mono(Type::Fun(vec![Type::I64], Box::new(Type::I64)));
        let print_str = TypeScheme::mono(Type::Fun(vec![Type::String], Box::new(Type::I64)));
        let print_none = TypeScheme::mono(Type::Fun(vec![], Box::new(Type::I64)));
        env.insert("println".to_string(), print_i64.clone());
        env.insert("print".to_string(), print_i64);
        env.insert("print-str".to_string(), print_str);
        env.insert("newline".to_string(), print_none);

        // Collection ops — vector can take any number of args
        let vec_new = TypeScheme::mono(Type::Fun(vec![], Box::new(Type::Named("vector".to_string()))));
        let push = TypeScheme::mono(Type::Fun(vec![Type::Named("vector".to_string()), Type::I64], Box::new(Type::I64)));
        let get = TypeScheme::mono(Type::Fun(vec![Type::Named("vector".to_string()), Type::I64], Box::new(Type::I64)));
        let count = TypeScheme::mono(Type::Fun(vec![Type::Named("vector".to_string())], Box::new(Type::I64)));
        env.insert("vector".to_string(), vec_new);
        env.insert("push".to_string(), push);
        env.insert("get".to_string(), get);
        env.insert("count".to_string(), count);
        env.insert("first".to_string(), unary.clone());
        env.insert("last".to_string(), unary);
        env.insert("nth".to_string(), TypeScheme::mono(Type::Fun(vec![Type::Named("vector".to_string()), Type::I64], Box::new(Type::I64))));

        let map_new = TypeScheme::mono(Type::Fun(vec![], Box::new(Type::Named("map".to_string()))));
        let map_op = TypeScheme::mono(Type::Fun(vec![Type::Named("map".to_string()), Type::I64], Box::new(Type::I64)));
        let map_set = TypeScheme::mono(Type::Fun(vec![
            Type::Named("map".to_string()), Type::I64, Type::I64,
        ], Box::new(Type::I64)));
        env.insert("map".to_string(), map_new);
        env.insert("map-get".to_string(), map_op.clone());
        env.insert("map_set".to_string(), map_set.clone());
        env.insert("map-count".to_string(), map_op.clone());
        env.insert("map-get".to_string(), map_op);
        env.insert("map-set".to_string(), map_set);

        // String ops
        env.insert("str".to_string(), TypeScheme::mono(Type::Fun(vec![Type::I64], Box::new(Type::String))));
        env.insert("str-count".to_string(), TypeScheme::mono(Type::Fun(vec![Type::String], Box::new(Type::I64))));

        env
    }

    /// Solve accumulated constraints via unification
    pub fn solve(&mut self) -> Result<Substitution, TypeError> {
        let mut subst: Substitution = HashMap::new();
        for Constraint(a, b) in std::mem::take(&mut self.constraints) {
            let a_sub = apply_subst(&subst, &a);
            let b_sub = apply_subst(&subst, &b);
            unify(&a_sub, &b_sub, &mut subst)?;
        }
        Ok(subst)
    }
}

// ── Unification ──────────────────────────────────────────────────────────────

fn unify(a: &Type, b: &Type, subst: &mut Substitution) -> Result<(), TypeError> {
    let a = normalize(a, subst);
    let b = normalize(b, subst);

    match (&a, &b) {
        _ if a == b => Ok(()),

        (Type::Var(id_a), _) => {
            if occurs(*id_a, &b, subst) {
                Err(TypeError::Circular(*id_a, b.clone()))
            } else {
                subst.insert(*id_a, b);
                Ok(())
            }
        }
        (_, Type::Var(id_b)) => {
            if occurs(*id_b, &a, subst) {
                Err(TypeError::Circular(*id_b, a.clone()))
            } else {
                subst.insert(*id_b, a);
                Ok(())
            }
        }
        (Type::Fun(pa, ra), Type::Fun(pb, rb)) => {
            if pa.len() != pb.len() {
                return Err(TypeError::Mismatch(a.clone(), b.clone()));
            }
            for (ai, bi) in pa.iter().zip(pb.iter()) {
                unify(ai, bi, subst)?;
            }
            unify(ra, rb, subst)
        }
        (Type::Named(na), Type::Named(nb)) if na == nb => Ok(()),

        _ => Err(TypeError::Mismatch(a.clone(), b.clone())),
    }
}

fn normalize(ty: &Type, subst: &Substitution) -> Type {
    match ty {
        Type::Var(id) => {
            if let Some(t) = subst.get(id) {
                normalize(t, subst)
            } else {
                ty.clone()
            }
        }
        _ => ty.clone(),
    }
}

fn occurs(var: TypeVarId, ty: &Type, subst: &Substitution) -> bool {
    let ty = normalize(ty, subst);
    match &ty {
        Type::Var(id) => *id == var,
        Type::Fun(params, ret) => {
            params.iter().any(|p| occurs(var, p, subst)) || occurs(var, ret, subst)
        }
        _ => false,
    }
}

pub fn apply_subst(subst: &Substitution, ty: &Type) -> Type {
    match ty {
        Type::Var(id) => {
            if let Some(t) = subst.get(id) {
                apply_subst(subst, t)
            } else {
                ty.clone()
            }
        }
        Type::Fun(params, ret) => {
            Type::Fun(
                params.iter().map(|p| apply_subst(subst, p)).collect(),
                Box::new(apply_subst(subst, ret)),
            )
        }
        other => other.clone(),
    }
}

// ── Type Errors ──────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub enum TypeError {
    Mismatch(Type, Type),
    UndefinedVar(String, usize, usize),
    Circular(TypeVarId, Type),
}

impl fmt::Display for TypeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TypeError::Mismatch(a, b) => write!(f, "Type mismatch: expected {}, found {}", a, b),
            TypeError::UndefinedVar(name, line, col) => write!(f, "Undefined variable '{}' at line {}, col {}", name, line, col),
            TypeError::Circular(id, ty) => write!(f, "Circular type: 't{} appears in {}", id, ty),
        }
    }
}
