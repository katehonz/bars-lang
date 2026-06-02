
[← Back to Index](index.md)

---

# Bara Lang Architecture

## Overview

Bara Lang is a **compiler**, not an interpreter. It follows the model of ClojureScript: Clojure source is read, macro-expanded, analyzed, and emitted as Nim source code, which then compiles to C and finally to a native binary.

## Compilation Pipeline

```
┌─────────────┐
│  .clj File  │
└──────┬──────┘
       │
  ┌────▼────┐
  │ Reader  │  ← EDN parser. Produces Clojure data structures.
  └────┬────┘
       │
  ┌────▼────┐
  │ Macros  │  ← defmacro expansion. Operates on Clojure data.
  └────┬────┘
       │
  ┌────▼────┐
  │ Analyzer│  ← Special forms, locals, closure analysis.
  └────┬────┘
       │
  ┌────▼────┐
  │ Emitter │  ← Generates Nim AST / source code.
  └────┬────┘
       │
  ┌────▼────┐
  │ Nim CC  │  ← Nim → C compilation.
  └────┬────┘
       │
  ┌────▼────┐
  │   C CC  │  ← C → machine code (GCC/Clang).
  └────┬────┘
       │
  ┌────▼────┐
  │  Binary │  ← Single native executable.
  └─────────┘
```

## Unique Advantages

### Independence from the Java Ecosystem
Bara Lang is the **only** Clojure dialect with absolutely no dependency on the Java ecosystem:

| Dialect | JVM Required | GraalVM | Google Closure | Java stdlib |
|---------|-------------|---------|----------------|-------------|
| Clojure (JVM) | ✅ | ❌ | ❌ | ✅ |
| ClojureScript | ❌ | ❌ | ✅ | ❌ |
| Babashka | ❌ | ✅ | ❌ | Partial |
| **Bara Lang** | ❌ | ❌ | ❌ | ❌ |

This means:
- **No JVM warmup** — binaries start instantly
- **No GraalVM complexity** — no native-image configuration
- **No Java installation required** — the compiler itself is a single binary
- **True standalone deployment** — one file, zero runtime dependencies

### Native HAMT Implementation
Our persistent data structures are built from scratch in Nim, optimized for Nim's ORC garbage collector:
- **32-way branching** like Clojure's `PersistentVector`, but without Java object overhead
- **Structural sharing** via copy-on-write HAMT nodes
- **O(log₃₂ n)** for `assoc`/`dissoc`/`nth` — same asymptotic complexity as JVM Clojure
- **Nim ref objects** instead of Java interfaces — simpler memory layout, better cache locality

### Multi-Target Compilation
The same Clojure source compiles to four different targets from one codebase:
1. **Native binary** — `nim c` → C → machine code
2. **Shared library** — `nim c --app:lib` → `.so` / `.dll` / `.dylib`
3. **WASM** — `nim c -d:emscripten` → browser-native WebAssembly
4. **JavaScript** — `nim js` → browser/Node.js

No other Clojure implementation offers this breadth of targets without external tools.

## Key Design Decisions

### 1. AOT Compiler
We compile ahead-of-time, like ClojureScript. This gives us:
- Fast runtime execution (C speed)
- Small binary size
- No interpreter overhead

The trade-off is that REPL compilation is slower (each form is compiled individually).

### 2. Clojure Macros on Clojure Data
Macro expansion happens **before** reaching Nim. Nim never sees Clojure macros:

```clojure
(defmacro unless [condition & body]
  `(if (not ~condition)
     (do ~@body)))
```

This macro operates on `CljVal` objects (Clojure lists, symbols), not Nim AST.

### 3. Runtime in Nim
The `lib/cljnim_runtime.nim` module provides:
- `CljVal` — tagged union representing all Clojure values
- `cljAdd`, `cljMul`, etc. — polymorphic arithmetic
- `cljRepr` — string representation

### 4. Nim Interop
Instead of Java interop, we have direct Nim interop:

```clojure
(nim/math/sin x)
(nim/strutils/toUpper s)
```

Nim modules are auto-imported when called via the `nim/module/fn` pattern.

## Module Responsibilities

| Module | Role |
|---|---|
| `src/reader.nim` | Parses `.clj` text into `CljVal` AST |
| `src/emitter.nim` | Transforms `CljVal` AST into Nim source |
| `src/repl.nim` | Human and AI REPL implementation |
| `src/eval.nim` | Tree-walking interpreter for fast in-memory eval |
| `src/deps.nim` | Dependency resolution (deps.edn format) |
| `src/core.nim` | Core runtime functions (AOT compiled) |
| `src/types.nim` | AST node types (used by reader/emitter) |
| `src/macros.nim` | Macro expansion engine |
| `src/runtime.nim` | Additional runtime helpers |
| `lib/cljnim_runtime.nim` | Core runtime library |
| `lib/cljnim_pvec.nim` | Persistent Vector (HAMT implementation) |
| `lib/cljnim_pmap.nim` | Persistent Hash Map (HAMT implementation) |
| `lib/cljnim_async.nim` | core.async channels runtime |

## Memory Model

- Uses Nim's ORC garbage collector
- `CljVal` is a `ref object` (heap-allocated)
- Persistent data structures (Vector, Map, Set) use structural sharing via HAMT
