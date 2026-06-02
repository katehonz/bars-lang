//! Mini-interpreter for evaluating macro bodies at compile time.
//!
//! Macros are functions that receive AST nodes and return AST nodes.
//! This interpreter evaluates Bars expressions where the "values" are
//! themselves AST `Expr` nodes (or primitives like i64/bool).

use crate::ast::{Expr, Keyword, Program, Span, Symbol};
use anyhow::{bail, Result};
use std::collections::HashMap;

/// Runtime value in the macro interpreter
#[derive(Debug, Clone, PartialEq)]
pub enum MacroVal {
    /// An AST expression (the primary value type for macros)
    Expr(Expr),
    /// A primitive integer
    Number(i64),
    /// A primitive boolean
    Bool(bool),
    /// A string
    String(String),
    /// A keyword
    Keyword(Keyword),
    /// A function (params + body + captured env)
    Fn {
        params: Vec<Symbol>,
        body: Box<Expr>,
        env: HashMap<String, MacroVal>,
    },
    /// nil
    Nil,
}

impl MacroVal {
    /// Convert an AST expr to a MacroVal
    pub fn from_expr(expr: &Expr) -> Self {
        match expr {
            Expr::Number(n) => MacroVal::Number(*n),
            Expr::Bool(b) => MacroVal::Bool(*b),
            Expr::String(s) => MacroVal::String(s.clone()),
            Expr::Keyword(k) => MacroVal::Keyword(k.clone()),
            Expr::Symbol(s) if s.0 == "nil" => MacroVal::Nil,
            other => MacroVal::Expr(other.clone()),
        }
    }

    /// Convert back to AST expr
    pub fn to_expr(&self) -> Expr {
        match self {
            MacroVal::Number(n) => Expr::Number(*n),
            MacroVal::Bool(b) => Expr::Bool(*b),
            MacroVal::String(s) => Expr::String(s.clone()),
            MacroVal::Keyword(k) => Expr::Keyword(k.clone()),
            MacroVal::Expr(e) => e.clone(),
            MacroVal::Nil => Expr::Symbol(Symbol("nil".to_string())),
            MacroVal::Fn { .. } => Expr::Symbol(Symbol("<fn>".to_string())),
        }
    }

    pub fn is_truthy(&self) -> bool {
        !matches!(self, MacroVal::Bool(false) | MacroVal::Nil)
    }
}

/// Interpreter environment: stack of scopes
#[derive(Debug, Clone)]
pub struct InterpEnv {
    scopes: Vec<HashMap<String, MacroVal>>,
}

impl InterpEnv {
    pub fn new() -> Self {
        let mut builtins = HashMap::new();
        Self { scopes: vec![builtins] }
    }

    pub fn from_bindings(bindings: HashMap<String, MacroVal>) -> Self {
        Self { scopes: vec![bindings] }
    }

    pub fn push_scope(&mut self) {
        self.scopes.push(HashMap::new());
    }

    pub fn pop_scope(&mut self) {
        self.scopes.pop();
    }

    pub fn get(&self, name: &str) -> Option<MacroVal> {
        for scope in self.scopes.iter().rev() {
            if let Some(v) = scope.get(name) {
                return Some(v.clone());
            }
        }
        None
    }

    pub fn insert(&mut self, name: String, val: MacroVal) {
        if let Some(scope) = self.scopes.last_mut() {
            scope.insert(name, val);
        }
    }
}

