pub mod ast;
pub mod backends;
pub mod cli;
pub mod diagnostics;
pub mod hir;
pub mod lsp;
pub mod modules;
pub mod r#macro;
pub mod ownership;
pub mod reader;
pub mod target;
pub mod types;

use anyhow::Result;
use std::collections::HashSet;
#[cfg(feature = "llvm-backend")]
use std::io::Write;

/// Read and parse a Bars source file, resolving (load ...) and (require ...) dependencies
pub fn read_file(path: &std::path::Path) -> Result<ast::Program> {
    let source = std::fs::read_to_string(path)?;
    let mut program = reader::read(&source)?;
    let base = path.parent().unwrap_or(std::path::Path::new("."));
    let mut loaded = HashSet::new();
    loaded.insert(std::fs::canonicalize(path)?);
    resolve_loads(&mut program, base, &mut loaded)?;
    let mut visited = HashSet::new();
    modules::resolve_requires(&mut program, base, &mut visited)?;
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

pub(crate) fn resolve_loads(program: &mut ast::Program, base: &std::path::Path, loaded: &mut HashSet<std::path::PathBuf>) -> Result<()> {
    let mut new_exprs = Vec::new();
    for expr in std::mem::take(&mut program.exprs) {
        if let ast::Expr::FnCall { func, args, .. } = &expr {
            if let ast::Expr::Symbol(ast::Symbol(name), _) = func.as_ref() {
                if name == "load" && args.len() == 1 {
                    if let ast::Expr::String(path_str, _) = &args[0] {
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

/// Lower AST to HIR and run optimization passes.
pub fn lower_and_optimize(program: &ast::Program) -> Result<hir::Program> {
    // Type-check first — generics require correct type inference
    type_check(program).map_err(|e| anyhow::anyhow!("Type error: {}", e))?;
    
    let mut hir_program = hir::lowering::lower(program)?;
    hir::optimize::constant_fold(&mut hir_program);
    hir::optimize::tail_call_optimize(&mut hir_program);
    hir::optimize::remove_dead_blocks(&mut hir_program);
    Ok(hir_program)
}

/// Compile a program to QBE IR string via HIR lowering
pub fn compile_to_qbe(program: &ast::Program) -> Result<String> {
    let hir_program = lower_and_optimize(program)?;
    let mut backend = backends::qbe_hir::QbeHIRBackend::new();
    for (name, fields) in &hir_program.struct_registry {
        backend.add_struct(name, fields.clone());
    }
    backend.compile(&hir_program)
}

/// Full pipeline: read → expand → compile via QBE HIR (legacy)
pub fn compile_file(path: &std::path::Path) -> Result<String> {
    let program = read_file(path)?;
    let expanded = expand_macros(&program)?;
    compile_to_qbe(&expanded)
}

/// Full pipeline: read → expand → LLVM object file
#[cfg(feature = "llvm-backend")]
pub fn compile_file_llvm(path: &std::path::Path, optimize: bool) -> Result<()> {
    let program = read_file(path)?;
    let expanded = expand_macros(&program)?;
    let hir_program = lower_and_optimize(&expanded)?;

    let stem = path.file_stem().unwrap_or_default().to_string_lossy();
    let obj_file = format!("/tmp/{}_{}.o", stem, std::process::id());

    backends::llvm::compile_hir_to_object(
        &hir_program,
        std::path::Path::new(&obj_file),
        optimize,
    )?;

    // Link with runtime and produce binary
    let bin_file = format!("/tmp/{}_{}.out", stem, std::process::id());
    let runtime_obj = format!("{}/../runtime/bars_runtime.o", env!("CARGO_MANIFEST_DIR"));
    let link = std::process::Command::new("cc")
        .args([&obj_file, &runtime_obj, "-lgc", "-lm", "-o", &bin_file])
        .output()?;

    if !link.status.success() {
        let stderr = String::from_utf8_lossy(&link.stderr);
        anyhow::bail!("Link step failed:\n{}", stderr);
    }

    // Run the binary
    let run = std::process::Command::new(&bin_file).output()?;
    std::io::stdout().write_all(&run.stdout)?;
    std::io::stderr().write_all(&run.stderr)?;

    let _ = std::fs::remove_file(&obj_file);
    let _ = std::fs::remove_file(&bin_file);

    Ok(())
}

/// Infer and check types for a program.
/// Returns the inferred type scheme for each top-level definition.
pub fn infer_types(program: &ast::Program) -> Result<Vec<(String, types::TypeScheme)>, types::TypeError> {
    let mut ctx = types::InferCtx::new();
    let (_subst, defn_types) = ctx.infer_program(program)?;
    Ok(defn_types)
}

/// Type-check a program, returning an error if types don't match.
pub fn type_check(program: &ast::Program) -> Result<(), types::TypeError> {
    let mut ctx = types::InferCtx::new();
    let _ = ctx.infer_program(program)?;
    Ok(())
}
