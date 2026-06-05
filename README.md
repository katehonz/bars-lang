# 🐆 Bars

> **Bars** (барс) — Снежният леопард. Бърз, независим, опасен.The snow leopard (Panthera uncia) 

![Bars — the Snow Leopard](bars-kotka.png)

A systems programming language with **Clojure** syntax, **Rust**-like ownership (lighter), and compilation to native code via **Cranelift** and **LLVM**.

```clojure
;; examples/hello.brs
(defn main []
  (println "Hello, World!"))
```

```bash
$ bars run examples/hello.brs
Hello, World!
```

---

## Why Bars?

- **Clojure syntax** — parentheses naturally express scope and structure. Only `()` and `[]` brackets.
- **Lightweight ownership** — NLL borrow checking, drop checking, no lifetime annotations.
- **Type inference** — Hindley-Milner type system with `bars check --types`.
- **Two backends** — Cranelift for JIT/REPL and fast AOT, LLVM for `--release`.
- **Lambda functions** — anonymous `(fn [x] body)` with full pipeline support.
- **Zero-cost FFI** — direct C ABI access through the runtime.
- **GC when you want it** — stack + ownership + Boehm GC for complex data.
- **`.brs`** — source file extension.

---

## Quick Start

### Prerequisites

- Rust 1.70+ (for building the compiler)
- `libgc-dev` (Boehm GC for the runtime)
- `cc` / `gcc` (for linking)

### Build

```bash
git clone https://codeberg.org/bars-lang/bars-lang.git
cd bars-lang
cargo build --release
```

### Run

```bash
# Read and print AST
bars read examples/hello.brs

# Compile and run (default Cranelift backend)
bars run examples/math.brs

# Compile and run with Cranelift backend
bars run --backend cranelift examples/math.brs

# REPL (Cranelift JIT)
bars repl
```

---

## Language Tour

### Functions

```clojure
(defn greet [name]
  (println name))

(defn add [a b]
  (+ a b))
```

### Variables

```clojure
(defn main []
  (let [x 42
        y (+ x 1)]
    (println y)))
```

### Conditionals

```clojure
(defn main []
  (let [x 2]
    (cond
      (= x 1) "one"
      (= x 2) "two"
      :else   "other")))
```

### Loops

```clojure
(defn factorial [n]
  (loop [i n acc 1]
    (if (= i 0)
      acc
      (recur (- i 1) (* acc i)))))
```

### Vectors

```clojure
(defn main []
  (let [v (vector 1 2 3)]
    (push v 4)
    (println (count v))        ;; 4
    (println (get v 2))))      ;; 3
```

Vectors can be nested:

```clojure
(def v [1 [2 3] 4])
(println (get (get v 1) 0))  ;; 2
```

### Maps

Maps are created with functions (no `{}` literal syntax):

```clojure
(defn main []
  (let [m (map)]
    (map-set m 1 100)
    (println (map-get m 1))))  ;; 100
```

Maps can hold vectors as values:

```clojure
(def m (map))
(map-set m 1 [10 20])
(println (get (map-get m 1) 0))  ;; 10
```

### Sets

```clojure
(defn main []
  (let [s (set)]
    (set-add s 1)
    (set-add s 2)
    (println (set-count s))          ;; 2
    (println (set-contains? s 2))))  ;; 1 (true)
```

### Borrowing (Ownership)

```clojure
(defn use-buf [^buf data]
  ;; immutable borrow
  (println (count data)))

(defn mutate-buf [^mut buf data]
  ;; mutable borrow
  (push data 42))

;; Implicit borrow: ^ is optional when passing owned values
(let [v (vector 1 2 3)]
  (use-buf v)           ;; automatic borrow
  (use-buf v))          ;; OK — borrow released after each call
```

### Loading Libraries

```clojure
(load "lib/core.brs")
(load "lib/math.brs")

(defn main []
  (println (factorial 5))
  (println (range 1 10)))
```

### Lambda Functions

```clojure
;; Inline anonymous functions
(fn [x] (+ x 1))

;; Lambda with borrow annotation
(fn [^buf data]
  (println (count data)))

;; Lambda as function body
(defn make-adder [n]
  (fn [x] (+ x n)))
```

### Type Checking

```bash
$ bars check --types examples/hello.brs
✅ Type inference passed.
  main : i64
```

### Algebraic Data Types

```clojure
(deftype Option [Some i64] [None])
(deftype Result [Ok i64] [Err i64])

(defn handle [res]
  (match res
    (Ok v) (+ v 1)
    (Err e) (* e -1)))
```

Конструкторите се разпознават по главна буква. `match` проверява за exhaustiveness.

### FFI — Foreign Function Interface

