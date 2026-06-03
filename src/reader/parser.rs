use crate::ast::{Expr, Keyword, Pattern, Program, Span, Symbol, Type, Variant};
use crate::reader::lexer::{SpannedToken, Token};
use anyhow::{bail, Result};

pub struct Parser<'a> {
    tokens: &'a [SpannedToken],
    pos: usize,
}

impl<'a> Parser<'a> {
    pub fn new(tokens: &'a [SpannedToken]) -> Self {
        Self { tokens, pos: 0 }
    }

    fn peek(&self) -> Option<&Token> {
        self.tokens.get(self.pos).map(|t| &t.token)
    }

    fn advance(&mut self) -> Option<&SpannedToken> {
        let tok = self.tokens.get(self.pos);
        if tok.is_some() {
            self.pos += 1;
        }
        tok
    }

    fn current_span(&self) -> Span {
        self.tokens
            .get(self.pos)
            .map(|t| Span::new(t.line, t.col))
            .unwrap_or_else(|| Span::new(0, 0))
    }

    pub fn parse(mut self) -> Result<Program> {
        let mut exprs = Vec::new();
        while !matches!(self.peek(), Some(Token::Eof) | None) {
            // Skip comments at top level
            if matches!(self.peek(), Some(Token::Comment(_))) {
                self.advance();
                continue;
            }
            exprs.push(self.parse_expr()?);
        }
        Ok(Program { exprs })
    }

    fn parse_expr(&mut self) -> Result<Expr> {
        let spanned = self.tokens.get(self.pos).ok_or_else(|| anyhow::anyhow!("Unexpected EOF"))?;
        let span = Span::new(spanned.line, spanned.col);

        match &spanned.token {
            Token::Comment(_) => {
                self.advance();
                self.parse_expr()
            }
            Token::LParen => self.parse_list(),
            Token::LBracket => self.parse_vector(),
            Token::Quote => {
                self.advance();
                let expr = self.parse_expr()?;
                Ok(Expr::Quote(Box::new(expr), span))
            }
            Token::SyntaxQuote => {
                self.advance();
                let expr = self.parse_expr()?;
                Ok(Expr::SyntaxQuote(Box::new(expr), span))
            }
            Token::Unquote => {
                self.advance();
                let expr = self.parse_expr()?;
                Ok(Expr::Unquote(Box::new(expr), span))
            }
            Token::Splicing => {
                self.advance();
                let expr = self.parse_expr()?;
                Ok(Expr::Splicing(Box::new(expr), span))
            }
            Token::Meta => {
                // ^expr — borrow (or metadata, initially just borrow)
                self.advance();
                let is_mut = if let Some(Token::Symbol(s)) = self.peek() {
                    if s == "mut" {
                        self.advance();
                        true
                    } else {
                        false
                    }
                } else {
                    false
                };
                let expr = self.parse_expr()?;
                Ok(Expr::Borrow(Box::new(expr), is_mut, span))
            }
            Token::Number(n) => {
                self.advance();
                Ok(Expr::Number(*n))
            }
            Token::Float(n) => {
                self.advance();
                Ok(Expr::Float(*n))
            }
            Token::String(s) => {
                let s = s.clone();
                self.advance();
                Ok(Expr::String(s))
            }
            Token::Symbol(s) => {
                let s = s.clone();
                self.advance();
                Ok(Expr::Symbol(Symbol(s)))
            }
            Token::Keyword(s) => {
                let s = s.clone();
                self.advance();
                Ok(Expr::Keyword(Keyword(s)))
            }
            Token::Bool(b) => {
                let b = *b;
                self.advance();
                Ok(Expr::Bool(b))
            }
            Token::Nil => {
                self.advance();
                Ok(Expr::Symbol(Symbol("nil".to_string())))
            }
            other => bail!("Unexpected token: {} at line {}, col {}", other, span.line, span.col),
        }
    }

