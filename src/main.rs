use anyhow::{bail, Result};
use bars::{ast, cli::{Backend, Cli, Commands}, diagnostics, read_file, target::{find_linker, find_runtime_obj, TargetTriple}};
use clap::Parser;
use std::io::Write;
use std::path::Path;
use std::process::Command;

// C runtime functions available because build.rs links libbars_runtime.a
unsafe extern "C" {
    fn bars_print_any_i64(val: i64);
    fn bars_print_newline();
    fn bars_set_args(argc: i32, argv: *mut *mut std::os::raw::c_char);
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Read { file } => {
            let program = read_file(&file)?;
            for expr in &program.exprs {
                println!("{:#?}", expr);
            }
        }
        Commands::Build { file, output, backend, release: _release, target } => {
            let target_triple = target
                .as_deref()
                .map(TargetTriple::parse)
                .transpose()?;
            if let Some(file) = file {
                // Single file mode
                let bin_out = output.unwrap_or_else(|| {
                    let stem = file.file_stem().unwrap_or_default().to_string_lossy();
                    std::path::PathBuf::from(stem.to_string())
                });
                match backend {
                    Backend::Qbe => {
                        build_qbe(&file, &bin_out, _release, target_triple.as_ref())?;
                    }
                    Backend::Cranelift => {
                        build_cranelift(&file, &bin_out, _release, target_triple.as_ref())?;
                    }
                    #[cfg(feature = "llvm-backend")]
                    Backend::Llvm => {
                        build_llvm(&file, &bin_out, _release, target_triple.as_ref())?;
                    }
                }
                println!("Binary written to {}", bin_out.display());
            } else {
                // Project mode
                let (project_dir, _) = bars_pkg::find_manifest()?
                    .ok_or_else(|| anyhow::anyhow!("няма Bars.toml в текущата директория или нейните родители"))?;
                let backend_str = match backend {
                    Backend::Qbe => "qbe",
                    Backend::Cranelift => "cranelift",
                    #[cfg(feature = "llvm-backend")]
                    Backend::Llvm => "llvm",
                };
                let bars_bin = std::env::current_exe()?;
                bars_pkg::build_project(&project_dir, _release, backend_str, &bars_bin)?;
            }
        }
        Commands::Run { file, backend, release: _release, target, args } => {
            let target_triple = target
                .as_deref()
                .map(TargetTriple::parse)
                .transpose()?;
            if let Some(file) = file {
                // Single file mode
                match backend {
                    Backend::Qbe => {
                        run_file_qbe(&file, _release, target_triple.as_ref())?;
                    }
                    Backend::Cranelift => {
                        let mut all_args = vec![file.display().to_string()];
                        all_args.extend(args);
                        run_file_cranelift(&file, _release, target_triple.as_ref(), all_args)?;
                    }
                    #[cfg(feature = "llvm-backend")]
                    Backend::Llvm => {
                        bars::compile_file_llvm(&file, _release)?;
                    }
                }
            } else {
                // Project mode
                let (project_dir, _) = bars_pkg::find_manifest()?
                    .ok_or_else(|| anyhow::anyhow!("няма Bars.toml в текущата директория или нейните родители"))?;
                let backend_str = match backend {
                    Backend::Qbe => "qbe",
                    Backend::Cranelift => "cranelift",
                    #[cfg(feature = "llvm-backend")]
                    Backend::Llvm => "llvm",
                };
                let bars_bin = std::env::current_exe()?;
                bars_pkg::run_project(&project_dir, _release, backend_str, &bars_bin)?;
            }
        }
        Commands::Repl => {
            run_repl_jit()?;
        }
        Commands::Check { file, types } => {
            let program = read_file(&file)?;
            let expanded = bars::expand_macros(&program)?;

            if types {
                match bars::infer_types(&expanded) {
                    Ok(results) => {
                        println!("✅ Type inference passed.");
                        for (name, ty) in &results {
                            println!("  {} : {}", name, ty);
                        }
                    }
                    Err(e) => {
                        let (line, col) = e.location();
                        let diag = diagnostics::Diagnostic::error(e.short_message())
                            .with_location(file.display().to_string(), line, col);
                        diagnostics::emit(&diag);
                        std::process::exit(1);
                    }
                }
            } else {
                match bars::ownership::check_program(&expanded) {
                    Ok(()) => println!("✅ Ownership checks passed."),
                    Err(e) => {
                        let (line, col) = e.location();
                        let diag = diagnostics::Diagnostic::error(e.short_message())
                            .with_location(file.display().to_string(), line, col);
                        diagnostics::emit(&diag);
                        std::process::exit(1);
                    }
                }
            }
        }
        Commands::Lsp => {
            tokio::runtime::Runtime::new()
                .expect("Failed to create Tokio runtime")
                .block_on(bars::lsp::run_stdio());
        }
        Commands::New { name, path } => {
            bars_pkg::new_project(&name, path.as_deref())?;
        }
        Commands::Add { package, git, path, version } => {
            let dep = if let Some(git_url) = git {
                bars_pkg::Dependency::Detailed(bars_pkg::DependencyDetail {
                    version,
                    git: Some(git_url),
                    path: None,
                })
            } else if let Some(path_str) = path {
                bars_pkg::Dependency::Detailed(bars_pkg::DependencyDetail {
                    version,
                    git: None,
                    path: Some(path_str),
                })
            } else if let Some(ver) = version {
                bars_pkg::Dependency::Simple(ver)
            } else {
                bars_pkg::Dependency::Simple("*".to_string())
            };
            bars_pkg::add_dependency(&package, dep)?;
        }
    }

    Ok(())
}

