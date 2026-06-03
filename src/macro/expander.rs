use crate::ast::{Expr, Program, Span, Symbol};
use crate::r#macro::interpreter::{eval, InterpEnv, MacroVal};
use std::collections::HashMap;
use thiserror::Error;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum MacroError {
    #[error("Macro '{0}' expects at least {1} arguments, got {2}")]
    WrongArity(String, usize, usize),
    #[error("Unknown macro: {0}")]
    UnknownMacro(String),
    #[error("Invalid syntax for macro '{0}'")]
    InvalidSyntax(String),
    #[error("Macro evaluation error: {0}")]
    EvalError(String),
}

impl From<anyhow::Error> for MacroError {
    fn from(e: anyhow::Error) -> Self {
        MacroError::EvalError(e.to_string())
    }
}

/// Expand all macros in a program (built-in + user-defined)
pub fn expand_program(program: &Program) -> Result<Program, MacroError> {
    // First pass: collect all defmacro definitions
    let mut macro_env: HashMap<String, Expr> = HashMap::new();
    for expr in &program.exprs {
        if let Expr::DefMacro { name, params, body, .. } = expr {
            macro_env.insert(name.0.clone(), Expr::Defn {
                name: name.clone(),
                params: params.clone(),
                body: body.clone(),
                ret_type: None,
                span: Span::new(0, 0),
            });
        }
    }

    // Second pass: expand all expressions
    let mut new_exprs = Vec::new();
    for expr in &program.exprs {
        // Skip defmacro forms themselves in the output (they are compile-time only)
        if matches!(expr, Expr::DefMacro { .. }) {
            continue;
        }
        new_exprs.push(expand_expr(expr, &macro_env)?);
    }
    Ok(Program { exprs: new_exprs })
}

/// Expand macros in a single expression
fn expand_expr(expr: &Expr, macro_env: &HashMap<String, Expr>) -> Result<Expr, MacroError> {
    match expr {
        // Don't expand inside quote
        Expr::Quote(inner, span) => Ok(Expr::Quote(inner.clone(), span.clone())),

        // Expand function calls
        Expr::FnCall { func, args, span } => {
            let expanded_func = expand_expr(func, macro_env)?;
            // Unwrap quoted symbols from syntax-quote
            let expanded_func = match expanded_func {
                Expr::Quote(inner, _) => *inner,
                other => other,
            };
            let expanded_args: Result<Vec<_>, _> = args.iter().map(|a| expand_expr(a, macro_env)).collect();
            let expanded_args = expanded_args?;

            // Check if func is a macro name
            if let Expr::Symbol(sym) = &expanded_func {
                if let Some(expanded) = try_expand_macro(&sym.0, &expanded_args, span, macro_env)? {
                    // Recursively expand the macro result (to unwrap quoted funcs, etc.)
                    return expand_expr(&expanded, macro_env);
                }
            }

            Ok(Expr::FnCall {
                func: Box::new(expanded_func),
                args: expanded_args,
                span: span.clone(),
            })
        }

        // Lists produced by macro expansion should be treated as function calls
        Expr::List(list, span) => {
            if list.is_empty() {
                Ok(Expr::List(list.clone(), span.clone()))
            } else {
                let func = expand_expr(&list[0], macro_env)?;
                let args: Result<Vec<_>, _> = list[1..].iter().map(|a| expand_expr(a, macro_env)).collect();
                let args = args?;
                // Unwrap quoted symbols (from syntax-quote)
                let func = match &func {
                    Expr::Quote(inner, _) => *inner.clone(),
                    _ => func,
                };
                if let Expr::Symbol(sym) = &func {
                    if let Some(expanded) = try_expand_macro(&sym.0, &args, span, macro_env)? {
                        return Ok(expanded);
                    }
                }
                Ok(Expr::FnCall {
                    func: Box::new(func),
                    args,
                    span: span.clone(),
                })
            }
        }

        // Recursively expand other expressions
        Expr::Let { bindings, body, span } => {
            let new_bindings: Result<Vec<_>, MacroError> = bindings
                .iter()
                .map(|(name, val)| Ok((name.clone(), expand_expr(val, macro_env)?)))
                .collect();
            Ok(Expr::Let {
                bindings: new_bindings?,
                body: Box::new(expand_expr(body, macro_env)?),
                span: span.clone(),
            })
        }

        Expr::If { cond, then_branch, else_branch, span } => Ok(Expr::If {
            cond: Box::new(expand_expr(cond, macro_env)?),
            then_branch: Box::new(expand_expr(then_branch, macro_env)?),
            else_branch: Box::new(expand_expr(else_branch, macro_env)?),
            span: span.clone(),
        }),

        Expr::Def { name, value, span } => Ok(Expr::Def {
            name: name.clone(),
            value: Box::new(expand_expr(value, macro_env)?),
            span: span.clone(),
        }),

        Expr::Defn { name, params, body, ret_type, span } => Ok(Expr::Defn {
            name: name.clone(),
            params: params.clone(),
            body: Box::new(expand_expr(body, macro_env)?),
            ret_type: ret_type.clone(),
            span: span.clone(),
        }),

        Expr::Do { exprs, span } => {
            let new_exprs: Result<Vec<_>, _> = exprs.iter().map(|e| expand_expr(e, macro_env)).collect();
            Ok(Expr::Do {
                exprs: new_exprs?,
                span: span.clone(),
            })
        }

        Expr::Loop { bindings, body, span } => {
            let new_bindings: Result<Vec<_>, MacroError> = bindings
                .iter()
                .map(|(name, val)| Ok((name.clone(), expand_expr(val, macro_env)?)))
                .collect();
            Ok(Expr::Loop {
                bindings: new_bindings?,
                body: Box::new(expand_expr(body, macro_env)?),
                span: span.clone(),
            })
        }

        Expr::Recur { args, span } => {
            let new_args: Result<Vec<_>, _> = args.iter().map(|a| expand_expr(a, macro_env)).collect();
            Ok(Expr::Recur {
                args: new_args?,
                span: span.clone(),
            })
        }

        Expr::Match { expr, arms, span } => {
            let new_expr = expand_expr(expr, macro_env)?;
            let mut new_arms = Vec::new();
            for (pat, body) in arms {
                new_arms.push((pat.clone(), expand_expr(body, macro_env)?));
            }
            Ok(Expr::Match {
                expr: Box::new(new_expr),
                arms: new_arms,
                span: span.clone(),
            })
        }

        Expr::SyntaxQuote(expr, _span) => {
            // Expand syntax-quote using the interpreter
            let mut empty_env = InterpEnv::new();
            let expanded = crate::r#macro::interpreter::expand_syntax_quote(expr, &mut empty_env)
                .map_err(|e| MacroError::EvalError(e.to_string()))?;
            expand_expr(&expanded, macro_env)
        }
        Expr::Unquote(expr, span) => Ok(Expr::Unquote(Box::new(expand_expr(expr, macro_env)?), span.clone())),
        Expr::Splicing(expr, span) => Ok(Expr::Splicing(Box::new(expand_expr(expr, macro_env)?), span.clone())),
        Expr::FieldAccess { expr, field, span } => Ok(Expr::FieldAccess {
            expr: Box::new(expand_expr(expr, macro_env)?),
            field: field.clone(),
            span: span.clone(),
        }),
        Expr::DefStruct { .. } => Ok(expr.clone()),

        // Atoms — nothing to expand
        other => Ok(other.clone()),
    }
}

