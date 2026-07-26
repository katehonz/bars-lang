# Rust bootstrap — frozen (Nim `csources` role)

This tree is the **host compiler** used only to bring up the self-hosted
Bars compiler (`compiler/*.brs`).

After Stage 10 bootstrap:

| Role | Path |
|------|------|
| **Language development** | `compiler/*.brs` (reader, HIR, macros, LLVM, build) |
| **Bootstrap only** | `bootstrap/` (this directory) |
| **Runtime** | `runtime/bars_runtime.c` |

## When to touch this code

- Bring-up on a new platform before a Bars binary exists
- Critical host bug that blocks compiling `compiler/build.brs`
- **Not** for new language features — implement those in Bars under `compiler/`

## Rebuild Gen1

```bash
make host          # cargo build --release
make runtime       # runtime/bars_runtime.o
make bars-self     # host → ./bars-self
make self-test     # example suite
make identity      # Gen3.ll == Gen4.ll
```

See root `PLAN.md` Stage 10 / 12.25 and `Makefile` help.
