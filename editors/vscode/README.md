# Bars for VS Code

Syntax highlighting, language configuration, and **LSP** integration for `.brs` files.

| Feature | Source |
|---------|--------|
| Syntax / brackets / comments | TextMate grammar + language-configuration |
| Diagnostics (parse, types) | `bars lsp` (host binary) |
| Hover (inferred types) | `bars lsp` |
| Completion (keywords + top-level defs) | `bars lsp` |
| Go to Definition | `bars lsp` |

## Prerequisites

1. **Host Bars binary** with the LSP subcommand:

   ```bash
   # from the Bars repo root
   make host
   # → target/release/bars
   ./target/release/bars lsp   # stdio server (started by the extension)
   ```

2. **Node dependencies** (once, in this directory):

   ```bash
   cd editors/vscode
   npm install
   ```

## Install (development)

```bash
cd editors/vscode
npm install

# Option A — install as a local extension
code --install-extension .

# Option B — symlink (reload VS Code after)
mkdir -p ~/.vscode/extensions
ln -sfn "$(pwd)" ~/.vscode/extensions/bars-lang-0.2.0
```

Then **Developer: Reload Window** and open any `.brs` file.

If `bars` is not on `PATH`, set:

```json
// settings.json
{
  "bars.lsp.path": "/absolute/path/to/bars/target/release/bars",
  "bars.lsp.enabled": true
}
```

## Settings

| Setting | Default | Meaning |
|---------|---------|---------|
| `bars.lsp.enabled` | `true` | Start the language server |
| `bars.lsp.path` | `"bars"` | Path to the host `bars` executable |
| `bars.lsp.trace` | `"off"` | `off` / `messages` / `verbose` LSP traffic log |

Command palette: **Bars: Restart Language Server**.

## Output

View → Output → **Bars Language Server** for startup errors (binary not found, etc.).

## Notes

- The LSP is the **Rust host** (`bootstrap/`), not `bars-self`. Self-host remains the production compiler; host provides IDE services.
- Diagnostics cover parse + type errors. Ownership is available via `./bars-self check` / `bars check`.
- Syntax-only still works if the LSP fails to start.
