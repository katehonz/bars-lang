# Bara Lang Documentation

> A Clojure dialect that compiles to Nim → C → native binaries.
> **The only standalone Clojure implementation completely free from the Java ecosystem.**

## Choose Language / Избор на език

| 🇬🇧 English | 🇧🇬 Български |
|------------|-------------|
| [English Documentation](index.md) | [Българска Документация](../bg/index.md) |

## Quick Links

- **GitHub/GitLab:** [lisp-nim](https://gitlab.com/balvatar/lisp-nim)
- **Build:** `make build && make check`
- **Tests:** 276+ tests across 8 test suites
- **AI Integration:** DeepSeek API, OpenAI-compatible, Xiaomi MiMo
- **Test Suite:** [Clojure Test Suite Compatibility](07-clojure-test-suite.md) — cross-dialect compliance testing

## Documentation

| # | Topic | File |
|---|-------|------|
| 1 | Getting Started | [01-getting-started.md](01-getting-started.md) |
| 2 | Architecture | [02-architecture.md](02-architecture.md) |
| 3 | AI Integration | [03-ai-integration.md](03-ai-integration.md) |
| 4 | API Reference | [04-api-reference.md](04-api-reference.md) |
| 5 | User Guide | [05-user-guide.md](05-user-guide.md) |
| 6 | Roadmap | [06-roadmap.md](06-roadmap.md) |
| 7 | Clojure Test Suite | [07-clojure-test-suite.md](07-clojure-test-suite.md) |

## Why Bara Lang?

Unlike every other Clojure dialect, Bara Lang has **zero dependency on the Java ecosystem** — no JVM, no GraalVM, no Google Closure Compiler, no Java standard library.

| Dialect | Java Ecosystem Dependency |
|---------|---------------------------|
| Clojure (JVM) | Full — runs on JVM |
| ClojureScript | Heavy — Google Closure Compiler |
| Babashka | Medium — GraalVM native-image |
| **Bara Lang** | **None — completely standalone** |

### Unique Advantages

1. **Native HAMT Persistent Data Structures** — Built from scratch in Nim (Persistent Vector, Map, Set with structural sharing)
2. **Multiple Targets** — Native binary, shared library (.so/.dll), WASM, and JavaScript from one codebase
3. **AOT Compiler** — Clojure → Nim → C → native, running at C speed
4. **Nim/C Interop** — Direct FFI without JVM bridging overhead
5. **AI-Native Tooling** — Built-in AI integration for code generation, optimization, and debugging
6. **Concurrency Without JVM** — Atoms, Agents, and core.async channels without Java threads
7. **Tiny Binaries** — Single executables under 1MB with no runtime dependencies
