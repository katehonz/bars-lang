# Overview

Bars is a systems programming language that combines:

- **Clojure syntax** — S-expressions, homoiconicity, Lisp ergonomics
- **Rust-like ownership** — borrow checking without lifetime annotations
- **Native compilation** — self-hosted **LLVM IR** (+ optional C / WASM backends)

## Design Philosophy

```
Clojure syntax + Rust memory safety + C speed = Bars
```

### Parentheses Show Scope

In Bars, every pair of parentheses is a scope boundary. This maps naturally to:

- Stack frames for function calls
- Lifetime regions for borrow checking
- Lexical blocks for variable visibility

### Lightweight Ownership

Unlike Rust, Bars does not require explicit lifetime annotations. The ownership checker tracks:

- `Owned` — the value owns its memory
- `Borrowed` — immutable borrow (shared read access)
- `MutBorrowed` — exclusive mutable borrow
- `Moved` — value has been transferred
- `Copy` — trivially copyable (numbers, bools, …)

### Hybrid Memory Management

| Type | Management | Example |
|------|-----------|---------|
| Stack | Automatic | `(let [x 42] …)` |
| Ownership | Checked moves/borrows | function args, locals |
| GC | Automatic (Boehm) | vectors, maps, strings |

The C runtime uses Boehm GC for heap collections.

## Two compilers

| | Host (`target/release/bars`) | Self-host (`./bars-self`) |
|--|------------------------------|---------------------------|
| Language | Rust (`bootstrap/`) | Bars (`compiler/`) |
| Role | Bootstrap, REPL, **LSP** | Day-to-day codegen |
| Backends | Cranelift, QBE, optional LLVM | LLVM IR (default), C, WASM |

After Stage 10 bootstrap, **new language work goes in `compiler/*.brs`**.

## Compilation Pipeline (self-host)

```
.brs source
    ↓
Reader (lexer + parser)
    ↓
Modules (require / Bars.toml deps)
    ↓
Macro expansion (built-ins + user defmacro)
    ↓
Type inference (soft by default)
    ↓
Ownership (light NLL)
    ↓
HIR lowering (HOF desugar, TCO, closures, …)
    ↓
Backend
    ├── LLVM IR text → clang → native binary   (default)
    ├── C source → cc                          (BARS_BACKEND_C=1)
    └── WAT / WASM                             (BARS_BACKEND_WASM=1)
    ↓
Runtime (C + Boehm GC; optional OpenSSL TLS object)
```

## File Extension

Bars source files use `.brs`.

## Further reading

- [Language guide](03-language-guide.md)
- [Standard library](04-stdlib.md)
- [CLI reference](05-cli-reference.md)
- [Installation](02-installation.md)
- [ROADMAP](../ROADMAP.md) / [PLAN](../PLAN.md)
