use anyhow::{bail, Result};
use bars::{ast, cli::{Backend, Cli, Commands}, read_file};
use clap::Parser;
use std::io::Write;
use std::path::Path;
use std::process::Command;

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Read { file } => {
            let program = read_file(&file)?;
            for expr in &program.exprs {
                println!("{:#?}", expr);
            }
        }
        Commands::Build { file, output, backend, release: _release } => {
            match backend {
                Backend::Qbe => {
                    let program = read_file(&file)?;
                    let expanded = bars::expand_macros(&program)?;
                    check_ownership(&expanded)?;
                    let qbe_ir = bars::compile_to_qbe(&expanded)?;
                    if let Some(out) = output {
                        std::fs::write(&out, qbe_ir)?;
                        println!("Written to {}", out.display());
                    } else {
                        println!("{}", qbe_ir);
                    }
                }
                Backend::Cranelift => {
                    let program = read_file(&file)?;
                    let expanded = bars::expand_macros(&program)?;
                    check_ownership(&expanded)?;
                    let hir_program = bars::lower_and_optimize(&expanded)?;

                    let stem = file.file_stem().unwrap_or_default().to_string_lossy();
                    let obj_file = format!("/tmp/{}_{}.o", stem, std::process::id());

                    bars::backends::cranelift::compile_hir_to_object(
                        &hir_program,
                        std::path::Path::new(&obj_file),
                    )?;

                    if let Some(out) = output {
                        let bin_out = out;
                        let runtime_obj = format!("{}/runtime/bars_runtime.o", env!("CARGO_MANIFEST_DIR"));
                        let cc_compile = Command::new("cc")
                            .args([&obj_file, &runtime_obj, "-lgc", "-o"])
                            .arg(&bin_out)
                            .output()?;
                        if !cc_compile.status.success() {
                            let stderr = String::from_utf8_lossy(&cc_compile.stderr);
                            bail!("Link step failed:\n{}", stderr);
                        }
                        println!("Binary written to {}", bin_out.display());
                        let _ = std::fs::remove_file(&obj_file);
                    } else {
                        println!("Object file written to {}", obj_file);
                    }
                }
                #[cfg(feature = "llvm-backend")]
                Backend::Llvm => {
                    let program = read_file(&file)?;
                    let expanded = bars::expand_macros(&program)?;
                    check_ownership(&expanded)?;
                    let hir_program = bars::lower_and_optimize(&expanded)?;

                    let stem = file.file_stem().unwrap_or_default().to_string_lossy();
                    let obj_file = format!("/tmp/{}_{}.o", stem, std::process::id());

                    bars::backends::llvm::compile_hir_to_object(
                        &hir_program,
                        std::path::Path::new(&obj_file),
                        _release,
                    )?;

                    if let Some(out) = output {
                        let bin_out = out;
                        let runtime_obj = format!("{}/runtime/bars_runtime.o", env!("CARGO_MANIFEST_DIR"));
                        let cc_compile = Command::new("cc")
                            .args([&obj_file, &runtime_obj, "-lgc", "-o"])
                            .arg(&bin_out)
                            .output()?;
                        if !cc_compile.status.success() {
                            let stderr = String::from_utf8_lossy(&cc_compile.stderr);
                            bail!("Link step failed:\n{}", stderr);
                        }
                        println!("Binary written to {}", bin_out.display());
                        let _ = std::fs::remove_file(&obj_file);
                    } else {
                        println!("Object file written to {}", obj_file);
                    }
                }
            }
        }
        Commands::Run { file, backend, release: _release } => {
            match backend {
                Backend::Qbe => {
                    run_file_qbe(&file)?;
                }
                Backend::Cranelift => {
                    run_file_cranelift(&file)?;
                }
                #[cfg(feature = "llvm-backend")]
                Backend::Llvm => {
                    bars::compile_file_llvm(&file, _release)?;
                }
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
                        eprintln!("❌ Type error: {}", e);
                        std::process::exit(1);
                    }
                }
            } else {
                match bars::ownership::check_program(&expanded) {
                    Ok(()) => println!("✅ Ownership checks passed."),
                    Err(e) => {
                        eprintln!("❌ Ownership error: {}", e);
                        std::process::exit(1);
                    }
                }
            }
        }
    }

    Ok(())
}

