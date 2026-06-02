# Bara Lang — The Native Clojure Book

> A practical guide to Clojure that compiles to native binaries. No JVM required.

## What You Will Learn

This book teaches **Clojure** through the lens of **Bara Lang** — a real compiler that turns your Clojure code into native machine code via Nim and C.

You do not need Java. You do not need Leiningen. You need Nim, a C compiler, and curiosity.

## Book Structure

| Chapter | Topic | Why It Matters |
|---------|-------|----------------|
| [01 — Fundamentals](en/01-fundamentals.md) | Syntax, data structures, functions, control flow | The foundation. Applies to all Clojure dialects. |
| [02 — Advanced](en/02-advanced.md) | Transducers, specs, parallelism, performance | Write code that scales. |
| [03 — Tooling](en/03-tooling.md) | Project structure, deps, testing, debugging | Ship reliable software. |
| [04 — Recipes](en/04-recipes.md) | Common patterns, state management, APIs | Copy-paste solutions that work. |
| **[05 — Bara Lang](en/05-bara-lang.md)** | **Native compilation, AI integration, JSON REPL, WASM** | **What makes this dialect unique.** |

## Quick Start

```bash
git clone https://gitlab.com/balvatar/lisp-nim.git
cd lisp-nim
make build && make check
./cljnim run examples/hello.clj
```

## Running the Examples

Most examples work in any Clojure REPL. Chapter 5 examples are specific to Bara Lang:

```bash
# Human REPL
./cljnim repl

# JSON REPL (for AI agents)
./cljnim repl --json

# Compile to native binary
./cljnim run myprogram.clj

# Generate code with AI
./cljnim ai "function that reverses a list"
```

## Language Versions

- **[English](en/)**
- **[Български](bg/)**

## Stats

- **8 chapters** (4 core + 4 translated)
- **1 new chapter** on Bara Lang (native compilation, AI, cross-targets)
- **All code tested** against Bara Lang v0.1.0

---

*This book is maintained as part of the Bara Lang project.*
