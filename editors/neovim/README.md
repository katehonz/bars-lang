# Bars for Neovim / Vim

## Install

```bash
# runtimepath entry
mkdir -p ~/.config/nvim
# or packpath:
mkdir -p ~/.local/share/nvim/site/pack/bars/start/bars
cp -r ftdetect syntax ~/.local/share/nvim/site/pack/bars/start/bars/
```

Or add this repo's `editors/neovim` to `runtimepath`:

```vim
set runtimepath+=/path/to/bars/editors/neovim
```

`.brs` files get `filetype=bars` and basic syntax highlighting.
