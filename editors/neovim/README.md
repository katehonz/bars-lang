# Bars for Neovim / Vim

## Install (syntax)

```bash
# packpath:
mkdir -p ~/.local/share/nvim/site/pack/bars/start/bars
cp -r ftdetect syntax ~/.local/share/nvim/site/pack/bars/start/bars/
```

Or add this directory to `runtimepath`:

```vim
set runtimepath+=/path/to/bars/editors/neovim
```

`.brs` files get `filetype=bars` and basic syntax highlighting.

## LSP

The language server is the **host** binary (`make host` → `target/release/bars`):

```bash
bars lsp
```

Example with Neovim 0.11+ style config (adjust to your plugin manager):

```lua
vim.lsp.config("bars", {
  cmd = { vim.fn.expand("~/z-git/bars/target/release/bars"), "lsp" },
  filetypes = { "bars" },
  root_markers = { ".git", "Bars.toml" },
})
vim.lsp.enable("bars")
```

Or classic `lspconfig`:

```lua
require("lspconfig").bars = {
  default_config = {
    cmd = { "bars", "lsp" },
    filetypes = { "bars" },
    root_dir = require("lspconfig.util").root_pattern(".git", "Bars.toml"),
  },
}
require("lspconfig").bars.setup({})
```

Full editor guide: [`docs/11-editors.md`](../../docs/11-editors.md).
