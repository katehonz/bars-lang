use anyhow::Result;
use std::fmt;

#[derive(Debug, Clone, PartialEq)]
pub enum Token {
    LParen,         // (
    RParen,         // )
    LBracket,       // [
    RBracket,       // ]
    LBrace,         // {
    RBrace,         // }
    Number(i64),
    Float(f64),
    String(String),
    Symbol(String),
    Keyword(String),
    Bool(bool),
    Nil,
    Quote,          // '
    SyntaxQuote,    // `
    Unquote,        // ~
    Splicing,       // ~@
    Meta,           // ^
    Deref,          // @
    Comment(String),
    Eof,
}

impl fmt::Display for Token {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Token::LParen => write!(f, "("),
            Token::RParen => write!(f, ")"),
            Token::LBracket => write!(f, "["),
            Token::RBracket => write!(f, "]"),
            Token::LBrace => write!(f, "{{"),
            Token::RBrace => write!(f, "}}"),
            Token::Number(n) => write!(f, "{}", n),
            Token::Float(n) => write!(f, "{}", n),
            Token::String(s) => write!(f, "\"{}\"", s),
            Token::Symbol(s) => write!(f, "{}", s),
            Token::Keyword(s) => write!(f, ":{}", s),
            Token::Bool(true) => write!(f, "true"),
            Token::Bool(false) => write!(f, "false"),
            Token::Nil => write!(f, "nil"),
            Token::Quote => write!(f, "'"),
            Token::SyntaxQuote => write!(f, "`"),
            Token::Unquote => write!(f, "~"),
            Token::Splicing => write!(f, "~@"),
            Token::Meta => write!(f, "^"),
            Token::Deref => write!(f, "@"),
            Token::Comment(s) => write!(f, ";{}", s),
            Token::Eof => write!(f, "<EOF>"),
        }
    }
}

#[derive(Debug, Clone)]
pub struct SpannedToken {
    pub token: Token,
    pub line: usize,
    pub col: usize,
}