fn check_ownership(program: &ast::Program, file: &Path) -> Result<()> {
    match bars::ownership::check_program(program) {
        Ok(()) => Ok(()),
        Err(e) => {
            // ResourceLeak checking is still experimental; treat as warning for now.
            if let bars::ownership::OwnershipError::ResourceLeak(_, _, _) = e {
                let (line, col) = e.location();
                let diag = diagnostics::Diagnostic::warning(e.short_message())
                    .with_location(file.display().to_string(), line, col);
                diagnostics::emit(&diag);
                Ok(())
            } else {
                let (line, col) = e.location();
                let diag = diagnostics::Diagnostic::error(e.short_message())
                    .with_location(file.display().to_string(), line, col);
                diagnostics::emit(&diag);
                bail!("ownership check failed")
            }
        }
    }
}

fn build_qbe(file: &Path, bin_out: &Path, release: bool, target: Option<&TargetTriple>) -> Result<()> {
    let program = read_file(file)?;
    let expanded = bars::expand_macros(&program)?;
    check_ownership(&expanded, file)?;
    let qbe_ir = bars::compile_to_qbe(&expanded)?; eprintln!("{}", qbe_ir);

    let stem = file.file_stem().unwrap_or_default().to_string_lossy();
    let qbe_file = format!("/tmp/{}_{}.ssa", stem, std::process::id());
    let s_file = format!("/tmp/{}_{}.s", stem, std::process::id());

    std::fs::write(&qbe_file, qbe_ir)?;

    let mut qbe_cmd = Command::new("qbe");
    qbe_cmd.arg(&qbe_file);
    if let Some(t) = target {
        qbe_cmd.arg("-t").arg(t.qbe_target()?);
    }
    let qbe_output = qbe_cmd.output()?;

    if !qbe_output.status.success() {
        let stderr = String::from_utf8_lossy(&qbe_output.stderr);
        bail!("QBE compilation failed:\n{}", stderr);
    }

    std::fs::write(&s_file, &qbe_output.stdout)?;

    let runtime_obj = find_runtime_obj(target.unwrap_or(&TargetTriple::host()))?;
    let runtime_obj_str = runtime_obj.to_string_lossy().to_string();
    let (linker, linker_extra) = find_linker(target.unwrap_or(&TargetTriple::host()))?;
    let mut cc_args: Vec<&str> = Vec::new();
    for extra in &linker_extra {
        cc_args.push(extra.as_str());
    }
    cc_args.push(s_file.as_str());
    cc_args.push(runtime_obj_str.as_str());
    cc_args.push("-lgc");
    cc_args.push("-lm");
    cc_args.push("-no-pie");
    if release {
        cc_args.push("-O2");
    }
    cc_args.push("-o");
    cc_args.push(bin_out.to_str().unwrap_or("a.out"));
    let cc_compile = Command::new(&linker)
        .args(&cc_args)
        .output()?;

    if !cc_compile.status.success() {
        let stderr = String::from_utf8_lossy(&cc_compile.stderr);
        bail!("Link step failed:\n{}", stderr);
    }

    let _ = std::fs::remove_file(&qbe_file);
    let _ = std::fs::remove_file(&s_file);

    Ok(())
}