    fn parse_list(&mut self) -> Result<Expr> {
        let start_span = self.current_span();
        self.advance(); // consume '('

        // Check for special forms
        if let Some(Token::Symbol(name)) = self.peek() {
            let name = name.clone();
            match name.as_str() {
                "let" => return self.parse_let(start_span),
                "if" => return self.parse_if(start_span),
                "def" => return self.parse_def(start_span),
                "defn" => return self.parse_defn(start_span),
                "defmacro" => return self.parse_defmacro(start_span),
                "do" => return self.parse_do(start_span),
                "loop" => return self.parse_loop(start_span),
                "recur" => return self.parse_recur(start_span),
                "quote" => return self.parse_quote(start_span),
                "match" => return self.parse_match(start_span),
                "defstruct" => return self.parse_defstruct(start_span),
                "deftype" => return self.parse_deftype(start_span),
                "fn" => return self.parse_lambda(start_span),
                _ => {}
            }
        }

        // Check for field access: (.field expr)
        if let Some(Token::Symbol(name)) = self.peek() {
            if name.starts_with('.') && name.len() > 1 {
                return self.parse_field_access(start_span);
            }
        }

        // Regular list / function call
        let mut items = Vec::new();
        while !matches!(self.peek(), Some(Token::RParen) | Some(Token::Eof) | None) {
            items.push(self.parse_expr()?);
        }
        self.expect(Token::RParen)?;

        if items.is_empty() {
            Ok(Expr::List(items, start_span))
        } else {
            // Function call: (func arg1 arg2 ...)
            let func = items.remove(0);
            Ok(Expr::FnCall {
                func: Box::new(func),
                args: items,
                span: start_span,
            })
        }
    }

    fn parse_let(&mut self, start_span: Span) -> Result<Expr> {
        self.advance(); // consume 'let'
        self.expect(Token::LBracket)?;
        let mut bindings = Vec::new();
        loop {
            self.skip_comments();
            if matches!(self.peek(), Some(Token::RBracket)) {
                break;
            }
            let name = match self.peek() {
                Some(Token::Symbol(s)) => {
                    let s = s.clone();
                    self.advance();
                    Symbol(s)
                }
                _ => bail!("Expected binding name in let at line {}, col {}", start_span.line, start_span.col),
            };
            let val = self.parse_expr()?;
            bindings.push((name, val));
        }
        self.expect(Token::RBracket)?;
        let body_exprs = self.parse_body_exprs()?;
        self.expect(Token::RParen)?;
        let body = if body_exprs.len() == 1 {
            Box::new(body_exprs.into_iter().next().unwrap())
        } else {
            Box::new(Expr::Do { exprs: body_exprs, span: start_span.clone() })
        };
        Ok(Expr::Let { bindings, body, span: start_span })
    }

    fn parse_if(&mut self, start_span: Span) -> Result<Expr> {
        self.advance(); // consume 'if'
        let cond = self.parse_expr()?;
        let then_branch = self.parse_expr()?;
        let else_branch = if matches!(self.peek(), Some(Token::RParen)) {
            Expr::Symbol(Symbol("nil".to_string()))
        } else {
            self.parse_expr()?
        };
        self.expect(Token::RParen)?;
        Ok(Expr::If {
            cond: Box::new(cond),
            then_branch: Box::new(then_branch),
            else_branch: Box::new(else_branch),
            span: start_span,
        })
    }

    fn parse_def(&mut self, start_span: Span) -> Result<Expr> {
        self.advance(); // consume 'def'
        let name = match self.peek() {
            Some(Token::Symbol(s)) => {
                let s = s.clone();
                self.advance();
                Symbol(s)
            }
            _ => bail!("Expected name in def at line {}, col {}", start_span.line, start_span.col),
        };
        let value = self.parse_expr()?;
        self.expect(Token::RParen)?;
        Ok(Expr::Def { name, value: Box::new(value), span: start_span })
    }

