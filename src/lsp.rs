use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use tower_lsp::jsonrpc::Result;
use tower_lsp::lsp_types::*;
use tower_lsp::{Client, LanguageServer, LspService, Server};

use crate::ast::{Expr, Program, Span, Symbol};
use crate::reader;
use crate::types::TypeScheme;

/// A single open document in the LSP session.
#[derive(Debug, Clone)]
struct Document {
    text: String,
    #[allow(dead_code)]
    version: i32, #[allow(dead_code)]
    /// Cached AST (None if parsing failed)
    ast: Option<Program>,
    /// Cached top-level type inference results
    types: Vec<(String, TypeScheme)>,
}

/// LSP backend state.
#[derive(Debug)]
pub struct Backend {
    client: Client,
    documents: Arc<Mutex<HashMap<Url, Document>>>,
}

impl Backend {
    pub fn new(client: Client) -> Self {
        Self {
            client,
            documents: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Parse a document and cache its AST + inferred types.
    fn refresh_document(&self, uri: &Url, text: &str) {
        let mut docs = self.documents.lock().unwrap();
        let ast = reader::read(text).ok();
        let types = ast
            .as_ref()
            .and_then(|prog| crate::infer_types(prog).ok())
            .unwrap_or_default();
        docs.insert(
            uri.clone(),
            Document {
                text: text.to_string(),
                version: 0,
                ast,
                types,
            },
        );
    }

    /// Publish diagnostics for a document.
    async fn publish_diagnostics(&self, uri: Url) {
        let diagnostics = {
            let docs = self.documents.lock().unwrap();
            let Some(doc) = docs.get(&uri) else {
                return;
            };
            let mut diags = Vec::new();

            // Parse errors
            if doc.ast.is_none() {
                if let Err(e) = reader::read(&doc.text) {
                    diags.push(Diagnostic {
                        range: Range {
                            start: Position {
                                line: 0,
                                character: 0,
                            },
                            end: Position {
                                line: 0,
                                character: 0,
                            },
                        },
                        severity: Some(DiagnosticSeverity::ERROR),
                        code: None,
                        code_description: None,
                        source: Some("bars".to_string()),
                        message: format!("Parse error: {}", e),
                        related_information: None,
                        tags: None,
                        data: None,
                    });
                }
            }

            // Type errors
            if let Some(ref ast) = doc.ast {
                if let Err(e) = crate::type_check(ast) {
                    let (line, col) = e.location();
                    let line = line.saturating_sub(1) as u32;
                    let col = col.saturating_sub(1) as u32;
                    diags.push(Diagnostic {
                        range: Range {
                            start: Position { line, character: col },
                            end: Position {
                                line,
                                character: col + 1,
                            },
                        },
                        severity: Some(DiagnosticSeverity::ERROR),
                        code: None,
                        code_description: None,
                        source: Some("bars".to_string()),
                        message: e.short_message(),
                        related_information: None,
                        tags: None,
                        data: None,
                    });
                }
            }

            diags
        };

        self.client
            .publish_diagnostics(uri, diagnostics, None)
            .await;
    }
}

#[tower_lsp::async_trait]
impl LanguageServer for Backend {
    async fn initialize(&self, _: InitializeParams) -> Result<InitializeResult> {
        Ok(InitializeResult {
            server_info: Some(ServerInfo {
                name: "bars-lsp".to_string(),
                version: Some(env!("CARGO_PKG_VERSION").to_string()),
            }),
            capabilities: ServerCapabilities {
                text_document_sync: Some(TextDocumentSyncCapability::Options(
                    TextDocumentSyncOptions {
                        open_close: Some(true),
                        change: Some(TextDocumentSyncKind::FULL),
                        will_save: None,
                        will_save_wait_until: None,
                        save: Some(TextDocumentSyncSaveOptions::SaveOptions(SaveOptions {
                            include_text: Some(false),
                        })),
                    },
                )),
                hover_provider: Some(HoverProviderCapability::Simple(true)),
                completion_provider: Some(CompletionOptions {
                    resolve_provider: Some(false),
                    trigger_characters: None,
                    all_commit_characters: None,
                    work_done_progress_options: Default::default(),
                    completion_item: None,
                }),
                definition_provider: Some(OneOf::Left(true)),
                diagnostic_provider: Some(DiagnosticServerCapabilities::Options(
                    DiagnosticOptions {
                        identifier: Some("bars".to_string()),
                        inter_file_dependencies: false,
                        workspace_diagnostics: false,
                        work_done_progress_options: Default::default(),
                    },
                )),
                ..Default::default()
            },
            ..Default::default()
        })
    }

    async fn initialized(&self, _: InitializedParams) {
        self.client
            .log_message(MessageType::INFO, "Bars language server initialized.")
            .await;
    }

    async fn shutdown(&self) -> Result<()> {
        Ok(())
    }

    // ── Document sync ──────────────────────────────────────────────────────────

    async fn did_open(&self, params: DidOpenTextDocumentParams) {
        let uri = params.text_document.uri;
        let text = params.text_document.text;
        self.refresh_document(&uri, &text);
        self.publish_diagnostics(uri).await;
    }

    async fn did_change(&self, params: DidChangeTextDocumentParams) {
        let uri = params.text_document.uri;
        // With FULL sync, the last change contains the entire document.
        if let Some(change) = params.content_changes.last() {
            self.refresh_document(&uri, &change.text);
            self.publish_diagnostics(uri).await;
        }
    }

    async fn did_close(&self, params: DidCloseTextDocumentParams) {
        let mut docs = self.documents.lock().unwrap();
        docs.remove(&params.text_document.uri);
    }

    async fn did_save(&self, params: DidSaveTextDocumentParams) {
        self.publish_diagnostics(params.text_document.uri).await;
    }

    // ── Hover ──────────────────────────────────────────────────────────────────

    async fn hover(&self, params: HoverParams) -> Result<Option<Hover>> {
        let uri = params.text_document_position_params.text_document.uri;
        let pos = params.text_document_position_params.position;

        let docs = self.documents.lock().unwrap();
        let Some(doc) = docs.get(&uri) else {
            return Ok(None);
        };
        let Some(ref ast) = doc.ast else {
            return Ok(None);
        };

        let line = (pos.line as usize) + 1;
        let col = (pos.character as usize) + 1;

        // Try to find a symbol at this position
        let symbol = find_symbol_at_position(ast, line, col);
        let Some(name) = symbol else {
            return Ok(None);
        };

        // Look up type in cached inference results
        let type_str = doc
            .types
            .iter()
            .find(|(n, _)| n == &name)
            .map(|(_, scheme)| format!("{}", scheme))
            .unwrap_or_else(|| "unknown".to_string());

        let contents = format!("```bars\n{} : {}\n```", name, type_str);
        Ok(Some(Hover {
            contents: HoverContents::Scalar(MarkedString::String(contents)),
            range: None,
        }))
    }

    // ── Completion ─────────────────────────────────────────────────────────────

    async fn completion(&self, params: CompletionParams) -> Result<Option<CompletionResponse>> {
        let uri = params.text_document_position.text_document.uri;

        let docs = self.documents.lock().unwrap();
        let Some(doc) = docs.get(&uri) else {
            return Ok(None);
        };

        let mut items = Vec::new();

        // Add builtins
        let builtins = [
            ("def", "Define a global constant: (def name value)"),
            ("defn", "Define a function: (defn name [params] body)"),
            ("let", "Local bindings: (let [x 1 y 2] body)"),
            ("if", "Conditional: (if cond then else)"),
            ("do", "Sequence expressions: (do expr1 expr2 ...)"),
            ("loop", "Tail-recursive loop: (loop [bindings] body)"),
            ("recur", "Recurse in loop: (recur args...)"),
            ("fn", "Anonymous function: (fn [params] body)"),
            ("match", "Pattern match: (match expr [pattern body] ...)"),
            ("deftype", "Algebraic data type: (deftype Name [Ctor fields...])"),
            ("defstruct", "Struct definition: (defstruct Name fields...)"),
            ("extern", "C FFI declaration"),
            ("load", "Load another Bars file"),
        ];
        for (name, detail) in builtins {
            items.push(CompletionItem {
                label: name.to_string(),
                kind: Some(CompletionItemKind::KEYWORD),
                detail: Some(detail.to_string()),
                ..Default::default()
            });
        }

        // Add top-level definitions from the current file
        if let Some(ref ast) = doc.ast {
            for expr in &ast.exprs {
                if let Some((name, kind)) = completion_item_from_expr(expr) {
                    items.push(CompletionItem {
                        label: name,
                        kind: Some(kind),
                        ..Default::default()
                    });
                }
            }
        }

        Ok(Some(CompletionResponse::Array(items)))
    }

    // ── Go to Definition ───────────────────────────────────────────────────────

    async fn goto_definition(
        &self,
        params: GotoDefinitionParams,
    ) -> Result<Option<GotoDefinitionResponse>> {
        let uri = params.text_document_position_params.text_document.uri;
        let pos = params.text_document_position_params.position;

        let docs = self.documents.lock().unwrap();
        let Some(doc) = docs.get(&uri) else {
            return Ok(None);
        };
        let Some(ref ast) = doc.ast else {
            return Ok(None);
        };

        let line = (pos.line as usize) + 1;
        let col = (pos.character as usize) + 1;

        let symbol = find_symbol_at_position(ast, line, col);
        let Some(name) = symbol else {
            return Ok(None);
        };

        // Find the definition span
        let def_span = find_definition_span(ast, &name);
        let Some(span) = def_span else {
            return Ok(None);
        };

        let range = span_to_range(&span);
        let location = Location {
            uri: uri.clone(),
            range,
        };

        Ok(Some(GotoDefinitionResponse::Scalar(location)))
    }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn span_to_range(span: &Span) -> Range {
    Range {
        start: Position {
            line: (span.line.saturating_sub(1)) as u32,
            character: (span.col.saturating_sub(1)) as u32,
        },
        end: Position {
            line: (span.line.saturating_sub(1)) as u32,
            character: (span.col.saturating_sub(1)) as u32 + 1,
        },
    }
}

/// Recursively search for a Symbol expression that contains the given position.
fn find_symbol_at_position(program: &Program, line: usize, col: usize) -> Option<String> {
    for expr in &program.exprs {
        if let Some(sym) = find_symbol_in_expr(expr, line, col) {
            return Some(sym);
        }
    }
    None
}

fn find_symbol_in_expr(expr: &Expr, line: usize, col: usize) -> Option<String> {
    let span = expr.span();
    // Check if cursor is inside this expression's span
    // Note: Span currently only has start position (line, col).
    // We do a simple exact match or proximity match.
    if span.line == line && span.col <= col {
        // For leaf symbols, check exact match
        if let Expr::Symbol(Symbol(name), _) = expr {
            let end_col = span.col + name.len();
            if col <= end_col {
                return Some(name.clone());
            }
            return None;
        }
    }

    // Recurse into sub-expressions
    match expr {
        Expr::List(exprs, _) | Expr::Vector(exprs, _) => {
            for e in exprs {
                if let Some(sym) = find_symbol_in_expr(e, line, col) {
                    return Some(sym);
                }
            }
        }
        Expr::Let { bindings, body, .. } => {
            for (_, val) in bindings {
                if let Some(sym) = find_symbol_in_expr(val, line, col) {
                    return Some(sym);
                }
            }
            if let Some(sym) = find_symbol_in_expr(body, line, col) {
                return Some(sym);
            }
        }
        Expr::If {
            cond,
            then_branch,
            else_branch,
            ..
        } => {
            for e in [cond.as_ref(), then_branch.as_ref(), else_branch.as_ref()] {
                if let Some(sym) = find_symbol_in_expr(e, line, col) {
                    return Some(sym);
                }
            }
        }
        Expr::Def { value, .. } => {
            if let Some(sym) = find_symbol_in_expr(value, line, col) {
                return Some(sym);
            }
        }
        Expr::Defn { body, .. } | Expr::Lambda { body, .. } | Expr::DefMacro { body, .. } => {
            if let Some(sym) = find_symbol_in_expr(body, line, col) {
                return Some(sym);
            }
        }
        Expr::FnCall { func, args, .. } => {
            if let Some(sym) = find_symbol_in_expr(func, line, col) {
                return Some(sym);
            }
            for a in args {
                if let Some(sym) = find_symbol_in_expr(a, line, col) {
                    return Some(sym);
                }
            }
        }
        Expr::Do { exprs, .. } => {
            for e in exprs {
                if let Some(sym) = find_symbol_in_expr(e, line, col) {
                    return Some(sym);
                }
            }
        }
        Expr::Loop { bindings, body, .. } => {
            for (_, val) in bindings {
                if let Some(sym) = find_symbol_in_expr(val, line, col) {
                    return Some(sym);
                }
            }
            if let Some(sym) = find_symbol_in_expr(body, line, col) {
                return Some(sym);
            }
        }
        Expr::Recur { args, .. } => {
            for a in args {
                if let Some(sym) = find_symbol_in_expr(a, line, col) {
                    return Some(sym);
                }
            }
        }
        Expr::Match { expr, arms, .. } => {
            if let Some(sym) = find_symbol_in_expr(expr, line, col) {
                return Some(sym);
            }
            for (_, body) in arms {
                if let Some(sym) = find_symbol_in_expr(body, line, col) {
                    return Some(sym);
                }
            }
        }
        Expr::FieldAccess { expr: inner, .. } => {
            if let Some(sym) = find_symbol_in_expr(inner, line, col) {
                return Some(sym);
            }
        }
        Expr::Quote(inner, _) | Expr::SyntaxQuote(inner, _) | Expr::Unquote(inner, _) | Expr::Splicing(inner, _) => {
            if let Some(sym) = find_symbol_in_expr(inner, line, col) {
                return Some(sym);
            }
        }
        Expr::Borrow(inner, _, _) => {
            if let Some(sym) = find_symbol_in_expr(inner, line, col) {
                return Some(sym);
            }
        }
        _ => {}
    }
    None
}

/// Find the definition span of a top-level name.
fn find_definition_span(program: &Program, name: &str) -> Option<Span> {
    for expr in &program.exprs {
        match expr {
            Expr::Defn { name: Symbol(n), span, .. } if n == name => return Some(span.clone()),
            Expr::Def { name: Symbol(n), span, .. } if n == name => return Some(span.clone()),
            Expr::DefStruct { name: Symbol(n), span, .. } if n == name => return Some(span.clone()),
            Expr::DefType { name: Symbol(n), span, .. } if n == name => return Some(span.clone()),
            Expr::Extern { bars_name: Symbol(n), span, .. } if n == name => return Some(span.clone()),
            _ => {}
        }
    }
    None
}

/// Extract a completion item from a top-level expression.
fn completion_item_from_expr(expr: &Expr) -> Option<(String, CompletionItemKind)> {
    match expr {
        Expr::Defn { name: Symbol(n), .. } => Some((n.clone(), CompletionItemKind::FUNCTION)),
        Expr::Def { name: Symbol(n), .. } => Some((n.clone(), CompletionItemKind::CONSTANT)),
        Expr::DefStruct { name: Symbol(n), .. } => Some((n.clone(), CompletionItemKind::STRUCT)),
        Expr::DefType { name: Symbol(n), .. } => Some((n.clone(), CompletionItemKind::ENUM)),
        Expr::Extern { bars_name: Symbol(n), .. } => Some((n.clone(), CompletionItemKind::FUNCTION)),
        _ => None,
    }
}

// ── Public entry point ───────────────────────────────────────────────────────

/// Run the Bars language server over stdio.
pub async fn run_stdio() {
    let stdin = tokio::io::stdin();
    let stdout = tokio::io::stdout();

    let (service, socket) = LspService::new(|client| Backend::new(client));
    Server::new(stdin, stdout, socket).serve(service).await;
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_find_symbol_at_position_simple() {
        let source = "(defn add [x y] (+ x y))\n(add 1 2)";
        let program = reader::read(source).unwrap();

        // "add" on line 2, col 2
        let sym = find_symbol_at_position(&program, 2, 2);
        assert_eq!(sym, Some("add".to_string()));

        // "x" inside the function body, line 1, col 20
        let sym = find_symbol_at_position(&program, 1, 20);
        assert_eq!(sym, Some("x".to_string()));
    }

    #[test]
    fn test_find_definition_span() {
        let source = "(defn add [x y] (+ x y))\n(def pi 314)";
        let program = reader::read(source).unwrap();

        let span = find_definition_span(&program, "add");
        assert!(span.is_some());
        assert_eq!(span.unwrap().line, 1);

        let span = find_definition_span(&program, "pi");
        assert!(span.is_some());
        assert_eq!(span.unwrap().line, 2);

        let span = find_definition_span(&program, "nonexistent");
        assert!(span.is_none());
    }

    #[test]
    fn test_completion_item_from_expr() {
        let source = "(defn foo [x] x)\n(def bar 42)\n(defstruct Point [x y])";
        let program = reader::read(source).unwrap();

        let items: Vec<_> = program.exprs.iter().filter_map(completion_item_from_expr).collect();
        assert_eq!(items.len(), 3);
        assert_eq!(items[0], ("foo".to_string(), CompletionItemKind::FUNCTION));
        assert_eq!(items[1], ("bar".to_string(), CompletionItemKind::CONSTANT));
        assert_eq!(items[2], ("Point".to_string(), CompletionItemKind::STRUCT));
    }
}
