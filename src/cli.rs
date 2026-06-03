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
    /// Компилирай .brs или Bars проект
    Build {
        #[arg(value_name = "FILE")]
        file: Option<PathBuf>,
        /// Изходен файл (по подразбиране: stdout)
        #[arg(short, long, value_name = "OUTPUT")]
        output: Option<PathBuf>,
        /// Компилатор: qbe (default) или llvm
        #[arg(long, default_value = "qbe")]
        backend: Backend,
        /// Release build с оптимизации
        #[arg(long)]
        release: bool,
        /// Cross-compilation target triple
        #[arg(long, value_name = "TRIPLE")]
        target: Option<String>,
    },
    /// Компилирай и изпълни .brs или Bars проект
    Run {
        #[arg(value_name = "FILE")]
        file: Option<PathBuf>,
        /// Компилатор: qbe (default) или llvm
        #[arg(long, default_value = "qbe")]
        backend: Backend,
        /// Release build с оптимизации
        #[arg(long)]
        release: bool,
        /// Cross-compilation target triple
        #[arg(long, value_name = "TRIPLE")]
        target: Option<String>,
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
    /// Стартирай LSP сървър
    Lsp,
    /// Създай нов Bars проект
    New {
        #[arg(value_name = "NAME")]
        name: String,
        /// Път към директория (по подразбиране: текуща)
        #[arg(short, long, value_name = "PATH")]
        path: Option<PathBuf>,
    },
    /// Добави dependency към текущия проект
    Add {
        #[arg(value_name = "PACKAGE")]
        package: String,
        /// Git URL
        #[arg(long, value_name = "URL")]
        git: Option<String>,
        /// Локален път
        #[arg(long, value_name = "PATH")]
        path: Option<String>,
        /// Версия
        #[arg(short, long, value_name = "VERSION")]
        version: Option<String>,
    },
}