```clojure
;; Деклариране на C функция
(extern "putchar" [c i64] -> i64)

(defn main []
  (putchar 65))  ;; отпечатва 'A'
```

Работи с Cranelift и LLVM — генерира правилни extern declarations.

---

## CLI Reference

| Command | Description |
|---------|-------------|
| `bars read <file>` | Parse and print AST |
| `bars build <file>` | Compile to binary via HIR |
| `bars build --backend cranelift <file>` | Compile via Cranelift |
| `bars build --backend llvm <file>` | Compile via LLVM |
| `bars build --release <file>` | Release build with optimizations |
| `bars run <file>` | Compile, link, and execute (default Cranelift) |
| `bars run --backend cranelift <file>` | Compile, link, and execute (Cranelift) |
| `bars run --backend llvm <file>` | Compile, link, and execute (LLVM) |
| `bars repl` | Interactive Cranelift JIT session |
| `bars check <file>` | Run ownership analysis |
| `bars check --types <file>` | Run type inference |
| `bars build --features llvm-backend` | Enable LLVM backend (requires LLVM 14+) |

---

## Project Structure

```
.
├── bootstrap/        # Rust bootstrap compiler
│   ├── src/           # Compiler source (Rust)
│   ├── reader/       # Lexer + Parser
│   ├── ast/          # AST types
│   ├── macro/        # Macro expansion
│   ├── ownership/    # Ownership checker
│   ├── types/        # Hindley-Milner type inference
│   ├── hir/          # High-level IR (flattened)
│   └── backends/     # Cranelift + LLVM backends
├── compiler/         # Self-hosted compiler (Bars)
│   ├── reader.brs    # Lexer + Parser
│   ├── hir.brs       # AST → HIR lowering
│   ├── types.brs     # Type inference
│   ├── ownership.brs # Ownership checker
│   ├── build.brs     # Build pipeline
│   └── codegen/      # LLVM backend
├── runtime/          # C runtime + Boehm GC
├── lib/              # Standard library (.brs)
├── examples/         # Example programs
├── tests/            # Integration tests
└── docs/             # Documentation
```

---

## Backends

| Backend | Mode | Status |
|---------|------|--------|
| **Cranelift** | JIT / REPL / AOT | ✅ Working |
| **LLVM** | Optimized release (--release) | ✅ Working |

---

## Standard Library

See [`lib/`](lib/) and [`docs/04-stdlib.md`](docs/04-stdlib.md).

- `lib/core.brs` — numeric helpers, vector helpers, range, `or`, `and`
- `lib/math.brs` — `square`, `cube`, `gcd`, `lcm`, `factorial`, `fib`, `sum`, `product`
- `lib/vector.brs` — `last`, `rest`, `take`, `drop`, `reverse`, `contains?`, `index-of`
- `lib/string.brs` — `str-empty?`, `str-count`
- `lib/map.brs` — `map-empty?`, `map-has?`
- `lib/adt.brs` — `Option`, `Result` типове с helper функции
- `lib/test.brs` — `assert` макрос за тестове

### Built-in Runtime Functions

| Функция | Описание |
|---------|----------|
| `sqrt n` | Корен квадратен |
| `pow base exp` | Степенуване |
| `abs n` | Абсолютна стойност |
| `str-count s` | Дължина на низ |
| `str-concat a b` | Конкатенация на низове |
| `slurp path` | Прочита файл като низ |
| `spit path content` | Записва низ във файл |

---

## Architecture

```
.brs → Reader → AST → Macro → Ownership → Types → HIR → Codegen → Native
                                                                    ├── Cranelift → cc
                                                                    └── LLVM IR → llc → cc
```

---

## Development Status

See [ROADMAP.md](ROADMAP.md) for the full plan.

| Feature | Status |
|---------|--------|
| Reader (Lexer + Parser) | ✅ |
| AST → HIR → LLVM IR | ✅ |
| Functions & recursion | ✅ |
| Ownership checker | ✅ |
| Runtime + Boehm GC | ✅ |
| REPL + Cranelift JIT | ✅ |
| Built-in macros (`when`, `unless`, `cond`, `->`, `->>`) | ✅ |
| `loop` / `recur` | ✅ |
| `load` system | ✅ |
| Stdlib | ✅ |
| LLVM backend | ✅ |
| User-defined macros (`defmacro`) | ✅ |
| Type inference (`check --types`) | ✅ |
| Lambda functions (`fn [x] body`) | ✅ |
| Nested collections | ✅ |
| Sets | ✅ |
| Cranelift AOT | ✅ |
| Generics (implicit polymorphism) | ✅ |
| ADT (`deftype`, exhaustiveness check) | ✅ |
| FFI (`extern` C functions) | ✅ |

---

## License

MIT or Apache-2.0