    fn parse_defn(&mut self, start_span: Span) -> Result<Expr> {
        self.advance(); // consume 'defn'
        let name = match self.peek() {
            Some(Token::Symbol(s)) => {
                let s = s.clone();
                self.advance();
                Symbol(s)
            }
            _ => bail!("Expected function name in defn at line {}, col {}", start_span.line, start_span.col),
        };
        self.expect(Token::LBracket)?;
        let mut params = Vec::new();
        loop {
            if matches!(self.peek(), Some(Token::RBracket)) {
                break;
            }
            let (param_name, param_type) = self.parse_fn_param(start_span.clone())?;
            params.push((param_name, param_type));
        }
        self.expect(Token::RBracket)?;

        // Optional return type: -> Type
        let ret_type = if matches!(self.peek(), Some(Token::Symbol(s)) if s == "->") {
            self.advance(); // consume '->'
            match self.peek() {
                Some(Token::Symbol(s)) => {
                    let s = s.clone();
                    self.advance();
                    parse_type(&s)
                }
                _ => None,
            }
        } else {
            None
        };

        let body_exprs = self.parse_body_exprs()?;
        self.expect(Token::RParen)?;
        let body = if body_exprs.len() == 1 {
            Box::new(body_exprs.into_iter().next().unwrap())
        } else {
            Box::new(Expr::Do { exprs: body_exprs, span: start_span.clone() })
        };
        Ok(Expr::Defn { name, params, body, ret_type, span: start_span })
    }

    fn parse_defmacro(&mut self, start_span: Span) -> Result<Expr> {
        self.advance(); // consume 'defmacro'
        let name = match self.peek() {
            Some(Token::Symbol(s)) => {
                let s = s.clone();
                self.advance();
                Symbol(s)
            }
            _ => bail!("Expected macro name after defmacro at line {}, col {}", start_span.line, start_span.col),
        };

        self.expect(Token::LBracket)?;
        let mut params = Vec::new();
        loop {
            self.skip_comments();
            if matches!(self.peek(), Some(Token::RBracket)) {
                break;
            }
            let param_name = match self.peek() {
                Some(Token::Symbol(s)) => {
                    let s = s.clone();
                    self.advance();
                    Symbol(s)
                }
                _ => bail!("Expected parameter in defmacro at line {}, col {}", start_span.line, start_span.col),
            };
            params.push((param_name, None));
        }
        self.expect(Token::RBracket)?;

        let body_exprs = self.parse_body_exprs()?;
        self.expect(Token::RParen)?;
        let body = if body_exprs.len() == 1 {
            Box::new(body_exprs.into_iter().next().unwrap())
        } else {
            Box::new(Expr::Do { exprs: body_exprs, span: start_span.clone() })
        };
        Ok(Expr::DefMacro { name, params, body, span: start_span })
    }

    fn parse_do(&mut self, start_span: Span) -> Result<Expr> {
        self.advance(); // consume 'do'
        let exprs = self.parse_body_exprs()?;
        self.expect(Token::RParen)?;
        Ok(Expr::Do { exprs, span: start_span })
    }

    fn parse_lambda(&mut self, start_span: Span) -> Result<Expr> {
        self.advance(); // consume 'fn'
        self.expect(Token::LBracket)?;
        let mut params = Vec::new();
        loop {
            self.skip_comments();
            if matches!(self.peek(), Some(Token::RBracket)) {
                break;
            }
            let (param_name, param_type) = self.parse_fn_param(start_span.clone())?;
            params.push((param_name, param_type));
        }
        self.expect(Token::RBracket)?;
        let body_exprs = self.parse_body_exprs()?;
        self.expect(Token::RParen)?;
        let body = if body_exprs.len() == 1 {
            Box::new(body_exprs.into_iter().next().unwrap())
        } else {
            Box::new(Expr::Do { exprs: body_exprs, span: start_span.clone() })
        };
        Ok(Expr::Lambda { params, body, span: start_span })
    }

    fn parse_loop(&mut self, start_span: Span) -> Result<Expr> {
        self.advance(); // consume 'loop'
        self.expect(Token::LBracket)?;
        let mut bindings = Vec::new();
        loop {
            self.skip_comments();
            if matches!(self.peek(), Some(Token::RBracket)) {
                break;
            }
            let name = match self.peek() {
                Some(Token::Symbol(s)) => {
                    let s = s.clone();
                    self.advance();
                    Symbol(s)
                }
                _ => bail!("Expected binding name in loop at line {}, col {}", start_span.line, start_span.col),
            };
            let val = self.parse_expr()?;
            bindings.push((name, val));
        }
        self.expect(Token::RBracket)?;
        let body_exprs = self.parse_body_exprs()?;
        self.expect(Token::RParen)?;
        let body = if body_exprs.len() == 1 {
            Box::new(body_exprs.into_iter().next().unwrap())
        } else {
            Box::new(Expr::Do { exprs: body_exprs, span: start_span.clone() })
        };
        Ok(Expr::Loop { bindings, body, span: start_span })
    }

