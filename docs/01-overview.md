# Overview

Bars is a systems programming language that combines:

- **Clojure syntax** — S-expressions, homoiconicity, Lisp ergonomics
- **Rust-like ownership** — borrow checking without lifetime annotations
- **Native compilation** — QBE for AOT, Cranelift for JIT/REPL

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

### Hybrid Memory Management

| Type | Management | Example |
|------|-----------|---------|
| Stack | Automatic | `(let [x 42] ...)` |
| Ownership | Manual + checked | `(def f (file/open "x.txt"))` |
| GC | Automatic (Boehm) | `(def v [1 2 3])` |

The C runtime uses Boehm GC for vectors, maps, and strings.

## Compilation Pipeline

```
.brs source
    ↓
Reader (lexer + parser)
    ↓
AST
    ↓
Macro expansion
    ↓
Ownership analysis
    ↓
HIR lowering
    ↓
Backend
    ├── QBE HIR → QBE IR → qbe assembler → cc → native binary
    └── Cranelift HIR → JIT in-memory execution
    ↓
Runtime (C + Boehm GC)
```

## File Extension

Bars source files use `.brs`.
