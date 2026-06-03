# Ownership Model: Scope-Based Memory Management

## The Core Insight

In Bars, every pair of parentheses `(` `)` is a **scope boundary**. This is not just syntax — it is the foundation of memory management.

```clojure
(let [file (open "data.txt")]     ;; scope begins
  (read file)                      ;; borrow
  (process file))                  ;; borrow again
;; scope ends → file is automatically closed
```

Because Lisp syntax is *explicitly nested*, ownership analysis is **local and linear**. We never need to track lifetimes across complex control flow graphs. The structure of the code *is* the lifetime graph.

## How Scopes Own Memory

```
(                              ← scope A begins
  (let [x (vector 1 2 3)]     ← x is owned by scope A
    (use x)                   ← immutable borrow
    (let [y x]                ← ERROR: x would be moved
      ...)))
)                              ← scope A ends → x is dropped
```

## The Rules

### 1. Default Immutability

Like Clojure, values are immutable by default. You can read them freely, but modifying requires explicit mutation (via `^mut` borrow or GC-managed types).

### 2. Copy Types (No Move)

Primitive types are copied, not moved:

| Type | Behavior |
|------|----------|
| `i64`, `bool`, `f64` | **Copy** — passed by value, original stays valid |
| `String`, `Vector`, `Map`, `Set` | **Move** — ownership transfers, original becomes invalid |
| User-defined structs | **Move** by default, opt-in `Copy` |

```clojure
(let [x 42]           ;; i64 is Copy
  (let [y x]          ;; x is copied, not moved
    (+ x y)))         ;; OK: both are valid → 84

(let [v (vector 1)]   ;; vector is non-Copy
  (let [w v]          ;; v is moved to w
    v))               ;; ERROR: use after move
```

### 3. Borrowing

Borrowing lets you temporarily access a value without taking ownership:

```clojure
(defn inspect [^i64 vec]        ;; immutable borrow
  (println (count vec)))

(defn fill [^mut i64 vec]       ;; mutable borrow
  (push vec 42))

(let [v (vector 1 2 3)]
  (inspect v)                    ;; borrow v immutably
  (inspect v)                    ;; borrow again — OK
  (fill v))                      ;; ERROR: can't mutably borrow while immutably borrowed
```

### 4. Implicit Borrow

Bars automatically borrows owned values when passing them to functions that expect a borrow parameter. You don't need to write `^` every time:

```clojure
(defn inspect [^i64 vec]
  (println (count vec)))

(let [v (vector 1 2 3)]
  (inspect v)           ;; implicit borrow — no need for ^v
  (inspect v))          ;; OK: borrow was released after each call
```

This works because:
- **Copy types** (`i64`, `bool`) are trivially copyable — no borrow needed.
- **Owned values** passed to `^` parameters are automatically borrowed for the duration of the call.
- **Already-borrowed values** can be "reborrowed" without explicit `^`.

### 5. Move by Default

When passing a non-Copy value to a function that does NOT expect a borrow, ownership moves:

```clojure
(defn consume [data]
  (process data))

(let [v (vector 1 2 3)]
  (consume v)                    ;; v is moved into consume
  v)                             ;; ERROR: use after move
```

To keep the value, pass a borrow instead:

```clojure
(let [v (vector 1 2 3)]
  (consume ^v)                   ;; borrow, don't move
  v)                             ;; OK
```

### 6. Automatic Drop at Scope End

When a scope ends, all owned values that haven't been moved are automatically dropped (cleaned up):

```clojure
(defn process []
  (let [file (open "data.txt")]  ;; file is owned
    (read file)
    ;; file is automatically closed here
    ))
```

This applies to:
- `let` bindings
- Function parameters
- `loop` bindings

Note: function parameters are owned by the **caller**, not locally allocated, so they are not checked for resource leaks at function end.

### 7. The Stack Is the Owner

Stack-allocated values (primitives, small structs) never need heap allocation. The stack frame itself is the owner:

```clojure
(let [a 10                      ;; on stack
      b (+ a 20)]               ;; on stack
  (+ a b))                      ;; no heap allocation, no GC
```

## Why This Is Easier Than Rust

| | Rust | Bars |
|---|---|---|
| **Lifetimes** | Explicit annotations (`'a`, `'static`) | Implicit from parentheses |
| **Borrow checker** | Region-based, global analysis | Scope-based, local analysis |
| **Learning curve** | Months | Hours |
| **Error messages** | Complex, refer to lifetimes | Simple: "x was moved" or "x is borrowed" |

Rust's borrow checker is conservative — it rejects valid programs to ensure safety. Bars' checker is **permissive but safe within scopes**. Because scopes are explicit and nested, there is no ambiguity about when a value dies.

## Interaction with GC

Bars uses a hybrid model:

| Category | Management | Drop behavior |
|----------|-----------|---------------|
| Stack primitives (`i64`, `bool`) | Automatic | No-op (Copy types) |
| Owned heap values (custom structs) | Ownership + explicit drop | Drop at scope end or move |
| GC-managed (`Vector`, `Map`, `Set`, `String`) | Boehm GC | GC collects when unreachable |

You choose the trade-off:
- Use ownership for performance-critical code (no GC pauses)
- Use GC-managed types for complex data structures (no manual memory management)

## Example: File Handling

```clojure
(defn read-config [path]
  (let [file (open path)]        ;; file is owned
    (let [contents (read-all file)]
      (parse contents))))        ;; file is dropped here

(defn main []
  (let [config (read-config "app.conf")]
    (println config)))           ;; config is dropped here
```

No `close()` calls. No `defer`. No `drop()`. The parentheses handle it.
