use std::io::IsTerminal;

/// Determine whether to use colors based on environment and terminal
fn use_color() -> bool {
    match std::env::var("BARS_COLOR").as_deref() {
        Ok("always") => true,
        Ok("never") => false,
        _ => std::io::stderr().is_terminal(),
    }
}

/// ANSI color codes
pub const RESET: &str = "\x1b[0m";
pub const BOLD: &str = "\x1b[1m";
pub const RED: &str = "\x1b[31m";
pub const GREEN: &str = "\x1b[32m";
pub const YELLOW: &str = "\x1b[33m";
pub const CYAN: &str = "\x1b[36m";

/// Severity of a diagnostic message
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Severity {
    Error,
    Warning,
    Note,
}

impl Severity {
    pub fn label(&self) -> &'static str {
        match self {
            Severity::Error => "error",
            Severity::Warning => "warning",
            Severity::Note => "note",
        }
    }

    pub fn color(&self) -> &'static str {
        match self {
            Severity::Error => RED,
            Severity::Warning => YELLOW,
            Severity::Note => CYAN,
        }
    }
}

/// A single diagnostic message with source location
#[derive(Debug, Clone)]
pub struct Diagnostic {
    pub severity: Severity,
    pub message: String,
    pub file: Option<String>,
    pub line: usize,
    pub col: usize,
}

impl Diagnostic {
    pub fn error(message: impl Into<String>) -> Self {
        Self {
            severity: Severity::Error,
            message: message.into(),
            file: None,
            line: 0,
            col: 0,
        }
    }

    pub fn warning(message: impl Into<String>) -> Self {
        Self {
            severity: Severity::Warning,
            message: message.into(),
            file: None,
            line: 0,
            col: 0,
        }
    }

    pub fn with_location(mut self, file: impl Into<String>, line: usize, col: usize) -> Self {
        self.file = Some(file.into());
        self.line = line;
        self.col = col;
        self
    }
}

/// Emit a diagnostic to stderr with colors and source context
pub fn emit(diagnostic: &Diagnostic) {
    let color = use_color();

    if !color {
        emit_plain(diagnostic);
        return;
    }

    let sev = &diagnostic.severity;
    let label = sev.label();
    let sev_color = sev.color();

    // Header: {bold}{red}error:{reset} {bold}message{reset}
    eprintln!("{BOLD}{sev_color}{label}:{RESET} {BOLD}{}{RESET}", diagnostic.message);

    // Location line
    if let Some(ref file) = diagnostic.file {
        if diagnostic.line > 0 {
            eprintln!(
                " {CYAN}-->{RESET} {}:{BOLD}{}{RESET}:{BOLD}{}{RESET}",
                file, diagnostic.line, diagnostic.col
            );
        } else {
            eprintln!(" {CYAN}-->{RESET} {}", file);
        }
    }

    print_source_context(diagnostic, true);
}

fn emit_plain(diagnostic: &Diagnostic) {
    let label = diagnostic.severity.label();
    eprintln!("{}: {}", label, diagnostic.message);
    if let Some(ref file) = diagnostic.file {
        if diagnostic.line > 0 {
            eprintln!("  at {}:{}:{}", file, diagnostic.line, diagnostic.col);
        } else {
            eprintln!("  at {}", file);
        }
    }
    print_source_context(diagnostic, false);
}

fn print_source_context(diagnostic: &Diagnostic, color: bool) {
    if diagnostic.line == 0 {
        return;
    }
    let Some(ref file_path) = diagnostic.file else { return };
    let Ok(source) = std::fs::read_to_string(file_path) else { return };
    let lines: Vec<&str> = source.lines().collect();
    let idx = diagnostic.line.saturating_sub(1);
    if idx >= lines.len() {
        return;
    }

    let line_text = lines[idx];
    let line_num = diagnostic.line;
    let gutter_width = format!("{}", line_num + 2).len();

    if color {
        eprintln!();
        eprintln!("{CYAN}{:>width$}{RESET} {CYAN}|{RESET}", line_num, width = gutter_width);
        eprintln!(
            "{CYAN}{:>width$}{RESET} {CYAN}|{RESET} {}",
            line_num, line_text, width = gutter_width
        );
        let col = diagnostic.col.saturating_sub(1);
        let indent = " ".repeat(col);
        let sev_color = diagnostic.severity.color();
        eprintln!(
            "{CYAN}{:>width$}{RESET} {CYAN}|{RESET} {indent}{sev_color}{BOLD}^{RESET}",
            "", width = gutter_width, indent = indent, sev_color = sev_color
        );
    } else {
        eprintln!();
        eprintln!("{:>width$} | {}", line_num, line_text, width = gutter_width);
        let col = diagnostic.col.saturating_sub(1);
        let indent = " ".repeat(col);
        eprintln!("{:>width$} | {indent}^", "", width = gutter_width, indent = indent);
    }
}
