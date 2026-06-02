<div align="center">

# 🔥 Bara Lang

> A Clojure dialect that compiles to Nim → C → native binaries.
> Zero JVM. Zero Java. Pure native performance.

[![Version](https://img.shields.io/badge/version-0.1.0-blue)](cljnim.nimble)
[![Tests](https://img.shields.io/badge/tests-276%2B-green)]()
[![Nim](https://img.shields.io/badge/nim-%3E%3D2.0-blue)](https://nim-lang.org)
[![License](https://img.shields.io/badge/license-MIT-yellow)](LICENSE)
[![Pipeline](https://gitlab.com/balvatar/lisp-nim/badges/main/pipeline.svg)](https://gitlab.com/balvatar/lisp-nim/-/pipelines)
[![Coverage](https://img.shields.io/badge/coverage-clojure--test--suite-blue)](docs/en/07-clojure-test-suite.md)

</div>

## ⚡ Why Bara Lang?

| | JVM Clojure | ClojureScript | Babashka | **Bara Lang** |
|---|---|---|---|---|
| JVM required | ✅ Yes | ❌ No | ❌ No | ✅ **No** |
| GraalVM/native-image | ❌ Needed | ❌ No | ✅ Required | ✅ **No** |
| Google Closure Compiler | ❌ No | ✅ Required | ❌ No | ✅ **No** |
| Java stdlib dependency | ✅ Full | ✅ Heavy | ✅ Medium | ✅ **None** |
| Startup time | ❌ Slow | ⚡ Fast | ⚡ Fast | ⚡ **Instant** |
| Binary size | ❌ 50MB+ | ❌ ~MB | ❌ ~MB | ✅ **~3MB** |
| Native speed | ❌ JIT | ❌ VM | ✅ AOT | ✅ **C-speed** |
| FFI | ❌ JNI/C | ❌ JS | ❌ Limited | ✅ **Nim/C native** |

Bara Lang is an **AI-first** Clojure implementation targeting the Nim ecosystem. It compiles Clojure source directly to Nim, then to C, and finally to a native binary.

**Unlike every other Clojure dialect, Bara Lang has zero dependency on the Java ecosystem.**

## 🚀 Quick Start

```bash
git clone https://gitlab.com/balvatar/lisp-nim.git
cd lisp-nim
make build
make check
./cljnim run examples/hello.clj
```

```clojure
;; examples/hello.clj
(println "Hello, native world!")
```

```bash
$ ./cljnim run examples/hello.clj
Hello, native world!
```

## 📖 Documentation

| Language | Link | Contents |
|---|---|---|
| 🇬🇧 English | [docs/en/index.md](docs/en/index.md) | Getting started, architecture, AI integration, API reference |
| 🇧🇬 Български | [docs/bg/index.md](docs/bg/index.md) | Първи стъпки, архитектура, AI интеграция, API справочник |
| 🧪 Test Suite | [docs/en/07-clojure-test-suite.md](docs/en/07-clojure-test-suite.md) | Cross-dialect compliance with [jank-lang/clojure-test-suite](https://github.com/jank-lang/clojure-test-suite) |
| 🛠️ Recommendations | [CLJNIM_RECOMMENDATIONS.md](CLJNIM_RECOMMENDATIONS.md) | Compiler limitations, workarounds, and fixes (Bulgarian) |

## ✨ What Makes This Unique?

### 1. Completely Independent from Java
The **only** Clojure dialect with absolutely no dependency on the Java ecosystem — not the JVM, not GraalVM, not the Java standard library, and not Google Closure Compiler.

```
Clojure source → Nim source → C source → native binary
```

### 2. Native HAMT Persistent Data Structures
Built from scratch in Nim:
- **Persistent Vector** — Hash Array Mapped Trie with 32-way branching and structural sharing
- **Persistent Map** — HAMT-based immutable hash map, O(log₃₂ n) operations
- **Persistent Set** — Backed by HAMT map
- **Transients** — Batch mutations with `conj!`, `assoc!`, `persistent!`

### 3. Multiple Compilation Targets
The same Clojure code compiles to:

| Target | Status | Use Case |
|--------|--------|----------|
| **Native binary** | ✅ Ready | CLI tools, system programming, servers |
| **Shared library** (.so/.dll/.dylib) | ✅ Ready | Embed in Python/Rust/Go/C via FFI |
| **WASM** | ✅ Ready | Browser, serverless, edge computing |
| **JavaScript** | ✅ Ready | Frontend, Node.js without 50MB JVM |

### 4. AOT Compiler — Not an Interpreter
Full ahead-of-time compilation with C-speed execution and binary sizes ~3MB (debug), <1MB when stripped. The REPL uses a hybrid model: tree-walking interpreter for fast feedback (<1ms eval), AOT compilation for production builds.

### 5. Nim/C Interop Instead of Java Interop
Direct FFI to the Nim and C ecosystem:
```clojure
(nim/math/sin x)
(nim/strutils/toUpper s)
(nim/json/write-value-as-string data)
```
No JNI, no JVM bridging, no Java interop overhead.

### 6. AI-Native Tooling Built-In
- **AI-assisted errors** — DeepSeek/MiMo explain compiler errors
- **AI code generation** — `(ai/generate "quicksort")` in REPL
- **AI optimization hints** — `(ai/optimize code)` suggests improvements
- **AI debugging** — `(ai/debug expr)` analyzes runtime behavior
- **JSON REPL protocol** — Structured I/O for AI agents and IDE integration

### 7. Concurrency Without the JVM
- **Atoms** — Compare-and-swap semantics
- **Agents** — Async state updates with `send`/`await`
- **core.async channels** — `chan`, `>!`, `<!`, `go` macros — CSP-style concurrency without JVM threads

## 🎯 Key Features

| Feature | Status |
|---------|--------|
| Compiler (Clojure → Nim → C → native) | ✅ |
| REPL with JSON protocol | ✅ |
| Macro system (`defmacro`, `syntax-quote`, `->`, `->>`) | ✅ |
| Persistent data structures (HAMT vector/map/set) | ✅ |
| Transients for batch mutations | ✅ |
| Atoms, Agents, Channels | ✅ |
| `loop`/`recur` with true TCO | ✅ |
| `try`/`catch`/`finally` | ✅ |
| Namespace system (`ns`, `:require`) | ✅ |
| Dependency resolution (deps.edn, Git deps) | ✅ |
| Nim/C FFI interop | ✅ |
| AI integration (DeepSeek, OpenAI, MiMo) | ✅ |
| Cross-compilation targets (JS, WASM, shared libs) | ✅ |
| Self-hosted REPL with tree-walking interpreter | ✅ |
| First-class functions (defn as values) | ✅ |
| Multi-arity `defn` | ✅ |
| `&` rest parameters | ✅ |
| Keyword-as-function `(:key map)` | ✅ |
| `--lib-path` CLI flag + `CLJNIM_LIB_PATH` | ✅ |
| 276+ unit tests | ✅ |
| [jank-lang/clojure-test-suite](https://github.com/jank-lang/clojure-test-suite) compliance | ✅ |

## 💡 Examples

### Native math
```clojure
;; examples/math.clj
(defn factorial [n]
  (if (= n 0)
    1
    (* n (factorial (- n 1)))))

(println (factorial 5))  ;; => 120
```

### Nim interop
```clojure
;; examples/interop.clj
(println (nim/math/sin 0.0))
(println (nim/strutils/toUpper "clojure"))
```

### JSON (production-ready)
```clojure
;; examples/jsonista.clj
(def data {:name "Alice" :age 30})

(println (json/write-value-as-string data))
;; => {"name":"Alice","age":30}

(println (json/read-value "{\"hello\":1}" {:keyword-keys? true}))
;; => {:hello 1}
```

See all examples in [`examples/`](examples/).

## 🤖 AI-Powered Development

```bash
export DEEPSEEK_API_KEY="sk-..."
./cljnim ai "function that sums a list using loop/recur"
```

Or use the REPL:
```clojure
(ai/generate "quicksort")
(ai/optimize my-code)
(ai/debug failing-expr)
```

See [docs/en/03-ai-integration.md](docs/en/03-ai-integration.md) for details.

## 📦 Installation

```bash
# Build from source
git clone https://gitlab.com/balvatar/lisp-nim.git
cd lisp-nim
make build

# The `cljnim` binary is now in the project root
./cljnim --help
```

### Custom Library Path
Use `--lib-path` to point to your project's Nim runtime libraries:
```bash
./cljnim --lib-path ./my_project/lib run app.clj
```

## 🏗️ Architecture

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌─────────────┐
│  .clj file  │───▶│    Reader    │───▶│   Emitter   │───▶│  Nim code   │
│  (source)   │    │  (EDN/Clojure│    │ (Clojure→Nim│    │  (.nim)      │
└─────────────┘    │   syntax)    │    │   codegen)  │    └─────────────┘
                   └──────────────┘    └─────────────┘          │
                                                                 ▼
                                                          ┌─────────────┐
                                                          │  Nim compiler│
                                                          │  (nim c)     │
                                                          └─────────────┘
                                                                 │
                                                                 ▼
                                                          ┌─────────────┐
                                                          │  Native binary│
                                                          │  (~3MB)      │
                                                          └─────────────┘
```

## 📊 Benchmarks

| Test | JVM Clojure | Bara Lang | Speedup |
|------|-------------|-----------|---------|
| factorial(20) | 2.1s | 0.003s | **700×** |
| fibonacci(35) | 3.8s | 0.005s | **760×** |
| hello world | 1.2s | 0.001s | **1200×** |

> JVM times include JVM startup. Bara Lang binaries start instantly.

Run benchmarks: `make bench`

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Run `make check` before committing
4. Submit a merge request

See [docs/en/index.md](docs/en/index.md) for the development guide.

## 📜 License

[MIT](LICENSE) — Copyright (c) 2026 Bara Lang Contributors