/// Evaluate an expression in the macro interpreter
pub fn eval(expr: &Expr, env: &mut InterpEnv) -> Result<MacroVal> {
    match expr {
        Expr::Number(n) => Ok(MacroVal::Number(*n)),
        Expr::Bool(b) => Ok(MacroVal::Bool(*b)),
        Expr::String(s) => Ok(MacroVal::String(s.clone())),
        Expr::Keyword(k) => Ok(MacroVal::Keyword(k.clone())),
        Expr::Symbol(s) if s.0 == "nil" => Ok(MacroVal::Nil),
        Expr::Symbol(s) => {
            match env.get(&s.0) {
                Some(v) => Ok(v),
                None => Ok(MacroVal::Expr(Expr::Symbol(s.clone()))),
            }
        }

        Expr::Quote(inner, _) => Ok(MacroVal::Expr(*inner.clone())),

        Expr::SyntaxQuote(inner, _) => {
            let expanded = expand_syntax_quote(inner, env)?;
            Ok(MacroVal::Expr(expanded))
        }

        Expr::FnCall { func, args, .. } => {
            let func_val = eval(func, env)?;
            match func_val {
                MacroVal::Fn { params, body, env: captured_env } => {
                    let mut new_env = InterpEnv { scopes: vec![captured_env] };
                    new_env.push_scope();
                    for (i, param) in params.iter().enumerate() {
                        let arg_val = if i < args.len() {
                            eval(&args[i], env)?
                        } else {
                            MacroVal::Nil
                        };
                        new_env.insert(param.0.clone(), arg_val);
                    }
                    let result = eval(&body, &mut new_env)?;
                    Ok(result)
                }
                MacroVal::Expr(Expr::Symbol(s)) => {
                    // Built-in interpreter functions
                    eval_builtin(&s.0, args, env)
                }
                _ => bail!("Not a function: {:?}", func_val),
            }
        }

        Expr::Let { bindings, body, .. } => {
            env.push_scope();
            for (name, val_expr) in bindings {
                let val = eval(val_expr, env)?;
                env.insert(name.0.clone(), val);
            }
            let result = eval(body, env)?;
            env.pop_scope();
            Ok(result)
        }

        Expr::If { cond, then_branch, else_branch, .. } => {
            let cond_val = eval(cond, env)?;
            if cond_val.is_truthy() {
                eval(then_branch, env)
            } else {
                eval(else_branch, env)
            }
        }

        Expr::Do { exprs, .. } => {
            let mut last = MacroVal::Nil;
            for e in exprs {
                last = eval(e, env)?;
            }
            Ok(last)
        }

        Expr::List(items, span) => {
            // Treat bare list as a call if first item is callable, else as data
            if items.is_empty() {
                return Ok(MacroVal::Expr(Expr::List(vec![], span.clone())));
            }
            let func = eval(&items[0], env)?;
            let args: Vec<Expr> = items[1..].iter().map(|e| {
                match eval(e, env) {
                    Ok(MacroVal::Expr(e)) => e,
                    Ok(other) => other.to_expr(),
                    Err(_) => e.clone(),
                }
            }).collect();
            match func {
                MacroVal::Fn { params, body, env: captured_env } => {
                    let mut new_env = InterpEnv { scopes: vec![captured_env] };
                    new_env.push_scope();
                    for (i, param) in params.iter().enumerate() {
                        let arg_val = if i < args.len() {
                            MacroVal::Expr(args[i].clone())
                        } else {
                            MacroVal::Nil
                        };
                        new_env.insert(param.0.clone(), arg_val);
                    }
                    let result = eval(&body, &mut new_env)?;
                    Ok(result)
                }
                _ => Ok(MacroVal::Expr(Expr::List(
                    std::iter::once(func.to_expr()).chain(args.into_iter()).collect(),
                    span.clone()
                ))),
            }
        }

        Expr::Vector(items, span) => {
            let vals: Vec<Expr> = items.iter().map(|e| eval(e, env).map(|v| v.to_expr()).unwrap_or_else(|_| e.clone())).collect();
            Ok(MacroVal::Expr(Expr::Vector(vals, span.clone())))
        }

        Expr::Map(items, span) => {
            let vals: Vec<(Expr, Expr)> = items.iter().map(|(k, v)| {
                (eval(k, env).map(|v| v.to_expr()).unwrap_or_else(|_| k.clone()),
                 eval(v, env).map(|v| v.to_expr()).unwrap_or_else(|_| v.clone()))
            }).collect();
            Ok(MacroVal::Expr(Expr::Map(vals, span.clone())))
        }

        Expr::Defn { params, body, .. } => {
            let param_names: Vec<Symbol> = params.iter().map(|(s, _)| s.clone()).collect();
            let captured = env.scopes.first().cloned().unwrap_or_default();
            Ok(MacroVal::Fn { params: param_names, body: body.clone(), env: captured })
        }

        // DefMacro shouldn't be evaluated directly in macro bodies
        other => Ok(MacroVal::Expr(other.clone())),
    }
}

