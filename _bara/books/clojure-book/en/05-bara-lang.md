# Bara Lang: Native Clojure

> The same language you love. Compiled to native binaries. No JVM required.

---

## What is Bara Lang?

**Bara Lang** is a complete Clojure dialect that compiles to native machine code via the Nim compiler. It is not an interpreter — it is a real compiler with a full optimization pipeline:

```
Your .clj file
      ↓
  Reader (EDN parser)
      ↓
  Macro expansion (defmacro, syntax-quote, ->, ->>)
      ↓
  Emitter (Clojure AST → Nim source)
      ↓
  Nim Compiler → C code
      ↓
  C Compiler → Native binary
```

The result is a single executable file, often under **1 MB**, that starts instantly with **no JVM warmup**.

### Why Native?

| JVM Clojure | Bara Lang |
|-------------|-------------|
| Needs Java runtime installed | Self-contained binary |
| ~2-5 second startup time | Instant startup |
| ~100-300 MB memory footprint | ~1-10 MB |
| JIT compilation pauses | Ahead-of-time, predictable |
| Great for long-running servers | Great for CLI tools, embedded, WASM |

This is not a toy. It is a production compiler with **276+ tests**, **persistent data structures (HAMT)**, **core.async channels**, and an **AI-assisted workflow**.

---

## Installation

```bash
git clone https://gitlab.com/balvatar/lisp-nim.git
cd lisp-nim
make build
make check   # run all tests + examples
```

**Requirements:** Nim ≥ 2.0, GCC or Clang, make.

That is it. No Java. No Leiningen. No deps downloads that take ten minutes.

---

## Your First Program

Create `hello.clj`:

```clojure
(println "Hello from native Clojure!")
(println (+ 1 2 3 4 5))
```

Run it:

```bash
$ ./cljnim run hello.clj
Hello from native Clojure!
15
```

Notice: the program was parsed, macro-expanded, emitted as Nim, compiled to C, compiled to machine code, and executed — all in under a second.

---

## The REPL: Two Modes

### Human REPL

```bash
$ ./cljnim repl
user> (defn square [x] (* x x))
user> (square 7)
=> 49
user> (atom 42)
=> (atom 42)
user> :ai function for fibonacci
🤖 Thinking...
💡 AI Suggestion:
   (defn fib [n]
     (loop [a 0 b 1 i 0]
       (if (= i n) a (recur b (+ a b) (inc i)))))
```

### JSON REPL (for AI Agents)

```bash
$ ./cljnim repl --json
{"status":"ready","ns":"user","mode":"json"}

> {"op":"eval","form":"(+ 1 2 3)"}
{"status":"ok","result":{"printed":"6"},"meta":{"ms":12}}

> {"tool":"cljnim/eval","args":{"form":"(defn greet [name] (str \"Hello \" name))"}}
{"status":"ok","result":{"type":"var","name":"greet"},...}
```

The JSON REPL is designed for programmatic interaction. Every operation has structured input and output. AI agents can discover capabilities, evaluate code, inspect definitions, and batch-process forms without parsing human-readable text.

---

## AI-Powered Development

Bara Lang is the first Clojure implementation built with AI assistance as a first-class feature.

### Error Explanation

When compilation fails, the compiler asks an AI for help:

```bash
$ ./cljnim run broken.clj
Compilation failed
Error: identifier expected, but got 'keyword var'

💡 AI Suggestion:
   The error occurs because `var` is a reserved keyword in Nim.
   Fix: Rename the function to `my-var`.
```

### Code Generation

Generate idiomatic Clojure from a description:

```bash
$ ./cljnim ai "function that filters even numbers"
(defn filter-even [coll]
  (loop [remaining coll result []]
    (if (empty? remaining)
      result
      (let [x (first remaining)]
        (recur (rest remaining)
               (if (even? x) (conj result x) result))))))
```

### Setup

```bash
export DEEPSEEK_API_KEY="sk-..."
# or OPENAI_API_KEY, or MIMO_API_KEY
```

---

## `loop` / `recur`: Real TCO

Unlike JVM Clojure (which uses `recur` to avoid stack overflow but still runs on a stack-based VM), Bara Lang compiles `loop`/`recur` to a native `while` loop:

```clojure
(defn factorial [n]
  (loop [acc 1 i n]
    (if (= i 0)
      acc
      (recur (* acc i) (dec i)))))
```

This generates efficient C code with no function calls. It is **genuinely O(1) stack space**.

---

## Cross-Compilation Targets

Bara Lang can target multiple platforms from the same source:

### Native Binary (default)
```bash
./cljnim run program.clj
```

### JavaScript
```bash
./cljnim compile program.clj program.nim
nim js -o:program.js program.nim
node program.js
```

### C Shared Library
```bash
./cljnim compile-lib program.clj program.nim
nim c --app:lib -o:libprogram.so program.nim
```

### WASM (experimental)
```bash
# Via Zig or Emscripten
nim c -d:release --cpu:wasm32 --os:linux program.nim
```

This is something JVM Clojure simply cannot do.

---

## Persistent Data Structures

Bara Lang implements real **Hash Array Mapped Trie (HAMT)** vectors and maps:

```clojure
(def v (vector 1 2 3))
(def v2 (conj v 4))
;; v  => [1 2 3]
;; v2 => [1 2 3 4]
;; Structural sharing: O(log₃₂ n) updates, not O(n) copies
```

The runtime uses the same algorithms as Clojure/JVM (32-way branching, path copying, tail optimization), but compiled to bare metal.

---

## Concurrency

### Atoms

```clojure
(def counter (atom 0))
(swap! counter inc)    ;; => 1
(reset! counter 100)   ;; => 100
(deref counter)        ;; => 100
```

### Agents

```clojure
(def state (agent 0))
(send state + 10)
(await state)
(deref state)          ;; => 10
```

### Channels (core.async)

```clojure
(def ch (chan 10))
(put! ch 42)
(take! ch)             ;; => 42
(close! ch)
```

All concurrency primitives work in both the compiled runtime and the in-memory interpreter.

---

## Macros That Work

```clojure
(defmacro unless [condition body]
  `(if (not ~condition)
     ~body))

(unless false
  (println "This prints!"))
```

Threading macros, `when-let`, `cond`, `doto`, `some->` — all implemented as real Clojure macros, expanded at compile time.

---

## When to Use Bara Lang

| Use Case | Clojure/JVM | Bara Lang |
|----------|-------------|-------------|
| Large web services | ✅ | ⚠️ (early stage) |
| CLI tools | ⚠️ (slow startup) | ✅ (instant) |
| Embedded systems | ❌ | ✅ |
| WASM / browser | ClojureScript | ✅ (native WASM) |
| Shared libraries | ❌ | ✅ |
| AI agent scripting | ❌ | ✅ (JSON REPL) |
| Learning Clojure | ✅ | ✅ (no JVM needed) |

---

## Further Reading

- [Getting Started](01-fundamentals.md) — Core Clojure concepts (applies to all dialects)
- [Architecture](../../docs/en/02-architecture.md) — How the compiler works internally
- [AI Integration](../../docs/en/03-ai-integration.md) — Deep API details for AI features
- [API Reference](../../docs/en/04-api-reference.md) — JSON REPL protocol specification

---

*Bara Lang is proof that you do not need a virtual machine to write elegant, functional, immutable code. You just need a good compiler.*
