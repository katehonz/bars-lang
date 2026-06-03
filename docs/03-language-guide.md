# Language Guide

## Syntax

Bars uses Clojure-style S-expressions with **only two bracket types**:

| Brackets | Meaning |
|----------|---------|
| `(...)` | Function calls, special forms (`defn`, `let`, `if`, `do`, `loop`) |
| `[...]` | Vectors, function parameters, `let` bindings |

> **Note:** There is no `{}` syntax in Bars. Maps and sets are created with functions.

### Literals

```clojure
42          ;; integer
-7
3.14        ;; float (not yet supported in all backends)
true        ;; boolean
false
"hello"     ;; string
:keyword    ;; keyword (represented as string at runtime)
nil         ;; null
```

### Symbols and Naming

Symbols can contain letters, digits, and special characters:

```clojure
x
my-var
inc
count
empty?
even?
_plus
```

Special characters are sanitized for the backends (`?` → `_Q`, `+` → `_plus`, etc.).

## Special Forms

### `defn` — Define a Function

```clojure
(defn name [params...]
  body)

;; With type annotations
(defn add [^i64 a ^i64 b]
  (+ a b))
```

Type annotations in parameters use the `^type` syntax. Supported types:
- `^i64` — 64-bit integer
- `^f64` — 64-bit float
- `^bool` — boolean
- `^i64 name` — reference (immutable borrow)
- `^mut i64 name` — mutable reference

### `let` — Local Bindings

```clojure
(let [x 10
      y 20]
  (+ x y))
```

### `if` — Conditional

```clojure
(if condition
  then-expr
  else-expr)
```

The `else-expr` is optional and defaults to `nil`.

### `cond` — Multi-way Conditional

```clojure
(cond
  (= x 1) "one"
  (= x 2) "two"
  :else   "other")
```

`:else` (or any keyword as the last condition) acts as a catch-all.

### `do` — Sequence Expressions

```clojure
(do
  (println "first")
  (println "second")
  42)
```

Returns the value of the last expression.

### `loop` / `recur` — Tail Recursion / Iteration

```clojure
(loop [i 0 acc 0]
  (if (= i 10)
    acc
    (recur (+ i 1) (+ acc i))))
```

- `loop` introduces a binding scope and a loop target.
- `recur` must provide exactly as many arguments as `loop` has bindings.
- `recur` can appear inside `if` branches.

### `def` — Global Variable

```clojure
(def pi 3.14159)
```

## Data Structures

### Vectors

```clojure
(def v (vector 1 2 3))   ;; create
(push v 4)                ;; append
(get v 0)                 ;; index → 1
(count v)                 ;; length → 4
```

Vectors can be nested:

```clojure
(def v [1 [2 3] 4])
(println (get (get v 1) 0))  ;; → 2
```

### Maps

Maps are created with functions (no `{}` literal syntax):

```clojure
(def m (map))             ;; create
(map-set m 1 100)         ;; set key-value
(map-get m 1)             ;; get → 100
(map-count m)             ;; size
```

Maps can hold vectors and other collections as values:

```clojure
(def m (map))
(map-set m 1 [10 20])
(println (get (map-get m 1) 0))  ;; → 10
```

### Sets

Sets are created with the `set` function:

```clojure
(def s (set))             ;; create empty set
(set-add s 42)            ;; add element
(set-contains? s 42)      ;; → 1 (true)
(set-contains? s 99)      ;; → 0 (false)
(set-count s)             ;; → 1
```

### Strings

Strings are allocated through the C runtime. They can be passed to `println`.

```clojure
(def s "Hello")
(println s)
```

## Operators

All operators are prefix (Lisp style):

```clojure
(+ 1 2)     ;; 3
(- 10 3)    ;; 7
(* 4 5)     ;; 20
(/ 10 2)    ;; 5
(% 10 3)    ;; 1

(= 1 1)     ;; true
(!= 1 2)    ;; true
(< 3 5)     ;; true
(> 3 5)     ;; false
(<= 3 3)    ;; true
(>= 3 3)    ;; true

(not true)  ;; false
```

## Borrowing and Ownership

Bars has a lightweight ownership checker that runs before code generation:

```bash
bars check file.brs
```

### Immutable Borrow

```clojure
(defn inspect [^i64 vec]
  (println (count vec)))
```

### Mutable Borrow

```clojure
(defn fill [^mut i64 vec]
  (push vec 42))
```

### Implicit Borrow

When passing an owned value to a function that expects a borrow, Bars automatically borrows it for you:

```clojure
(defn inspect [^i64 vec]
  (println (count vec)))

(let [v (vector 1 2 3)]
  (inspect v)           ;; implicit borrow — no need for ^v
  (inspect v))          ;; OK: borrow was released after the call
```

### Ownership Rules

1. A value can have any number of immutable borrows OR exactly one mutable borrow.
2. You cannot use a value after it has been moved (unless it implements `Copy`, like integers).
3. Borrowed values cannot be moved.
4. Parameters of functions are not checked for resource leaks — they are owned by the caller.

## Macros

Bars has built-in macros that expand before code generation:

### `when`

```clojure
(when condition
  expr1
  expr2)
;; expands to:
(if condition
  (do expr1 expr2)
  nil)
```

### `unless`

```clojure
(unless condition
  expr1)
;; expands to:
(if (not condition)
  expr1
  nil)
```

### Threading Macros

```clojure
(-> x
    (f a)      ;; (f x a)
    (g b))     ;; (g (f x a) b)

(->> x
     (f a)     ;; (f a x)
     (g b))    ;; (g b (f a x))
```

## Loading Code

```clojure
(load "lib/core.brs")
(load "lib/math.brs")
```

`load` resolves paths relative to the file's directory and walks up the directory tree until the file is found. This allows `examples/foo.brs` to load `lib/core.brs`.