fn build_cranelift(file: &Path, bin_out: &Path, release: bool, target: Option<&TargetTriple>) -> Result<()> {
    let program = read_file(file)?;
    let expanded = bars::expand_macros(&program)?;
    check_ownership(&expanded, file)?;
    let mut hir_program = bars::lower_and_optimize(&expanded)?;

    // Rename Bars main to _bars_main so we can inject a C wrapper
    for func in &mut hir_program.funcs {
        if func.name == "main" {
            func.name = "_bars_main".to_string();
        }
    }

    let stem = file.file_stem().unwrap_or_default().to_string_lossy();
    let obj_file = format!("/tmp/{}_{}.o", stem, std::process::id());

    bars::backends::cranelift::compile_hir_to_object(
        &hir_program,
        std::path::Path::new(&obj_file),
        release,
        target,
    )?;

    // Build a small C wrapper that calls bars_set_args then _bars_main
    let wrapper_c = format!("/tmp/{}_{}_wrapper.c", stem, std::process::id());
    let wrapper_o = format!("/tmp/{}_{}_wrapper.o", stem, std::process::id());
    std::fs::write(&wrapper_c, r#"
#include <stdint.h>
extern void bars_set_args(int argc, char** argv);
extern int64_t _bars_main(void);
int main(int argc, char** argv) {
    bars_set_args(argc, argv);
    return (int)_bars_main();
}
"#)?;
    let wrapper_compile = Command::new("cc")
        .args(["-c", &wrapper_c, "-o", &wrapper_o])
        .output()?;
    if !wrapper_compile.status.success() {
        let stderr = String::from_utf8_lossy(&wrapper_compile.stderr);
        bail!("Wrapper compilation failed:
{}", stderr);
    }

    let runtime_obj = find_runtime_obj(target.unwrap_or(&TargetTriple::host()))?;
    let runtime_obj_str = runtime_obj.to_string_lossy().to_string();
    let (linker, linker_extra) = find_linker(target.unwrap_or(&TargetTriple::host()))?;
    let mut link_args: Vec<&str> = Vec::new();
    for extra in &linker_extra {
        link_args.push(extra.as_str());
    }
    link_args.push(obj_file.as_str());
    link_args.push(wrapper_o.as_str());
    link_args.push(runtime_obj_str.as_str());
    link_args.push("-lgc");
    link_args.push("-lm");
    link_args.push("-no-pie");
    link_args.push("-Wl,-z,now");
    if release {
        link_args.push("-O2");
    }
    link_args.push("-o");
    link_args.push(bin_out.to_str().unwrap_or("a.out"));
    let cc_compile = Command::new(&linker)
        .args(&link_args)
        .output()?;

    if !cc_compile.status.success() {
        let stderr = String::from_utf8_lossy(&cc_compile.stderr);
        bail!("Link step failed:\n{}", stderr);
    }

    let _ = std::fs::remove_file(&obj_file);
    let _ = std::fs::remove_file(&wrapper_c);
    let _ = std::fs::remove_file(&wrapper_o);

    Ok(())
}

#[cfg(feature = "llvm-backend")]
fn build_llvm(file: &Path, bin_out: &Path, release: bool, target: Option<&TargetTriple>) -> Result<()> {
    let program = read_file(file)?;
    let expanded = bars::expand_macros(&program)?;
    check_ownership(&expanded, file)?;
    let hir_program = bars::lower_and_optimize(&expanded)?;

    let stem = file.file_stem().unwrap_or_default().to_string_lossy();
    let obj_file = format!("/tmp/{}_{}.o", stem, std::process::id());

    bars::backends::llvm::compile_hir_to_object(
        &hir_program,
        std::path::Path::new(&obj_file),
        release,
        target,
    )?;

    let runtime_obj = find_runtime_obj(target.unwrap_or(&TargetTriple::host()))?;
    let runtime_obj_str = runtime_obj.to_string_lossy().to_string();
    let (linker, linker_extra) = find_linker(target.unwrap_or(&TargetTriple::host()))?;
    let mut link_args = vec![obj_file.as_str(), runtime_obj_str.as_str(), "-lgc", "-lm", "-no-pie", "-o"];
    for extra in &linker_extra {
        link_args.push(extra.as_str());
    }
    let cc_compile = Command::new(&linker)
        .args(&link_args)
        .arg(bin_out)
        .output()?;

    if !cc_compile.status.success() {
        let stderr = String::from_utf8_lossy(&cc_compile.stderr);
        bail!("Link step failed:\n{}", stderr);
    }

    let _ = std::fs::remove_file(&obj_file);

    Ok(())
}

fn run_file_qbe(file: &Path, release: bool, target: Option<&TargetTriple>) -> Result<()> {
    let program = read_file(file)?;
    let expanded = bars::expand_macros(&program)?;
    check_ownership(&expanded, file)?;
    let qbe_ir = bars::compile_to_qbe(&expanded)?; eprintln!("{}", qbe_ir);

    // Write QBE IR to temp file
    let stem = file.file_stem().unwrap_or_default().to_string_lossy();
    let qbe_file = format!("/tmp/{}_{}.ssa", stem, std::process::id());
    let bin_file = format!("/tmp/{}_{}", stem, std::process::id());

    std::fs::write(&qbe_file, qbe_ir)?;

    // Compile: qbe file.ssa | cc -x assembler - -o binary
    let mut qbe_cmd = Command::new("qbe");
    qbe_cmd.arg(&qbe_file);
    if let Some(t) = target {
        qbe_cmd.arg("-t").arg(t.qbe_target()?);
    }
    let qbe_output = qbe_cmd.output()?;

    if !qbe_output.status.success() {
        let stderr = String::from_utf8_lossy(&qbe_output.stderr);
        bail!("QBE compilation failed:\n{}", stderr);
    }

    let s_file = format!("/tmp/{}_{}.s", stem, std::process::id());
    std::fs::write(&s_file, &qbe_output.stdout)?;

    let runtime_obj = find_runtime_obj(target.unwrap_or(&TargetTriple::host()))?;
    let runtime_obj_str = runtime_obj.to_string_lossy().to_string();
    let (linker, linker_extra) = find_linker(target.unwrap_or(&TargetTriple::host()))?;
    let mut cc_args: Vec<&str> = Vec::new();
    for extra in &linker_extra {
        cc_args.push(extra.as_str());
    }
    cc_args.push(s_file.as_str());
    cc_args.push(runtime_obj_str.as_str());
    cc_args.push("-lgc");
    cc_args.push("-lm");
    cc_args.push("-no-pie");
    if release {
        cc_args.push("-O2");
    }
    cc_args.push("-o");
    cc_args.push(bin_file.as_str());
    let cc_compile = Command::new(&linker)
        .args(&cc_args)
        .output()?;

    if !cc_compile.status.success() {
        let stderr = String::from_utf8_lossy(&cc_compile.stderr);
        bail!("Link step failed:\n{}", stderr);
    }

    // Run binary
    let run = Command::new(&bin_file).output()?;
    std::io::stdout().write_all(&run.stdout)?;
    std::io::stderr().write_all(&run.stderr)?;

    // Cleanup
    let _ = std::fs::remove_file(&qbe_file);
    let _ = std::fs::remove_file(&s_file);
    let _ = std::fs::remove_file(&bin_file);

    Ok(())
}

fn run_file_cranelift(file: &Path, _release: bool, _target: Option<&TargetTriple>, args: Vec<String>) -> Result<()> {
    let program = read_file(file)?;
    let expanded = bars::expand_macros(&program)?;
    check_ownership(&expanded, file)?;
    let hir_program = bars::lower_and_optimize(&expanded)?;

    // Set args for the JIT-compiled program
    let c_args: Vec<std::ffi::CString> = args.iter()
        .map(|s| std::ffi::CString::new(s.clone()).unwrap())
        .collect();
    let mut ptrs: Vec<*mut std::os::raw::c_char> = c_args.iter()
        .map(|s| s.as_ptr() as *mut std::os::raw::c_char)
        .collect();
    ptrs.push(std::ptr::null_mut());
    unsafe {
        bars_set_args(ptrs.len() as i32 - 1, ptrs.as_mut_ptr());
    }

    let mut backend = bars::backends::cranelift::CraneliftBackend::new()?;
    let result = backend.compile_hir(&hir_program)?;
    unsafe {
        bars_print_any_i64(result);
        bars_print_newline();
    }
    Ok(())
}

fn run_repl_jit() -> Result<()> {
    println!("Bars REPL v0.1.0 (Cranelift JIT)");
    println!("Натисни Ctrl+D или напиши :quit за изход.");
    println!();

    let mut backend = match bars::backends::cranelift::CraneliftBackend::new() {
        Ok(b) => b,
        Err(e) => {
            eprintln!("Грешка при инициализация на JIT: {}", e);
            return Ok(());
        }
    };

    let mut rl = rustyline::DefaultEditor::new()?;
    let history_path = std::path::PathBuf::from(".bars_history");
    let _ = rl.load_history(&history_path);

    let mut input = String::new();
    let mut depth = 0i32;
    let mut repl_counter = 0usize;

    loop {
        let prompt = if depth > 0 { "  " } else { "bars> " };
        let line = match rl.readline(prompt) {
            Ok(line) => line,
            Err(rustyline::error::ReadlineError::Interrupted) => {
                println!("^C");
                if !input.is_empty() {
                    input.clear();
                    depth = 0;
                    continue;
                }
                break;
            }
            Err(rustyline::error::ReadlineError::Eof) => {
                println!();
                break;
            }
            Err(e) => {
                eprintln!("Грешка при четене: {}", e);
                break;
            }
        };

        rl.add_history_entry(&line)?;

        // Special REPL commands
        let trimmed = line.trim();
        if trimmed == ":quit" || trimmed == ":q" {
            break;
        }
        if trimmed == ":help" || trimmed == ":h" {
            println!("REPL команди:");
            println!("  :quit, :q    — изход");
            println!("  :help, :h    — тази помощ");
            println!("  :ast <expr>  — покажи AST");
            println!("  :type <expr> — покажи inferred тип");
            continue;
        }
        if trimmed.starts_with(":ast ") {
            let expr_str = &trimmed[4..].trim();
            match bars::reader::read(expr_str) {
                Ok(program) => {
                    for expr in &program.exprs {
                        println!("{:#?}", expr);
                    }
                }
                Err(e) => eprintln!("Грешка при парсване: {}", e),
            }
            continue;
        }
        if trimmed.starts_with(":type ") {
            let expr_str = &trimmed[5..].trim();
            match bars::reader::read(expr_str) {
                Ok(program) => {
                    match bars::infer_types(&program) {
                        Ok(results) => {
                            for (name, ty) in &results {
                                println!("  {} : {}", name, ty);
                            }
                        }
                        Err(e) => eprintln!("Type error: {}", e),
                    }
                }
                Err(e) => eprintln!("Грешка при парсване: {}", e),
            }
            continue;
        }

        for ch in line.chars() {
            match ch {
                '(' | '[' => depth += 1,
                ')' | ']' => depth -= 1,
                _ => {}
            }
        }

        input.push_str(&line);
        input.push('\n');

        if depth == 0 && !input.trim().is_empty() {
            match bars::reader::read(&input) {
                Ok(program) => {
                    let expanded = match bars::expand_macros(&program) {
                        Ok(p) => p,
                        Err(e) => {
                            eprintln!("Грешка при макроси: {}", e);
                            input.clear();
                            continue;
                        }
                    };
                    if let Err(e) = check_ownership(&expanded, Path::new("<repl>")) {
                        eprintln!("{}", e);
                        input.clear();
                        continue;
                    }
                    match bars::lower_and_optimize(&expanded) {
                        Ok(mut hir_program) => {
                            // Rename main to avoid duplicate definitions in REPL
                            let entry_name = format!("main_{}", repl_counter);
                            for func in &mut hir_program.funcs {
                                if func.name == "main" {
                                    func.name = entry_name.clone();
                                }
                            }
                            repl_counter += 1;
                            match backend.compile_hir_entry(&hir_program, &entry_name) {
                                Ok(result) => {
                                    unsafe {
                                        bars_print_any_i64(result);
                                        bars_print_newline();
                                    }
                                }
                                Err(e) => {
                                    eprintln!("Грешка при JIT компилация: {}", e);
                                }
                            }
                        }
                        Err(e) => {
                            eprintln!("Грешка при HIR lowering: {}", e);
                        }
                    }
                }
                Err(e) => {
                    eprintln!("Грешка при парсване: {}", e);
                }
            }
            input.clear();
        }
    }

    let _ = rl.save_history(&history_path);
    println!("Довиждане!");
    Ok(())
}
