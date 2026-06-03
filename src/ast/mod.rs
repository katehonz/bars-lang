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

/// A variant in an algebraic data type definition
#[derive(Debug, Clone, PartialEq)]
pub struct Variant {
    pub name: Symbol,
    pub fields: Vec<(Symbol, Option<Type>)>,
}

/// Patterns for pattern matching
#[derive(Debug, Clone, PartialEq)]
pub enum Pattern {
    Wildcard,                          // _
    Binding(Symbol),                   // x
    Literal(Expr),                     // 42, true, "hello", :ok
    Vector(Vec<Pattern>, Span),        // [p1 p2]
    List(Vec<Pattern>, Span),          // (p1 p2)
    Struct { name: Symbol, fields: Vec<Pattern> }, // (Point x y)
}

/// Expressions in Bars AST
#[derive(Debug, Clone, PartialEq)]
pub enum Expr {
    Number(i64, Span),
    Float(f64, Span),
    Bool(bool, Span),
    String(String, Span),
    Symbol(Symbol, Span),
    Keyword(Keyword, Span),
    List(Vec<Expr>, Span),
    Vector(Vec<Expr>, Span),

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
    Lambda {
        params: Vec<(Symbol, Option<Type>)>,
        body: Box<Expr>,
        span: Span,
    },
    Match {
        expr: Box<Expr>,
        arms: Vec<(Pattern, Expr)>,
        span: Span,
    },
    DefStruct {
        name: Symbol,
        fields: Vec<Symbol>,
        span: Span,
    },
    DefType {
        name: Symbol,
        variants: Vec<Variant>,
        span: Span,
    },
    Extern {
        c_name: String,
        bars_name: Symbol,
        params: Vec<(Symbol, Option<Type>)>,
        ret_type: Option<Type>,
        span: Span,
    },
    FieldAccess {
        expr: Box<Expr>,
        field: Symbol,
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
            Expr::Number(_, s) | Expr::Float(_, s) | Expr::Bool(_, s) | Expr::String(_, s) |
            Expr::Symbol(_, s) | Expr::Keyword(_, s) => s.clone(),
            Expr::List(_, s) | Expr::Vector(_, s) => s.clone(),
            Expr::Let { span, .. } => span.clone(),
            Expr::If { span, .. } => span.clone(),
            Expr::Def { span, .. } => span.clone(),
            Expr::Defn { span, .. } => span.clone(),
            Expr::FnCall { span, .. } => span.clone(),
            Expr::Do { span, .. } => span.clone(),
            Expr::Loop { span, .. } => span.clone(),
            Expr::Recur { span, .. } => span.clone(),
            Expr::DefMacro { span, .. } => span.clone(),
            Expr::Lambda { span, .. } => span.clone(),
            Expr::Match { span, .. } => span.clone(),
            Expr::DefStruct { span, .. } => span.clone(),
            Expr::DefType { span, .. } => span.clone(),
            Expr::Extern { span, .. } => span.clone(),
            Expr::FieldAccess { span, .. } => span.clone(),
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
