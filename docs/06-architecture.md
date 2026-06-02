# Architecture

## High-Level Flow

```
.brs source file
    ↓
Reader (lexer + recursive descent parser)
    ↓
AST (Expr enum)
    ↓
Macro Expansion (built-in macros + defmacro)
    ↓
Ownership Analysis
    ↓
HIR Lowering — AST → flattened HIR (alloc, store, load, call, branch, jump)
    ↓
Backend Code Generation
    ├── QBE HIR Backend → QBE IR → qbe assembler → cc → native binary
    └── Cranelift HIR Backend → JIT in-memory machine code
    ↓
C Runtime (Boehm GC)
```

## Components

### Reader (`src/reader/`)

- **Lexer** (`lexer.rs`) — Tokenizes source into `Token` enum (symbols, numbers, strings, keywords, brackets, `^` for borrows).
- **Parser** (`parser.rs`) — Recursive descent parser producing `Expr`. Handles special forms (`let`, `if`, `defn`, `def`, `do`, `loop`, `recur`, `quote`) and data structures (vectors `[]`, maps `{}`).

### AST (`src/ast/mod.rs`)

Core types:
- `Expr::Number(i64)`, `String(String)`, `Bool(bool)`, `Symbol(Symbol)`, `Keyword(Keyword)`, `Nil`
- `Expr::Let { bindings, body, span }`
- `Expr::If { cond, then_branch, else_branch, span }`
- `Expr::Defn { name, params, body, ret_type, span }`
- `Expr::Loop { bindings, body, span }`
- `Expr::Recur { args, span }`
- `Expr::FnCall { func, args, span }`
- `Expr::Borrow { expr, is_mut, span }`

### Macro Expansion (`src/macro/expander.rs`)

Built-in macros:
- `when` → `(if cond (do body...) nil)`
- `unless` → `(if (not cond) (do body...) nil)`
- `cond` → nested `if`
- `->` (thread-first) — insert first arg as first argument
- `->>` (thread-last) — insert first arg as last argument

User-defined macros via `defmacro` + `syntax-quote`/`~`/`~@`

### Ownership Checker (`src/ownership/checker.rs`)

Tracks ownership states per scope:
- `Owned` — value owns its memory
- `Borrowed { count }` — shared immutable borrow
- `MutBorrowed` — exclusive mutable borrow
- `Moved` — value has been transferred

Errors:
- `UseAfterMove`
- `AlreadyBorrowed`
- `AlreadyMutBorrowed`
- `MoveWhileBorrowed`

### Backends

#### HIR (`src/hir/`)

Flattened intermediate representation where all control flow and memory operations are explicit:
- `Instr::Alloc`, `Store`, `Load`, `FieldLoad`, `FieldStore`
- `Instr::BinOp`, `UnOp`, `Call`, `StringLit`
- `Terminator::Branch`, `Jump`, `Return`

High-level constructs (`if`, `match`, `loop`/`recur`, `let`) are desugared to ~10 primitive instructions.

#### QBE HIR Backend (`src/backends/qbe_hir/mod.rs`)

- Consumes HIR and generates QBE SSA IR via the `qbe` crate.
- Compiles `defn` to `export function` definitions.
- Top-level expressions are wrapped in `$main()`.
- Built-in operators (`+`, `-`, `*`, `/`, `%`, comparisons) emit direct QBE instructions.
- `println` dispatches to `printf` (integers) or `bars_print_string` (strings).
- `if`/`match` use stack slots (`alloc8` + `store`/`load`) instead of phi nodes.
- `loop`/`recur` use `jmp` to loop labels with explicit variable updates.
- Name sanitization handles special characters (`?`, `!`, `-`, `+`, etc.) for QBE compatibility.

#### Cranelift HIR Backend (`src/backends/cranelift/mod.rs`)

- Consumes HIR and uses `cranelift-jit` for in-memory compilation.
- `defn` functions are declared and defined in the JIT module, persisting across REPL iterations.
- HIR variables map to Cranelift `Variable`s with `def_var`/`use_var`, enabling automatic phi insertion.
- Blocks are sealed only after all jumps are emitted, so backward edges (loops) resolve correctly.

### C Runtime (`runtime/bars_runtime.c`)

- Boehm GC (`libgc`) for managed allocations.
- String type (`bars_string_t`) with GC allocation.
- Vector operations (`bars_vector_new_i64`, `push`, `get`, `count`).
- Map operations (`bars_map_new_i64`, `set`, `get`, `count`).
- Print helpers (`bars_print_i64`, `bars_print_string`, `bars_print_newline`).

The runtime is compiled to a static library (`libbars_runtime.a`) by `build.rs` and linked with every binary.

### Load System (`src/lib.rs`)

`resolve_loads` recursively processes `(load "path")` forms:
- Resolves paths relative to the current file's directory.
- Walks up the directory tree if not found locally.
- Prevents duplicate loads via a `HashSet` of canonical paths.

## Testing

- Unit tests: `cargo test`
- Integration tests in `tests/`: reader, compiler, integration, ownership, macros, stdlib, loop
