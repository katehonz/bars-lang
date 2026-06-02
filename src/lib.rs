pub mod ast;
pub mod backends;
pub mod cli;
pub mod hir;
pub mod r#macro;
pub mod ownership;
pub mod reader;

use anyhow::Result;
use std::collections::HashSet;

/// Read and parse a Bars source file, resolving (load ...) dependencies
pub fn read_file(path: &std::path::Path) -> Result<ast::Program> {
    let source = std::fs::read_to_string(path)?;
    let mut program = reader::read(&source)?;
    let base = path.parent().unwrap_or(std::path::Path::new("."));
    let mut loaded = HashSet::new();
    loaded.insert(std::fs::canonicalize(path)?);
    resolve_loads(&mut program, base, &mut loaded)?;
    Ok(program)
}

fn find_file(base: &std::path::Path, path_str: &str) -> Option<std::path::PathBuf> {
    let mut current = Some(base);
    while let Some(dir) = current {
        let candidate = dir.join(path_str);
        if candidate.exists() {
            return Some(candidate);
        }
        current = dir.parent();
    }
    None
}

fn resolve_loads(program: &mut ast::Program, base: &std::path::Path, loaded: &mut HashSet<std::path::PathBuf>) -> Result<()> {
    let mut new_exprs = Vec::new();
    for expr in std::mem::take(&mut program.exprs) {
        if let ast::Expr::FnCall { func, args, .. } = &expr {
            if let ast::Expr::Symbol(ast::Symbol(name)) = func.as_ref() {
                if name == "load" && args.len() == 1 {
                    if let ast::Expr::String(path_str) = &args[0] {
                        let dep_path = find_file(base, path_str)
                            .ok_or_else(|| anyhow::anyhow!("Cannot resolve load path '{}' from '{}'", path_str, base.display()))?;
                        let canonical = std::fs::canonicalize(&dep_path)
                            .map_err(|e| anyhow::anyhow!("Cannot canonicalize load path '{}': {}", path_str, e))?;
                        if !loaded.contains(&canonical) {
                            loaded.insert(canonical.clone());
                            let dep_source = std::fs::read_to_string(&dep_path)
                                .map_err(|e| anyhow::anyhow!("Cannot read loaded file '{}': {}", path_str, e))?;
                            let mut dep_program = reader::read(&dep_source)?;
                            resolve_loads(&mut dep_program, base, loaded)?;
                            new_exprs.extend(dep_program.exprs);
                        }
                        continue;
                    }
                }
            }
        }
        new_exprs.push(expr);
    }
    program.exprs = new_exprs;
    Ok(())
}

/// Expand macros in a program
pub fn expand_macros(program: &ast::Program) -> Result<ast::Program, r#macro::MacroError> {
    r#macro::expand_program(program)
}

/// Compile a program to QBE IR string via HIR lowering
pub fn compile_to_qbe(program: &ast::Program) -> Result<String> {
    let hir_program = hir::lowering::lower(program)?;
    let mut backend = backends::qbe_hir::QbeHIRBackend::new();
    for (name, fields) in &hir_program.struct_registry {
        backend.add_struct(name, fields.clone());
    }
    backend.compile(&hir_program)
}

/// Full pipeline: read → expand → compile (legacy)
pub fn compile_file(path: &std::path::Path) -> Result<String> {
    let program = read_file(path)?;
    let expanded = expand_macros(&program)?;
    compile_to_qbe(&expanded)
}