fn check_ownership(program: &ast::Program) -> Result<()> {
    match bars::ownership::check_program(program) {
        Ok(()) => Ok(()),
        Err(e) => {
            // ResourceLeak checking is still experimental; treat as warning for now.
            if let bars::ownership::OwnershipError::ResourceLeak(_, _, _) = e {
                eprintln!("⚠️  Ownership warning: {}", e);
                Ok(())
            } else {
                bail!("❌ Ownership error: {}", e)
            }
        }
    }
}

fn run_file_qbe(file: &Path) -> Result<()> {
    let program = read_file(file)?;
    let expanded = bars::expand_macros(&program)?;
    check_ownership(&expanded)?;
    let qbe_ir = bars::compile_to_qbe(&expanded)?;

    // Write QBE IR to temp file
    let stem = file.file_stem().unwrap_or_default().to_string_lossy();
    let qbe_file = format!("/tmp/{}_{}.ssa", stem, std::process::id());
    let bin_file = format!("/tmp/{}_{}", stem, std::process::id());

    std::fs::write(&qbe_file, qbe_ir)?;

    // Compile: qbe file.ssa | cc -x assembler - -o binary
    let qbe_output = Command::new("qbe")
        .arg(&qbe_file)
        .output()?;

    if !qbe_output.status.success() {
        let stderr = String::from_utf8_lossy(&qbe_output.stderr);
        bail!("QBE compilation failed:\n{}", stderr);
    }

    let s_file = format!("/tmp/{}_{}.s", stem, std::process::id());
    std::fs::write(&s_file, &qbe_output.stdout)?;

    let runtime_obj = format!("{}/runtime/bars_runtime.o", env!("CARGO_MANIFEST_DIR"));
    let cc_compile = Command::new("cc")
        .args([&s_file, &runtime_obj, "-lgc", "-o", &bin_file])
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

fn run_file_cranelift(file: &Path) -> Result<()> {
    let program = read_file(file)?;
    let expanded = bars::expand_macros(&program)?;
    check_ownership(&expanded)?;
    let hir_program = bars::lower_and_optimize(&expanded)?;

    let stem = file.file_stem().unwrap_or_default().to_string_lossy();
    let obj_file = format!("/tmp/{}_{}.o", stem, std::process::id());
    let bin_file = format!("/tmp/{}_{}", stem, std::process::id());

    bars::backends::cranelift::compile_hir_to_object(&hir_program, Path::new(&obj_file))?;

    let runtime_obj = format!("{}/runtime/bars_runtime.o", env!("CARGO_MANIFEST_DIR"));
    let cc_compile = Command::new("cc")
        .args([&obj_file, &runtime_obj, "-lgc", "-o", &bin_file])
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
    let _ = std::fs::remove_file(&obj_file);
    let _ = std::fs::remove_file(&bin_file);

    Ok(())
}

fn run_repl_jit() -> Result<()> {
    println!("Bars REPL v0.1.0 (Cranelift JIT)");
    println!("Натисни Ctrl+D за изход.");
    println!();

    let mut backend = match bars::backends::cranelift::CraneliftBackend::new() {
        Ok(b) => b,
        Err(e) => {
            eprintln!("Грешка при инициализация на JIT: {}", e);
            return Ok(());
        }
    };

    let mut input = String::new();
    let mut depth = 0i32;

    loop {
        let prompt = if depth > 0 { "  " } else { "bars> " };
        print!("{}", prompt);
        std::io::stdout().flush()?;

        let mut line = String::new();
        match std::io::stdin().read_line(&mut line) {
            Ok(0) => {
                println!();
                break;
            }
            Ok(_) => {}
            Err(e) => {
                eprintln!("Грешка при четене: {}", e);
                break;
            }
        }

        for ch in line.chars() {
            match ch {
                '(' | '[' => depth += 1,
                ')' | ']' => depth -= 1,
                _ => {}
            }
        }

        input.push_str(&line);

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
                    if let Err(e) = check_ownership(&expanded) {
                        eprintln!("{}", e);
                        input.clear();
                        continue;
                    }
                    match bars::lower_and_optimize(&expanded) {
                        Ok(hir_program) => {
                            match backend.compile_hir(&hir_program) {
                                Ok(result) => {
                                    println!("{}", result);
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

    println!("Довиждане!");
    Ok(())
}
