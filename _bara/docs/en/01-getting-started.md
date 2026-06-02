
[← Back to Index](index.md)

---

# Getting Started

> A Clojure dialect that compiles to Nim → C → native binaries.

## Prerequisites

- **Nim** >= 2.0.0
- **GCC** or **Clang**
- **make**
- **curl** (for AI features, optional)

## Installation

```bash
git clone https://gitlab.com/balvatar/lisp-nim.git
cd lisp-nim
make build
```

## Verify Installation

```bash
make check    # build + 276+ tests + all examples
```

## CLI Commands

| Command | Description |
|---------|-------------|
| `./cljnim compile <file.clj>` | Compile to Nim source |
| `./cljnim compile-lib <file.clj>` | Compile to Nim with exported functions (`*`) |
| `./cljnim run <file.clj>` | Compile and run binary |
| `./cljnim read <file.clj>` | Parse and print AST |
| `./cljnim repl` | Start human REPL |
| `./cljnim repl --json` | Start JSON REPL (for AI agents) |
| `./cljnim deps` | Resolve dependencies from `deps.edn` |
| `./cljnim -e '<code>'` | Evaluate expression |
| `./cljnim ai '<description>'` | Generate Clojure code with AI |

## Quick Examples

### Hello World
```clojure
;; examples/hello.clj
(println "Hello, Nim world!")
(println (+ 1 2 3))
```

```bash
$ ./cljnim run examples/hello.clj
Hello, Nim world!
6
```

### Functions & Recursion
```clojure
(defn square [x] (* x x))
(defn factorial [n]
  (if (= n 0)
    1
    (* n (factorial (- n 1)))))

(let [a 5]
  (println (square a))
  (println (factorial a)))
```

### loop/recur
```clojure
(defn sum [n]
  (loop [acc 0 i 1]
    (if (> i n)
      acc
      (recur (+ acc i) (inc i)))))
(println (sum 10))  ;; => 55
```

### Atoms (REPL)
```clojure
user> (def a (atom 0))
user> (swap! a inc)
1
user> (reset! a 42)
42
user> (deref a)
42
```

## AI Setup (Optional)

```bash
export DEEPSEEK_API_KEY="sk-..."
# or OPENAI_API_KEY, or MIMO_API_KEY
```

See [03-ai-integration.md](03-ai-integration.md) for full AI documentation.

## Project Structure

```
├── src/              # Compiler source
│   ├── cljnim.nim    # CLI entry point
│   ├── reader.nim    # EDN parser
│   ├── emitter.nim   # Clojure AST → Nim
│   ├── eval.nim      # Tree-walking interpreter (REPL fast path)
│   └── ai_assist.nim # AI API integration
├── lib/              # Runtime libraries
│   ├── cljnim_runtime.nim      # Native runtime
│   └── cljnim_runtime_js.nim   # JS runtime
├── tests/            # Test suites (8 files, 276+ tests)
├── examples/         # Example .clj files
├── benchmarks/       # Performance benchmarks
├── docs/             # Documentation
└── experiments/      # Web, WASM, native-lib targets
```

## Next Steps

- [02-architecture.md](02-architecture.md) — How the compiler works
- [03-ai-integration.md](03-ai-integration.md) — AI-powered development
- [04-api-reference.md](04-api-reference.md) — JSON REPL protocol
- [05-user-guide.md](05-user-guide.md) — Macros, interop, advanced patterns
