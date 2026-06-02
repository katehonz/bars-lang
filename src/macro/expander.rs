use crate::ast::{Expr, Program, Span, Symbol};
use thiserror::Error;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum MacroError {
    #[error("Macro '{0}' expects at least {1} arguments, got {2}")]
    WrongArity(String, usize, usize),
    #[error("Unknown macro: {0}")]
    UnknownMacro(String),
    #[error("Invalid syntax for macro '{0}'")]
    InvalidSyntax(String),
}

/// Expand all macros in a program
pub fn expand_program(program: &Program) -> Result<Program, MacroError> {
    let mut new_exprs = Vec::new();
    for expr in &program.exprs {
        new_exprs.push(expand_expr(expr)?);
    }
    Ok(Program { exprs: new_exprs })
}

/// Expand macros in a single expression
fn expand_expr(expr: &Expr) -> Result<Expr, MacroError> {
    match expr {
        // Don't expand inside quote
        Expr::Quote(inner, span) => Ok(Expr::Quote(inner.clone(), span.clone())),

        // Expand function calls
        Expr::FnCall { func, args, span } => {
            let expanded_func = expand_expr(func)?;
            let expanded_args: Result<Vec<_>, _> = args.iter().map(expand_expr).collect();
            let expanded_args = expanded_args?;

            // Check if func is a macro name
            if let Expr::Symbol(sym) = &expanded_func {
                if let Some(expanded) = try_expand_macro(&sym.0, &expanded_args, span)? {
                    return Ok(expanded);
                }
            }

            Ok(Expr::FnCall {
                func: Box::new(expanded_func),
                args: expanded_args,
                span: span.clone(),
            })
        }

        // Recursively expand other expressions
        Expr::Let { bindings, body, span } => {
            let new_bindings: Result<Vec<_>, _> = bindings
                .iter()
                .map(|(name, val)| Ok((name.clone(), expand_expr(val)?)))
                .collect();
            Ok(Expr::Let {
                bindings: new_bindings?,
                body: Box::new(expand_expr(body)?),
                span: span.clone(),
            })
        }

        Expr::If { cond, then_branch, else_branch, span } => Ok(Expr::If {
            cond: Box::new(expand_expr(cond)?),
            then_branch: Box::new(expand_expr(then_branch)?),
            else_branch: Box::new(expand_expr(else_branch)?),
            span: span.clone(),
        }),

        Expr::Do { exprs, span } => {
            let new_exprs: Result<Vec<_>, _> = exprs.iter().map(expand_expr).collect();
            Ok(Expr::Do {
                exprs: new_exprs?,
                span: span.clone(),
            })
        }

        Expr::Def { name, value, span } => Ok(Expr::Def {
            name: name.clone(),
            value: Box::new(expand_expr(value)?),
            span: span.clone(),
        }),

        Expr::Defn { name, params, body, ret_type, span } => Ok(Expr::Defn {
            name: name.clone(),
            params: params.clone(),
            body: Box::new(expand_expr(body)?),
            ret_type: ret_type.clone(),
            span: span.clone(),
        }),

        Expr::Loop { bindings, body, span } => {
            let new_bindings: Result<Vec<_>, _> = bindings
                .iter()
                .map(|(name, val)| Ok((name.clone(), expand_expr(val)?)))
                .collect();
            Ok(Expr::Loop {
                bindings: new_bindings?,
                body: Box::new(expand_expr(body)?),
                span: span.clone(),
            })
        }

        Expr::Recur { args, span } => {
            let new_args: Result<Vec<_>, _> = args.iter().map(expand_expr).collect();
            Ok(Expr::Recur {
                args: new_args?,
                span: span.clone(),
            })
        }

        // Atoms — nothing to expand
        other => Ok(other.clone()),
    }
}

/// Try to expand a macro call. Returns None if not a macro.
fn try_expand_macro(
    name: &str,
    args: &[Expr],
    span: &Span,
) -> Result<Option<Expr>, MacroError> {
    match name {
        "when" => expand_when(args, span),
        "unless" => expand_unless(args, span),
        "cond" => expand_cond(args, span),
        "->" => expand_thread_first(args, span),
        "->>" => expand_thread_last(args, span),
        _ => Ok(None),
    }
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
                return Err(MacroError::InvalidSyntax(format!(
                    "-> expects function call, got {:?}", other
                )));
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
    // Or with explicit else: [... :else default]
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
                return Err(MacroError::InvalidSyntax(format!(
                    "->> expects function call, got {:?}", other
                )));
            }
        };
    }
    Ok(Some(result))
}