/// Expand a syntax-quoted expression
pub fn expand_syntax_quote(expr: &Expr, env: &mut InterpEnv) -> Result<Expr> {
    match expr {
        Expr::Unquote(inner, _) => {
            let val = eval(inner, env)?;
            Ok(val.to_expr())
        }
        Expr::Splicing(inner, _) => {
            let val = eval(inner, env)?;
            Ok(val.to_expr())
        }
        Expr::Symbol(s) => {
            Ok(Expr::Quote(Box::new(Expr::Symbol(s.clone())), Span::new(0, 0)))
        }
        Expr::List(items, span) => {
            let mut result = Vec::new();
            for item in items {
                if let Expr::Splicing(inner, _) = item {
                    let val = eval(inner, env)?;
                    match val {
                        MacroVal::Expr(Expr::List(lst, _)) | MacroVal::Expr(Expr::Vector(lst, _)) => {
                            for e in lst {
                                result.push(e);
                            }
                        }
                        other => {
                            result.push(other.to_expr());
                        }
                    }
                } else {
                    let expanded = expand_syntax_quote(item, env)?;
                    result.push(expanded);
                }
            }
            Ok(Expr::List(result, span.clone()))
        }
        Expr::Vector(items, span) => {
            let vals: Vec<Expr> = items.iter()
                .map(|e| expand_syntax_quote(e, env))
                .collect::<Result<Vec<_>>>()?;
            Ok(Expr::Vector(vals, span.clone()))
        }
        Expr::If { cond, then_branch, else_branch, span } => {
            Ok(Expr::If {
                cond: Box::new(expand_syntax_quote(cond, env)?),
                then_branch: Box::new(expand_syntax_quote(then_branch, env)?),
                else_branch: Box::new(expand_syntax_quote(else_branch, env)?),
                span: span.clone(),
            })
        }
        Expr::Do { exprs, span } => {
            let vals: Vec<Expr> = exprs.iter()
                .map(|e| expand_syntax_quote(e, env))
                .collect::<Result<Vec<_>>>()?;
            Ok(Expr::Do { exprs: vals, span: span.clone() })
        }
        Expr::Let { bindings, body, span } => {
            let new_bindings: Vec<(Symbol, Expr)> = bindings.iter()
                .map(|(name, val)| Ok((name.clone(), expand_syntax_quote(val, env)?)))
                .collect::<Result<Vec<_>>>()?;
            Ok(Expr::Let {
                bindings: new_bindings,
                body: Box::new(expand_syntax_quote(body, env)?),
                span: span.clone(),
            })
        }
        Expr::FnCall { func, args, span } => {
            Ok(Expr::FnCall {
                func: Box::new(expand_syntax_quote(func, env)?),
                args: args.iter().map(|a| expand_syntax_quote(a, env)).collect::<Result<Vec<_>>>()?,
                span: span.clone(),
            })
        }
        Expr::Loop { bindings, body, span } => {
            let new_bindings: Vec<(Symbol, Expr)> = bindings.iter()
                .map(|(name, val)| Ok((name.clone(), expand_syntax_quote(val, env)?)))
                .collect::<Result<Vec<_>>>()?;
            Ok(Expr::Loop {
                bindings: new_bindings,
                body: Box::new(expand_syntax_quote(body, env)?),
                span: span.clone(),
            })
        }
        Expr::Recur { args, span } => {
            Ok(Expr::Recur {
                args: args.iter().map(|a| expand_syntax_quote(a, env)).collect::<Result<Vec<_>>>()?,
                span: span.clone(),
            })
        }
        Expr::Def { name, value, span } => {
            Ok(Expr::Def {
                name: name.clone(),
                value: Box::new(expand_syntax_quote(value, env)?),
                span: span.clone(),
            })
        }
        Expr::Defn { name, params, body, ret_type, span } => {
            Ok(Expr::Defn {
                name: name.clone(),
                params: params.clone(),
                body: Box::new(expand_syntax_quote(body, env)?),
                ret_type: ret_type.clone(),
                span: span.clone(),
            })
        }
        Expr::DefMacro { name, params, body, span } => {
            Ok(Expr::DefMacro {
                name: name.clone(),
                params: params.clone(),
                body: Box::new(expand_syntax_quote(body, env)?),
                span: span.clone(),
            })
        }
        other => Ok(other.clone()),
    }
}

