use std::fmt;

/// Source location for error reporting
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Span {
    pub line: usize,
    pub col: usize,
}

impl Span {
    pub fn new(line: usize, col: usize) -> Self {
        Self { line, col }
    }
}

/// Types in Bars
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Type {
    I64,
    F64,
    Bool,
    Void,
    // Ownership annotations
    Ref(Box<Type>),
    MutRef(Box<Type>),
    // User-defined / inferred
    Unknown,
    Named(String),
}

impl fmt::Display for Type {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Type::I64 => write!(f, "i64"),
            Type::F64 => write!(f, "f64"),
            Type::Bool => write!(f, "bool"),
            Type::Void => write!(f, "void"),
            Type::Ref(t) => write!(f, "^{}", t),
            Type::MutRef(t) => write!(f, "^mut {}", t),
            Type::Unknown => write!(f, "?"),
            Type::Named(n) => write!(f, "{}", n),
        }
    }
}

/// A symbol/name in the language
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Symbol(pub String);

impl fmt::Display for Symbol {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// A keyword like :foo
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Keyword(pub String);

impl fmt::Display for Keyword {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, ":{}", self.0)
    }
}

/// Patterns for pattern matching
#[derive(Debug, Clone, PartialEq)]
pub enum Pattern {
    Wildcard,                          // _
    Binding(Symbol),                   // x
    Literal(Expr),                     // 42, true, "hello", :ok
    Vector(Vec<Pattern>, Span),        // [p1 p2]
    List(Vec<Pattern>, Span),          // (p1 p2)
}

/// Expressions in Bars AST
#[derive(Debug, Clone, PartialEq)]
pub enum Expr {
    Number(i64),
    Float(f64),
    Bool(bool),
    String(String),
    Symbol(Symbol),
    Keyword(Keyword),
    List(Vec<Expr>, Span),
    Vector(Vec<Expr>, Span),
    Map(Vec<(Expr, Expr)>, Span),
    // Special forms
    Let {
        bindings: Vec<(Symbol, Expr)>,
        body: Box<Expr>,
        span: Span,
    },
    If {
        cond: Box<Expr>,
        then_branch: Box<Expr>,
        else_branch: Box<Expr>,
        span: Span,
    },
    Def {
        name: Symbol,
        value: Box<Expr>,
        span: Span,
    },
    Defn {
        name: Symbol,
        params: Vec<(Symbol, Option<Type>)>,
        body: Box<Expr>,
        ret_type: Option<Type>,
        span: Span,
    },
    FnCall {
        func: Box<Expr>,
        args: Vec<Expr>,
        span: Span,
    },
    Do {
        exprs: Vec<Expr>,
        span: Span,
    },
    Loop {
        bindings: Vec<(Symbol, Expr)>,
        body: Box<Expr>,
        span: Span,
    },
    Recur {
        args: Vec<Expr>,
        span: Span,
    },
    DefMacro {
        name: Symbol,
        params: Vec<(Symbol, Option<Type>)>,
        body: Box<Expr>,
        span: Span,
    },
    Match {
        expr: Box<Expr>,
        arms: Vec<(Pattern, Expr)>,
        span: Span,
    },
    Quote(Box<Expr>, Span),
    SyntaxQuote(Box<Expr>, Span),
    Unquote(Box<Expr>, Span),
    Splicing(Box<Expr>, Span),
    Borrow(Box<Expr>, bool, Span), // expr, is_mut
}

impl Expr {
    pub fn span(&self) -> Span {
        match self {
            Expr::Number(_) | Expr::Float(_) | Expr::Bool(_) | Expr::String(_) |
            Expr::Symbol(_) | Expr::Keyword(_) => Span::new(0, 0),
            Expr::List(_, s) | Expr::Vector(_, s) | Expr::Map(_, s) => s.clone(),
            Expr::Let { span, .. } => span.clone(),
            Expr::If { span, .. } => span.clone(),
            Expr::Def { span, .. } => span.clone(),
            Expr::Defn { span, .. } => span.clone(),
            Expr::FnCall { span, .. } => span.clone(),
            Expr::Do { span, .. } => span.clone(),
            Expr::Loop { span, .. } => span.clone(),
            Expr::Recur { span, .. } => span.clone(),
            Expr::DefMacro { span, .. } => span.clone(),
            Expr::Match { span, .. } => span.clone(),
            Expr::Quote(_, s) => s.clone(),
            Expr::SyntaxQuote(_, s) => s.clone(),
            Expr::Unquote(_, s) => s.clone(),
            Expr::Splicing(_, s) => s.clone(),
            Expr::Borrow(_, _, s) => s.clone(),
        }
    }
}

/// Top-level program
#[derive(Debug, Clone, PartialEq)]
pub struct Program {
    pub exprs: Vec<Expr>,
}
