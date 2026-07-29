# Editors

## VS Code (recommended)

In-repo extension: [`editors/vscode/`](../editors/vscode/).

| Piece | What it does |
|-------|----------------|
| TextMate grammar | Syntax for `.brs` |
| Language config | Comments, brackets, auto-close |
| **LSP client** | Spawns `bars lsp` (host binary) |

### Setup

```bash
# 1. Host compiler (provides `bars lsp`)
make host

# 2. Extension deps + install
cd editors/vscode
npm install
code --install-extension .
# or symlink:
# ln -sfn "$(pwd)" ~/.vscode/extensions/bars-lang-0.2.0
```

Reload the window, open a `.brs` file.

### Settings

| Key | Default | Notes |
|-----|---------|--------|
| `bars.lsp.enabled` | `true` | Turn the language server on/off |
| `bars.lsp.path` | `"bars"` | Absolute path to `target/release/bars` if needed |
| `bars.lsp.trace` | `"off"` | `messages` / `verbose` for debugging |

Command: **Bars: Restart Language Server**.

Output channel: **Bars Language Server**.

### Features (LSP)

- Diagnostics: parse + type errors while typing  
- Hover: type of top-level names  
- Completion: specials/macros + file-level defs  
- Go to Definition: top-level `defn` / `def` / …  

Ownership and full compile checks remain:

```bash
./bars-self check path/to/file.brs
```

## Neovim

Syntax + ftdetect under [`editors/neovim/`](../editors/neovim/).  
Wire LSP yourself, e.g. with `nvim-lspconfig`:

```lua
vim.lsp.config("bars", {
  cmd = { "bars", "lsp" },  -- or full path to target/release/bars
  filetypes = { "bars" },
  root_markers = { ".git", "Bars.toml" },
})
vim.lsp.enable("bars")
```

(Exact API depends on your Neovim / lspconfig version.)

## Generic LSP client

```text
command:  <path-to>/target/release/bars
args:     ["lsp"]
language: bars
files:    *.brs
transport: stdio
```