    fn parse_recur(&mut self, start_span: Span) -> Result<Expr> {
        self.advance(); // consume 'recur'
        let mut args = Vec::new();
        while !matches!(self.peek(), Some(Token::RParen) | Some(Token::Eof) | None) {
            self.skip_comments();
            if matches!(self.peek(), Some(Token::RParen) | Some(Token::Eof) | None) {
                break;
            }
            args.push(self.parse_expr()?);
        }
        self.expect(Token::RParen)?;
        Ok(Expr::Recur { args, span: start_span })
    }

    fn parse_body_exprs(&mut self) -> Result<Vec<Expr>> {
        let mut exprs = Vec::new();
        while !matches!(self.peek(), Some(Token::RParen) | Some(Token::Eof) | None) {
            self.skip_comments();
            if matches!(self.peek(), Some(Token::RParen) | Some(Token::Eof) | None) {
                break;
            }
            exprs.push(self.parse_expr()?);
        }
        Ok(exprs)
    }

    fn skip_comments(&mut self) {
        while matches!(self.peek(), Some(Token::Comment(_))) {
            self.advance();
        }
    }

    /// Parse a function parameter: name or ^type name or ^mut type name
    fn parse_fn_param(&mut self, start_span: Span) -> Result<(Symbol, Option<Type>)> {
        match self.peek() {
            Some(Token::Symbol(s)) => {
                let s = s.clone();
                self.advance();
                Ok((Symbol(s), None))
            }
            Some(Token::Meta) => {
                self.advance();
                let is_mut = if let Some(Token::Symbol(s)) = self.peek() {
                    if s == "mut" { self.advance(); true } else { false }
                } else { false };
                let type_hint = match self.peek() {
                    Some(Token::Symbol(s)) => {
                        let s = s.clone();
                        self.advance();
                        parse_type(&s)
                    }
                    _ => None,
                };
                let name = match self.peek() {
                    Some(Token::Symbol(s)) => {
                        let s = s.clone();
                        self.advance();
                        Symbol(s)
                    }
                    _ => bail!("Expected parameter name after type at line {}", start_span.line),
                };
                let ty = match type_hint {
                    Some(t) if is_mut => Some(Type::MutRef(Box::new(t))),
                    Some(t) => Some(Type::Ref(Box::new(t))),
                    None => None,
                };
                Ok((name, ty))
            }
            _ => bail!("Expected parameter at line {}", start_span.line),
        }
    }

    fn parse_quote(&mut self, start_span: Span) -> Result<Expr> {
        self.advance(); // consume 'quote'
        let expr = self.parse_expr()?;
        self.expect(Token::RParen)?;
        Ok(Expr::Quote(Box::new(expr), start_span))
    }

    fn parse_match(&mut self, start_span: Span) -> Result<Expr> {
        self.advance(); // consume 'match'
        let expr = self.parse_expr()?;
        let mut arms = Vec::new();
        while !matches!(self.peek(), Some(Token::RParen) | Some(Token::Eof) | None) {
            let pattern = self.parse_pattern()?;
            let body = self.parse_expr()?;
            arms.push((pattern, body));
        }
        self.expect(Token::RParen)?;
        Ok(Expr::Match {
            expr: Box::new(expr),
            arms,
            span: start_span,
        })
    }

