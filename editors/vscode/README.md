# Bars for VS Code

Syntax highlighting and language configuration for `.brs` files.

## Install (development)

```bash
# From this directory
code --install-extension .
# or symlink into ~/.vscode/extensions/bars-lang
ln -s "$(pwd)" ~/.vscode/extensions/bars-lang-0.1.0
```

Then reload the window and open any `.brs` file.

## Features

- Line comments: `;;`
- Keywords: `defn`, `let`, `if`, `match`, `require`, …
- Strings, numbers, booleans, keywords (`:as`)

For diagnostics and go-to-definition, run the host LSP: `bars lsp`.
