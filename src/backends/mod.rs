pub mod cranelift;
pub mod qbe;

use crate::ast::Program;
use anyhow::Result;

/// Trait for compiler backends
pub trait Backend {
    /// Generate code from AST Program
    fn compile(&mut self, program: &Program) -> Result<String>;
}