/// Try to expand a macro call. Returns None if not a macro.
fn try_expand_macro(
    name: &str,
    args: &[Expr],
    span: &Span,
    macro_env: &HashMap<String, Expr>,
) -> Result<Option<Expr>, MacroError> {
    // Built-in macros first
    match name {
        "when" => return expand_when(args, span),
        "unless" => return expand_unless(args, span),
        "cond" => return expand_cond(args, span),
        "->" => return expand_thread_first(args, span),
        "->>" => return expand_thread_last(args, span),
        _ => {}
    }

    // User-defined macros
    if let Some(macro_defn) = macro_env.get(name) {
        if let Expr::Defn { params, body, .. } = macro_defn {
            let mut interp_env = InterpEnv::new();
            for (i, (param, _)) in params.iter().enumerate() {
                let arg_val = if i < args.len() {
                    MacroVal::Expr(args[i].clone())
                } else {
                    MacroVal::Nil
                };
                interp_env.insert(param.0.clone(), arg_val);
            }
            let result = eval(body, &mut interp_env)?;
            return Ok(Some(result.to_expr()));
        }
    }

    Ok(None)
}

/// (when cond body...)
/// => (if cond (do body...) nil)
fn expand_when(args: &[Expr], span: &Span) -> Result<Option<Expr>, MacroError> {
    if args.is_empty() {
        return Err(MacroError::WrongArity("when".to_string(), 1, 0));
    }
    let cond = args[0].clone();
    let body = if args.len() == 1 {
        Expr::Symbol(Symbol("nil".to_string()))
    } else {
        Expr::Do {
            exprs: args[1..].to_vec(),
            span: span.clone(),
        }
    };
    Ok(Some(Expr::If {
        cond: Box::new(cond),
        then_branch: Box::new(body),
        else_branch: Box::new(Expr::Symbol(Symbol("nil".to_string()))),
        span: span.clone(),
    }))
}

