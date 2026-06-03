use clap::{Parser, Subcommand, ValueEnum};
use std::path::PathBuf;

#[derive(ValueEnum, Clone, Debug, PartialEq)]
pub enum Backend {
    /// QBE backend (fast AOT, default)
    Qbe,
    /// Cranelift backend (fast AOT/JIT)
    Cranelift,
    /// LLVM backend (optimized AOT, for --release)
    #[cfg(feature = "llvm-backend")]
    Llvm,
}

#[derive(Parser)]
#[command(name = "bars")]
#[command(about = "Bars — системен Lisp с ownership")]
#[command(version = "0.1.0")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand)]
pub enum Commands {
    /// Прочети .brs файл и покажи AST
    Read {
        #[arg(value_name = "FILE")]
        file: PathBuf,
    },
    /// Компилирай .brs до QBE IR
    Build {
        #[arg(value_name = "FILE")]
        file: PathBuf,
        /// Изходен файл (по подразбиране: stdout)
        #[arg(short, long, value_name = "OUTPUT")]
        output: Option<PathBuf>,
        /// Компилатор: qbe (default) или llvm
        #[arg(long, default_value = "qbe")]
        backend: Backend,
        /// Release build с оптимизации
        #[arg(long)]
        release: bool,
    },
    /// Компилирай и изпълни .brs файл
    Run {
        #[arg(value_name = "FILE")]
        file: PathBuf,
        /// Компилатор: qbe (default) или llvm
        #[arg(long, default_value = "qbe")]
        backend: Backend,
        /// Release build с оптимизации
        #[arg(long)]
        release: bool,
    },
    /// Стартирай REPL
    Repl,
    /// Провери ownership и/или типове
    Check {
        #[arg(value_name = "FILE")]
        file: PathBuf,
        /// Провери типове (type inference)
        #[arg(long)]
        types: bool,
    },
}