    fn parse_pattern(&mut self) -> Result<Pattern> {
        let spanned = self.tokens.get(self.pos).ok_or_else(|| anyhow::anyhow!("Unexpected EOF in pattern"))?;
        let span = Span::new(spanned.line, spanned.col);
        match &spanned.token {
            Token::Symbol(s) if s == "_" => {
                self.advance();
                Ok(Pattern::Wildcard)
            }
            Token::Symbol(s) if s.chars().next().map_or(false, |c| c.is_uppercase()) => {
                // Uppercase symbols in patterns are constructors (variant/struct)
                let name = s.clone();
                self.advance();
                Ok(Pattern::Struct { name: Symbol(name), fields: vec![] })
            }
            Token::Symbol(s) => {
                let s = s.clone();
                self.advance();
                Ok(Pattern::Binding(Symbol(s)))
            }
            Token::Number(n) => {
                let n = *n;
                self.advance();
                Ok(Pattern::Literal(Expr::Number(n)))
            }
            Token::Float(f) => {
                let f = *f;
                self.advance();
                Ok(Pattern::Literal(Expr::Float(f)))
            }
            Token::Bool(b) => {
                let b = *b;
                self.advance();
                Ok(Pattern::Literal(Expr::Bool(b)))
            }
            Token::String(s) => {
                let s = s.clone();
                self.advance();
                Ok(Pattern::Literal(Expr::String(s)))
            }
            Token::Keyword(k) => {
                let k = k.clone();
                self.advance();
                Ok(Pattern::Literal(Expr::Keyword(Keyword(k))))
            }
            Token::LBracket => {
                self.advance(); // consume '['
                let mut items = Vec::new();
                while !matches!(self.peek(), Some(Token::RBracket) | Some(Token::Eof) | None) {
                    items.push(self.parse_pattern()?);
                }
                self.expect(Token::RBracket)?;
                Ok(Pattern::Vector(items, span))
            }
            Token::LParen => {
                self.advance(); // consume '('
                // Check if this is a struct/variant pattern: (StructName field1 field2 ...)
                if let Some(Token::Symbol(s)) = self.peek() {
                    let struct_name = s.clone();
                    let is_uppercase = struct_name.chars().next().map_or(false, |c| c.is_uppercase());
                    self.advance();
                    let mut fields = Vec::new();
                    while !matches!(self.peek(), Some(Token::RParen) | Some(Token::Eof) | None) {
                        let field_pattern = self.parse_pattern()?;
                        fields.push(field_pattern);
                    }
                    self.expect(Token::RParen)?;
                    // Uppercase name always means struct/variant pattern, even with no fields
                    if !fields.is_empty() || is_uppercase {
                        return Ok(Pattern::Struct { name: Symbol(struct_name), fields });
                    }
                    // Lowercase symbol with no sub-patterns — treat as binding in a list
                    return Ok(Pattern::List(vec![Pattern::Binding(Symbol(struct_name))], span));
                }
                let mut items = Vec::new();
                while !matches!(self.peek(), Some(Token::RParen) | Some(Token::Eof) | None) {
                    items.push(self.parse_pattern()?);
                }
                self.expect(Token::RParen)?;
                Ok(Pattern::List(items, span))
            }
            other => bail!("Unexpected token in pattern: {} at line {}, col {}", other, span.line, span.col),
        }
    }

    fn parse_defstruct(&mut self, start_span: Span) -> Result<Expr> {
        self.advance(); // consume 'defstruct'
        let name = match self.peek() {
            Some(Token::Symbol(s)) => {
                let s = s.clone();
                self.advance();
                Symbol(s)
            }
            _ => bail!("Expected struct name after defstruct at line {}, col {}", start_span.line, start_span.col),
        };
        self.expect(Token::LBracket)?;
        let mut fields = Vec::new();
        while !matches!(self.peek(), Some(Token::RBracket) | Some(Token::Eof) | None) {
            let field_name = match self.peek() {
                Some(Token::Symbol(s)) => {
                    let s = s.clone();
                    self.advance();
                    Symbol(s)
                }
                _ => bail!("Expected field name in defstruct at line {}, col {}", start_span.line, start_span.col),
            };
            fields.push(field_name);
        }
        self.expect(Token::RBracket)?;
        self.expect(Token::RParen)?;
        Ok(Expr::DefStruct { name, fields, span: start_span })
    }

