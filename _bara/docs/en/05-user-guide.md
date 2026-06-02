
[← Back to Index](index.md)

---

# Bara Lang User Guide

## Installation

### Prerequisites
- Nim >= 2.0
- GCC or Clang
- make

### Build from Source
```bash
git clone https://gitlab.com/balvatar/lisp-nim.git
cd lisp-nim
make build
```

## CLI Commands

### `compile` — Compile to Nim
```bash
./cljnim compile input.clj output.nim
```
Generates a `.nim` file from Clojure source.

### `run` — Compile and Execute
```bash
./cljnim run examples/hello.clj
```
Compiles to Nim, then to C, then to a binary, and runs it.

### Global Flags

#### `--lib-path <dir>` — Custom Library Directory
Override the default `lib/` search path. Checked before `CLJNIM_LIB_PATH` env var and built-in paths.

```bash
./cljnim --lib-path ./my_project/lib run app.clj
```

Environment variable alternative:
```bash
export CLJNIM_LIB_PATH=./my_project/lib
./cljnim run app.clj
```

### `read` — Parse and Print AST
```bash
./cljnim read examples/hello.clj
```
Shows the Clojure AST as S-expressions.

### `repl` — Interactive REPL
```bash
# Human-friendly mode
./cljnim repl

# AI mode (structured JSON)
./cljnim repl --json
```

## Writing Bara Lang Programs

### Basic Syntax
```clojure
; Comments start with semicolon

; Define a variable
(def x 42)

; Define a function
(defn greet [name]
  (println "Hello, " name))

; Function with docstring
(defn greet "Says hello to someone" [name]
  (str "Hello, " name))

; Multi-arity function
(defn greet-multi
  ([name] (greet-multi name "Hello"))
  ([name greeting] (str greeting ", " name)))

; Function with rest parameters
(defn sum-all [x & rest]
  (+ x (reduce + rest)))

; Call a function
(greet "World")
(greet-multi "Alice")          ;; => "Hello, Alice"
(greet-multi "Alice" "Hi")     ;; => "Hi, Alice"
(sum-all 1 2 3 4)              ;; => 10

; Arithmetic
(+ 1 2 3)      ; => 6
(* 10 20)      ; => 200
(/ 100 4)      ; => 25

; Conditionals
(if (> x 0)
  "positive"
  "non-positive")

; Local bindings
(let [a 10
      b 20]
  (+ a b))     ; => 30
```

### Working with Data
```clojure
; Vectors (use Nim seq internally)
(def nums [1 2 3 4 5])

; Keywords
(def person {:name "Alice" :age 30})

; Keyword as function (lookup in map)
(:name person)                 ;; => "Alice"
(:age person)                  ;; => 30

; Maps and sets use persistent HAMT data structures
; with structural sharing and O(log₃₂ n) operations.
```

### Recursion
```clojure
(defn factorial [n]
  (if (= n 0)
    1
    (* n (factorial (- n 1)))))

(println (factorial 5))  ; => 120
```

### First-Class Functions
User-defined functions can be passed as values to higher-order functions:

```clojure
(defn square [x] (* x x))
(defn odd? [x] (= 1 (mod x 2)))

(map square [1 2 3 4])         ;; => [1 4 9 16]
(filter odd? [1 2 3 4])        ;; => [1 3]
(apply + [1 2 3])              ;; => 6
```

### Loop / Recur
```clojure
(defn find-header [headers name]
  (loop [pairs (seq headers)]
    (if (empty? pairs)
      nil
      (let [[k v] (first pairs)]
        (if (= k name)
          v
          (recur (rest pairs)))))))

(find-header [[:content-type "text/html"] [:accept "*/*"]] :accept)
;; => "*/*"
```

## AI REPL Guide

The JSON REPL is designed for programmatic interaction.

### Start AI REPL
```bash
./cljnim repl --json
```

### Evaluate a Form
```json
{"op": "eval", "form": "(+ 1 2 3)"}
```
Response:
```json
{
  "status": "ok",
  "result": {"printed": "6"},
  "meta": {"ns": "user", "ms": 861, "form": "(+ 1 2 3)"}
}
```

### Batch Evaluation
```json
{"op": "eval-batch", "forms": ["(defn f [x] x)", "(f 42)"]}
```

### List Definitions
```json
{"op": "get-defs"}
```
Response:
```json
{"status": "ok", "defs": ["f"], "ns": "user"}
```

### Clear Session
```json
{"op": "clear"}
```

### Exit
```json
{"op": "quit"}
```

## Tips

- Use `:help` in human REPL for available commands.
- Definitions in REPL persist across evaluations in the same session.
- The `--json` flag makes the REPL fully machine-readable.
