use clap::{Parser, Subcommand};
use std::path::PathBuf;

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
    },
    /// Компилирай и изпълни .brs файл
    Run {
        #[arg(value_name = "FILE")]
        file: PathBuf,
    },
    /// Стартирай REPL
    Repl,
    /// Провери ownership грешки
    Check {
        #[arg(value_name = "FILE")]
        file: PathBuf,
    },
}