/// (unless cond body...)
/// => (if (not cond) (do body...) nil)
fn expand_unless(args: &[Expr], span: &Span) -> Result<Option<Expr>, MacroError> {
    if args.is_empty() {
        return Err(MacroError::WrongArity("unless".to_string(), 1, 0));
    }
    let cond = Expr::FnCall {
        func: Box::new(Expr::Symbol(Symbol("not".to_string()))),
        args: vec![args[0].clone()],
        span: span.clone(),
    };
    let body = if args.len() == 1 {
        Expr::Symbol(Symbol("nil".to_string()))
    } else {
        Expr::Do {
            exprs: args[1..].to_vec(),
            span: span.clone(),
        }
    };
    Ok(Some(Expr::If {
        cond: Box::new(cond),
        then_branch: Box::new(body),
        else_branch: Box::new(Expr::Symbol(Symbol("nil".to_string()))),
        span: span.clone(),
    }))
}

/// (-> x (f a) (g b))
/// => (g (f x a) b)
fn expand_thread_first(args: &[Expr], span: &Span) -> Result<Option<Expr>, MacroError> {
    if args.is_empty() {
        return Err(MacroError::WrongArity("->".to_string(), 1, 0));
    }
    let mut result = args[0].clone();
    for form in &args[1..] {
        result = match form {
            Expr::List(list, _) => {
                if list.is_empty() {
                    return Err(MacroError::InvalidSyntax("->".to_string()));
                }
                let func = list[0].clone();
                let mut new_args = vec![result];
                new_args.extend_from_slice(&list[1..]);
                Expr::FnCall {
                    func: Box::new(func),
                    args: new_args,
                    span: span.clone(),
                }
            }
            Expr::FnCall { func, args: fn_args, span: _, .. } => {
                let mut new_args = vec![result];
                new_args.extend_from_slice(fn_args);
                Expr::FnCall {
                    func: func.clone(),
                    args: new_args,
                    span: span.clone(),
                }
            }
            Expr::Symbol(sym) => Expr::FnCall {
                func: Box::new(Expr::Symbol(sym.clone())),
                args: vec![result],
                span: span.clone(),
            },
            other => {
                return Err(MacroError::InvalidSyntax(format!("-> {:?}", other)));
            }
        };
    }
    Ok(Some(result))
}

/// (->> x (f a) (g b))
/// => (g b (f a x))
fn expand_thread_last(args: &[Expr], span: &Span) -> Result<Option<Expr>, MacroError> {
    if args.is_empty() {
        return Err(MacroError::WrongArity("->>".to_string(), 1, 0));
    }
    let mut result = args[0].clone();
    for form in &args[1..] {
        result = match form {
            Expr::List(list, _) => {
                if list.is_empty() {
                    return Err(MacroError::InvalidSyntax("->>".to_string()));
                }
                let func = list[0].clone();
                let mut new_args = list[1..].to_vec();
                new_args.push(result);
                Expr::FnCall {
                    func: Box::new(func),
                    args: new_args,
                    span: span.clone(),
                }
            }
            Expr::FnCall { func, args: fn_args, span: _, .. } => {
                let mut new_args = fn_args.clone();
                new_args.push(result);
                Expr::FnCall {
                    func: func.clone(),
                    args: new_args,
                    span: span.clone(),
                }
            }
            Expr::Symbol(sym) => Expr::FnCall {
                func: Box::new(Expr::Symbol(sym.clone())),
                args: vec![result],
                span: span.clone(),
            },
            other => {
                return Err(MacroError::InvalidSyntax(format!("->> {:?}", other)));
            }
        };
    }
    Ok(Some(result))
}

/// (cond (p1 e1) (p2 e2) ...)
/// => (if p1 e1 (if p2 e2 ...))
fn expand_cond(args: &[Expr], span: &Span) -> Result<Option<Expr>, MacroError> {
    if args.is_empty() {
        return Ok(Some(Expr::Symbol(Symbol("nil".to_string()))));
    }
    // args should be pairs: [condition1, result1, condition2, result2, ...]
    let mut result = Expr::Symbol(Symbol("nil".to_string()));
    // Process in reverse to build nested ifs from inside out
    let mut i = args.len();
    while i >= 2 {
        i -= 2;
        let cond = match &args[i] {
            Expr::Keyword(_) => Expr::Bool(true),
            other => other.clone(),
        };
        let then_val = args[i + 1].clone();
        result = Expr::If {
            cond: Box::new(cond),
            then_branch: Box::new(then_val),
            else_branch: Box::new(result),
            span: span.clone(),
        };
    }
    Ok(Some(result))
}
