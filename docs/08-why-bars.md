# Why Bars? A Manifesto for a Systems Lisp

## The Missing Link

Lisp has existed for over 60 years. Systems programming has existed for just as long. Yet no language has successfully combined **genuine Lisp syntax and macros** with **native systems programming** in a practical, production-ready form.

This is the gap Bars is built to fill.

### The Landscape

| Language | Lisp Syntax | Native Code | Memory Safety | Macros | Industrial Usage |
|----------|-------------|-------------|---------------|--------|------------------|
| **Common Lisp** | ✅ | ✅ (via SBCL) | ❌ | ✅ | Niche, declining |
| **Scheme** | ✅ | ❌ (mostly interpreted) | ❌ | ✅ | Academic |
| **Clojure** | ✅ | ❌ (JVM) | ❌ | ✅ | **Industrial standard** |
| **Racket** | ✅ | ❌ (bytecode VM) | ❌ | ✅ | Educational |
| **Carp** | ✅ | ✅ (LLVM) | ✅ | ✅ | **Abandoned** |
| **Rust** | ❌ | ✅ | ✅ | ❌ (procedural only) | Industrial standard |
| **Zig** | ❌ | ✅ | ✅ (manual) | ❌ | Growing |
| **C** | ❌ | ✅ | ❌ | ❌ (text preprocessor) | Industrial standard |
| **Bars** | ✅ | ✅ | ✅ | ✅ | **First serious attempt** |

## Clojure Is the Industrial Standard for Lisp

Clojure proved something profound: **Lisp syntax scales to industrial software engineering.**

- Millions of lines of production code at Fortune 500 companies
- A ecosystem of libraries (Datomic, Pedestal, Ring, core.async)
- A community that understands immutable data, REPL-driven development, and functional composition
- A syntax that developers *choose* to use for money, not just for fun

But Clojure made a deliberate trade-off: it runs on the JVM. This gives it garbage collection, a huge library ecosystem, and cross-platform portability — at the cost of:

- **Startup time** (1-2 seconds for a simple script)
- **Memory footprint** (200MB+ runtime)
- **Systems programming** (no OS kernels, no drivers, no embedded, no WASM without heavy lifting)
- **Zero-cost FFI** (JNI is slow and painful)

## The First Serious Attempt

Bars is the first project to say: *"What if we kept everything that makes Clojure great, but compiled to native code with memory safety?"*

### What We Keep from Clojure

- **S-expression syntax** — code is data, data is code
- **REPL-driven development** — evaluate expressions instantly via Cranelift JIT
- **Homoiconic macros** — `when`, `unless`, `cond`, `->`, `->>` as AST transformations
- **Immutable-by-default philosophy** — functional composition, explicit mutation
- **Vectors `[]` and Maps `{}`** — literal syntax for common data structures
- **Keyword `:foo`** — self-describing identifiers

### What We Add for Systems Programming

- **Native compilation via QBE** — seconds, not minutes, for a full build
- **Ownership checking** — borrow semantics without Rust's lifetime annotation complexity
- **Cranelift JIT REPL** — instant feedback without an interpreter
- **Optional Boehm GC** — use it for complex data, avoid it for hot loops
- **Zero-cost C FFI** — direct ABI calls, no JNI overhead
- **`loop` / `recur`** — tail-recursive iteration that compiles to jumps, not stack frames
- **Small binaries** — no 200MB runtime, just your code + optional GC

## Why Now?

Three things make this possible today that weren't possible 10 years ago:

1. **QBE** — a compiler backend that is tiny, fast, and mature enough for real use. It compiles 100x faster than LLVM while producing good code.

2. **Cranelift** — a code generator designed specifically for JIT compilation. Fast enough for a REPL, correct enough for production.

3. **Boehm GC** — a conservative garbage collector that Just Works with C code. No need to write a new GC from scratch.

The infrastructure is here. What was missing was the language design.

## Why Bars Beats the Alternatives

### vs Clojure
> *"I love Clojure, but I need to write a daemon that starts in 10ms."*

Bars gives you the same REPL, the same macros, the same syntax — but compiles to a 50KB native binary.

### vs Rust
> *"I need memory safety, but I don't have 6 months to fight the borrow checker."*

Bars has ownership checking, but without lifetime annotations. The checker is scope-based and more permissive. You get safety without the learning curve.

### vs Zig/C
> *"I want to write fast code, but I miss macros that can generate code."*

Bars gives you true Lisp macros — AST manipulation, not text substitution. Your macro can introspect the code it generates and produce optimized output.

### vs Carp
> *"Carp was brilliant, but it's dead."*

Carp proved the concept. Bars executes it with modern backends, active development, and a real load system + standard library.

## The Vision

We are not trying to replace Clojure. Clojure is excellent at what it does.

We are not trying to replace Rust. Rust is excellent at what it does.

We are building the language for the programmer who:
- Thinks in S-expressions
- Needs native performance
- Wants memory safety
- Refuses to give up macros
- Hates waiting for LLVM

That programmer has had no home. Until now.

## Call to Action

If you are a Clojure developer who has ever thought *"I wish I could compile this to a binary"* — Bars is for you.

If you are a systems programmer who has ever thought *"I wish I had macros"* — Bars is for you.

If you are a language enthusiast who believes that **parentheses are not a bug, they are a feature** — Bars is for you.

This is the first serious attempt. It won't be the last. But it will be the one that proves it can work.