    fn parse_deftype(&mut self, start_span: Span) -> Result<Expr> {
        self.advance(); // consume 'deftype'
        let name = match self.peek() {
            Some(Token::Symbol(s)) => {
                let s = s.clone();
                self.advance();
                Symbol(s)
            }
            _ => bail!("Expected type name after deftype at line {}, col {}", start_span.line, start_span.col),
        };
        let mut variants = Vec::new();
        while !matches!(self.peek(), Some(Token::RParen) | Some(Token::Eof) | None) {
            self.skip_comments();
            if matches!(self.peek(), Some(Token::RParen) | Some(Token::Eof) | None) {
                break;
            }
            // Each variant is [VariantName Type1 Type2 ...]
            self.expect(Token::LBracket)?;
            let variant_name = match self.peek() {
                Some(Token::Symbol(s)) => {
                    let s = s.clone();
                    self.advance();
                    Symbol(s)
                }
                _ => bail!("Expected variant name in deftype at line {}, col {}", start_span.line, start_span.col),
            };
            let mut fields = Vec::new();
            while !matches!(self.peek(), Some(Token::RBracket) | Some(Token::Eof) | None) {
                self.skip_comments();
                if matches!(self.peek(), Some(Token::RBracket) | Some(Token::Eof) | None) {
                    break;
                }
                let field_name = match self.peek() {
                    Some(Token::Symbol(s)) => {
                        let s = s.clone();
                        self.advance();
                        Symbol(s)
                    }
                    _ => bail!("Expected field name in variant at line {}, col {}", start_span.line, start_span.col),
                };
                // Optional type annotation
                let field_type = if matches!(self.peek(), Some(Token::Symbol(s)) if is_type_name(s)) {
                    if let Some(Token::Symbol(s)) = self.peek() {
                        let ty = parse_type(s);
                        self.advance();
                        ty
                    } else {
                        None
                    }
                } else {
                    None
                };
                fields.push((field_name, field_type));
            }
            self.expect(Token::RBracket)?;
            variants.push(Variant { name: variant_name, fields });
        }
        self.expect(Token::RParen)?;
        Ok(Expr::DefType { name, variants, span: start_span })
    }

    fn parse_field_access(&mut self, start_span: Span) -> Result<Expr> {
        let field = match self.peek() {
            Some(Token::Symbol(s)) => {
                let name = s.clone();
                self.advance();
                // Remove leading dot
                Symbol(name.trim_start_matches('.').to_string())
            }
            _ => bail!("Expected field name in field access at line {}, col {}", start_span.line, start_span.col),
        };
        let expr = self.parse_expr()?;
        self.expect(Token::RParen)?;
        Ok(Expr::FieldAccess { expr: Box::new(expr), field, span: start_span })
    }

    fn parse_vector(&mut self) -> Result<Expr> {
        let start_span = self.current_span();
        self.advance(); // consume '['
        let mut items = Vec::new();
        while !matches!(self.peek(), Some(Token::RBracket) | Some(Token::Eof) | None) {
            items.push(self.parse_expr()?);
        }
        self.expect(Token::RBracket)?;
        Ok(Expr::Vector(items, start_span))
    }

    fn expect(&mut self, expected: Token) -> Result<()> {
        let tok = self.advance().ok_or_else(|| anyhow::anyhow!("Unexpected EOF"))?;
        let matches = match (&tok.token, &expected) {
            (Token::RParen, Token::RParen) => true,
            (Token::LParen, Token::LParen) => true,
            (Token::RBracket, Token::RBracket) => true,
            (Token::LBracket, Token::LBracket) => true,

            _ => false,
        };
        if !matches {
            bail!("Expected {:?}, got {:?} at line {}, col {}", expected, tok.token, tok.line, tok.col);
        }
        Ok(())
    }
}

fn is_type_name(s: &str) -> bool {
    matches!(s, "i64" | "f64" | "bool" | "void")
}

fn parse_type(s: &str) -> Option<Type> {
    match s {
        "i64" => Some(Type::I64),
        "f64" => Some(Type::F64),
        "bool" => Some(Type::Bool),
        _ => Some(Type::Named(s.to_string())),
    }
}

pub fn parse(tokens: &[SpannedToken]) -> Result<Program> {
    Parser::new(tokens).parse()
}
