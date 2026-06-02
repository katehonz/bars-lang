pub mod lexer;
pub mod parser;

use crate::ast::Program;
use anyhow::Result;

/// Read a Bars source string into an AST Program
pub fn read(source: &str) -> Result<Program> {
    let tokens = lexer::tokenize(source)?;
    let program = parser::parse(&tokens)?;
    Ok(program)
}