pub fn tokenize(input: &str) -> Result<Vec<SpannedToken>> {
    let mut tokens = Vec::new();
    let mut chars = input.chars().peekable();
    let mut line: usize = 1;
    let mut col: usize = 1;

    while let Some(&ch) = chars.peek() {
        let start_line = line;
        let start_col = col;

        match ch {
            '(' => {
                chars.next();
                col += 1;
                tokens.push(SpannedToken { token: Token::LParen, line: start_line, col: start_col });
            }
            ')' => {
                chars.next();
                col += 1;
                tokens.push(SpannedToken { token: Token::RParen, line: start_line, col: start_col });
            }
            '[' => {
                chars.next();
                col += 1;
                tokens.push(SpannedToken { token: Token::LBracket, line: start_line, col: start_col });
            }
            ']' => {
                chars.next();
                col += 1;
                tokens.push(SpannedToken { token: Token::RBracket, line: start_line, col: start_col });
            }
            '{' => {
                chars.next();
                col += 1;
                tokens.push(SpannedToken { token: Token::LBrace, line: start_line, col: start_col });
            }
            '}' => {
                chars.next();
                col += 1;
                tokens.push(SpannedToken { token: Token::RBrace, line: start_line, col: start_col });
            }
            ';' => {
                // Comment till end of line
                chars.next();
                let mut comment = String::new();
                while let Some(&c) = chars.peek() {
                    if c == '\n' {
                        break;
                    }
                    comment.push(c);
                    chars.next();
                }
                tokens.push(SpannedToken {
                    token: Token::Comment(comment),
                    line: start_line,
                    col: start_col,
                });
            }
            '"' => {
                chars.next(); // skip opening quote
                col += 1;
                let mut string = String::new();
                while let Some(&c) = chars.peek() {
                    if c == '"' {
                        chars.next();
                        col += 1;
                        break;
                    }
                    if c == '\\' {
                        chars.next();
                        col += 1;
                        if let Some(&next) = chars.peek() {
                            match next {
                                'n' => string.push('\n'),
                                't' => string.push('\t'),
                                'r' => string.push('\r'),
                                '\\' => string.push('\\'),
                                '"' => string.push('"'),
                                _ => string.push(next),
                            }
                            chars.next();
                            col += 1;
                        }
                    } else {
                        string.push(c);
                        chars.next();
                        col += 1;
                    }
                }
                tokens.push(SpannedToken {
                    token: Token::String(string),
                    line: start_line,
                    col: start_col,
                });
            }
            '\'' => {
                chars.next();
                col += 1;
                tokens.push(SpannedToken { token: Token::Quote, line: start_line, col: start_col });
            }
            '`' => {
                chars.next();
                col += 1;
                tokens.push(SpannedToken { token: Token::SyntaxQuote, line: start_line, col: start_col });
            }
            '~' => {
                chars.next();
                col += 1;
                if let Some(&'@') = chars.peek() {
                    chars.next();
                    col += 1;
                    tokens.push(SpannedToken { token: Token::Splicing, line: start_line, col: start_col });
                } else {
                    tokens.push(SpannedToken { token: Token::Unquote, line: start_line, col: start_col });
                }
            }
            '^' => {
                chars.next();
                col += 1;
                tokens.push(SpannedToken { token: Token::Meta, line: start_line, col: start_col });
            }
            '@' => {
                chars.next();
                col += 1;
                tokens.push(SpannedToken { token: Token::Deref, line: start_line, col: start_col });
            }
            c if c.is_whitespace() => {
                chars.next();
                if c == '\n' {
                    line += 1;
                    col = 1;
                } else {
                    col += 1;
                }
            }
            c if c.is_numeric() || (c == '-' && matches!(chars.clone().nth(1), Some(d) if d.is_numeric())) => {
                let mut num_str = String::new();
                if c == '-' {
                    num_str.push(c);
                    chars.next();
                    col += 1;
                }
                while let Some(&c) = chars.peek() {
                    if c.is_numeric() {
                        num_str.push(c);
                        chars.next();
                        col += 1;
                    } else if c == '.' {
                        num_str.push(c);
                        chars.next();
                        col += 1;
                        // continue as float
                        while let Some(&c) = chars.peek() {
                            if c.is_numeric() {
                                num_str.push(c);
                                chars.next();
                                col += 1;
                            } else {
                                break;
                            }
                        }
                        let val: f64 = num_str.parse()?;
                        tokens.push(SpannedToken {
                            token: Token::Float(val),
                            line: start_line,
                            col: start_col,
                        });
                        break;
                    } else {
                        let val: i64 = num_str.parse()?;
                        tokens.push(SpannedToken {
                            token: Token::Number(val),
                            line: start_line,
                            col: start_col,
                        });
                        break;
                    }
                }
                if num_str.parse::<i64>().is_ok() && chars.peek().is_none() {
                    let val: i64 = num_str.parse()?;
                    tokens.push(SpannedToken {
                        token: Token::Number(val),
                        line: start_line,
                        col: start_col,
                    });
                }
            }
            ':' => {
                chars.next();
                col += 1;
                let mut kw = String::new();
                while let Some(&c) = chars.peek() {
                    if c.is_whitespace() || c == '(' || c == ')' || c == '[' || c == ']' || c == '{' || c == '}' {
                        break;
                    }
                    kw.push(c);
                    chars.next();
                    col += 1;
                }
                tokens.push(SpannedToken {
                    token: Token::Keyword(kw),
                    line: start_line,
                    col: start_col,
                });
            }
            _ => {
                // Symbol or bool/nil
                let mut sym = String::new();
                while let Some(&c) = chars.peek() {
                    if c.is_whitespace() || c == '(' || c == ')' || c == '[' || c == ']' || c == '{' || c == '}' || c == ';' || c == '"' || c == '\'' || c == '`' || c == '~' || c == '^' || c == '@' {
                        break;
                    }
                    sym.push(c);
                    chars.next();
                    col += 1;
                }
                let token = match sym.as_str() {
                    "true" => Token::Bool(true),
                    "false" => Token::Bool(false),
                    "nil" => Token::Nil,
                    _ => Token::Symbol(sym),
                };
                tokens.push(SpannedToken {
                    token,
                    line: start_line,
                    col: start_col,
                });
            }
        }
    }

    tokens.push(SpannedToken {
        token: Token::Eof,
        line,
        col,
    });

    Ok(tokens)
}