/// Evaluate built-in interpreter functions
fn eval_builtin(name: &str, args: &[Expr], env: &mut InterpEnv) -> Result<MacroVal> {
    match name {
        "list" => {
            let vals: Vec<Expr> = args.iter()
                .map(|e| eval(e, env).map(|v| v.to_expr()).unwrap_or_else(|_| e.clone()))
                .collect();
            Ok(MacroVal::Expr(Expr::List(vals, Span::new(0, 0))))
        }
        "cons" => {
            if args.len() < 2 {
                bail!("cons requires 2 arguments");
            }
            let head = eval(&args[0], env)?.to_expr();
            let tail = eval(&args[1], env)?;
            match tail {
                MacroVal::Expr(Expr::List(mut lst, span)) | MacroVal::Expr(Expr::Vector(mut lst, span)) => {
                    lst.insert(0, head);
                    Ok(MacroVal::Expr(Expr::List(lst, span)))
                }
                other => {
                    Ok(MacroVal::Expr(Expr::List(vec![head, other.to_expr()], Span::new(0, 0))))
                }
            }
        }
        "first" => {
            if args.is_empty() { bail!("first requires an argument"); }
            let val = eval(&args[0], env)?;
            match val {
                MacroVal::Expr(Expr::List(lst, _)) | MacroVal::Expr(Expr::Vector(lst, _)) => {
                    Ok(lst.first().map(|e| MacroVal::Expr(e.clone())).unwrap_or(MacroVal::Nil))
                }
                _ => Ok(MacroVal::Nil),
            }
        }
        "rest" => {
            if args.is_empty() { bail!("rest requires an argument"); }
            let val = eval(&args[0], env)?;
            match val {
                MacroVal::Expr(Expr::List(lst, span)) | MacroVal::Expr(Expr::Vector(lst, span)) => {
                    if lst.is_empty() {
                        Ok(MacroVal::Expr(Expr::List(vec![], span)))
                    } else {
                        Ok(MacroVal::Expr(Expr::List(lst[1..].to_vec(), span)))
                    }
                }
                _ => Ok(MacroVal::Expr(Expr::List(vec![], Span::new(0, 0)))),
            }
        }
        "second" => {
            if args.is_empty() { bail!("second requires an argument"); }
            let val = eval(&args[0], env)?;
            match val {
                MacroVal::Expr(Expr::List(lst, _)) | MacroVal::Expr(Expr::Vector(lst, _)) => {
                    Ok(lst.get(1).map(|e| MacroVal::Expr(e.clone())).unwrap_or(MacroVal::Nil))
                }
                _ => Ok(MacroVal::Nil),
            }
        }
        "third" => {
            if args.is_empty() { bail!("third requires an argument"); }
            let val = eval(&args[0], env)?;
            match val {
                MacroVal::Expr(Expr::List(lst, _)) | MacroVal::Expr(Expr::Vector(lst, _)) => {
                    Ok(lst.get(2).map(|e| MacroVal::Expr(e.clone())).unwrap_or(MacroVal::Nil))
                }
                _ => Ok(MacroVal::Nil),
            }
        }
        "count" => {
            if args.is_empty() { bail!("count requires an argument"); }
            let val = eval(&args[0], env)?;
            match val {
                MacroVal::Expr(Expr::List(lst, _)) | MacroVal::Expr(Expr::Vector(lst, _)) => {
                    Ok(MacroVal::Number(lst.len() as i64))
                }
                _ => Ok(MacroVal::Number(0)),
            }
        }
        "symbol?" => {
            if args.is_empty() { bail!("symbol? requires an argument"); }
            let val = eval(&args[0], env)?;
            Ok(MacroVal::Bool(matches!(val, MacroVal::Expr(Expr::Symbol(_)))))
        }
        "list?" => {
            if args.is_empty() { bail!("list? requires an argument"); }
            let val = eval(&args[0], env)?;
            Ok(MacroVal::Bool(matches!(val, MacroVal::Expr(Expr::List(_, _)))))
        }
        "vector?" => {
            if args.is_empty() { bail!("vector? requires an argument"); }
            let val = eval(&args[0], env)?;
            Ok(MacroVal::Bool(matches!(val, MacroVal::Expr(Expr::Vector(_, _)))))
        }
        "=" => {
            if args.len() < 2 { bail!("= requires 2 arguments"); }
            let a = eval(&args[0], env)?;
            let b = eval(&args[1], env)?;
            Ok(MacroVal::Bool(a == b))
        }
        "+" => {
            let mut sum = 0i64;
            for arg in args {
                match eval(arg, env)? {
                    MacroVal::Number(n) => sum += n,
                    _ => bail!("+ requires numbers"),
                }
            }
            Ok(MacroVal::Number(sum))
        }
        "-" => {
            if args.is_empty() { bail!("- requires at least 1 argument"); }
            let first = eval(&args[0], env)?;
            match first {
                MacroVal::Number(n) => {
                    if args.len() == 1 {
                        Ok(MacroVal::Number(-n))
                    } else {
                        let mut result = n;
                        for arg in &args[1..] {
                            match eval(arg, env)? {
                                MacroVal::Number(m) => result -= m,
                                _ => bail!("- requires numbers"),
                            }
                        }
                        Ok(MacroVal::Number(result))
                    }
                }
                _ => bail!("- requires numbers"),
            }
        }
        "*" => {
            let mut prod = 1i64;
            for arg in args {
                match eval(arg, env)? {
                    MacroVal::Number(n) => prod *= n,
                    _ => bail!("* requires numbers"),
                }
            }
            Ok(MacroVal::Number(prod))
        }
        "println" => {
            for arg in args {
                let val = eval(arg, env)?;
                eprintln!("[macro] {:?}", val);
            }
            Ok(MacroVal::Nil)
        }
        _ => bail!("Unknown macro function: {}", name),
    }
}
