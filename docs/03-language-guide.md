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

Optional **docstring** — first body expression is a string, then real body
(skipped at runtime by the self-hosted compiler; extracted by `bars-self doc`):

```clojure
(defn add [a b]
  "Add two integers."
  (+ a b))
```

Leading `;;` comments above `defn` are also used as docs (same as before).

### Traits (Phase 14.4+)

Static monomorphization — no dynamic dispatch. Methods become
`Trait_method_Type` functions.

```clojure
(deftrait Show [show]
  ;; default method; Self is replaced by the impl type
  (default display [x]
    (tcall Show show Self x)))

(impl Show for i64
  (defn show [x] x))
  ;; display is synthesized → Show_display_i64

(tcall Show show i64 7)       ;; or (trait-call Show show i64 7)
(tcall Show display i64 7)
```

| Form | Meaning |
|------|---------|
| `(deftrait T [m1 m2] (default m …)*)` | Declare required methods + defaults |
| `(impl T for Type (defn m …)*)` | Provide methods; missing defaults are filled |
| `Self` | Placeholder type inside defaults |
| `(tcall T m Type args…)` | Call `T_m_Type` (alias of `trait-call`) |

### `defconst`

```clojure
(defconst ANSWER 42)
(ANSWER)   ;; → 42  (zero-arg function)
```

### Async (package, not core)

```clojure
(require "lib/async" :as async)
(async/ready 1)
(async/pending)
(async/unwrap fut)
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

### Destructuring in `let`

Vector and nested patterns (also works with `defstruct` field patterns):

```clojure
(let [[a b c] (vector 10 20 30)]
  (+ a b c))          ;; 60

(let [[x _ z] (vector 1 2 3)]
  (+ x z))            ;; 4  (_ discards)

(let [[a [b c] d] (vector 7 (vector 8 9) 10)]
  (+ a b c d))        ;; 34
```

See `examples/let_destructure.brs`, `examples/struct_destructure.brs`.

### Higher-order `map` / `filter` / `reduce` / `some` / `every?`

These are **not** hashmap constructors. With two (or three) arguments they
desugar to inline `loop`/`recur` (self-host):

```clojure
(defn add1 [x] (+ x 1))
(defn even? [x] (= (% x 2) 0))
(defn add [a b] (+ a b))
(defn pos? [n] (> n 0))

(map add1 [1 2 3])             ;; [2 3 4]
(filter even? [1 2 3 4])       ;; [2 4]
(reduce add 0 [1 2 3 4 5])     ;; 15
(some pos? [0 -1 3])           ;; 1 (first truthy pred result)
(every? pos? [1 2 3])          ;; 1
(every? pos? [1 0 3])          ;; 0
(not-any? pos? [-1 0])         ;; 1 (no element matches)
(not-every? pos? [1 0 3])      ;; 1 (not all match)
(take 3 [1 2 3 4 5])           ;; [1 2 3]
(drop 2 [1 2 3 4 5])           ;; [3 4 5]
(take-while pos? [1 2 0 4])    ;; [1 2]
(drop-while pos? [1 2 0 4])    ;; [0 4]
(range 4)                      ;; [0 1 2 3]
(range 2 6)                    ;; [2 3 4 5]
(range 0 10 3)                 ;; [0 3 6 9]
(range 5 0 -2)                 ;; [5 3 1]
(reverse [1 2 3 4])            ;; [4 3 2 1]
(concat [1 2] [3 4 5])         ;; [1 2 3 4 5]
(concat [1] [2] [3])           ;; [1 2 3] (variadic)
(distinct [1 2 2 3 1])         ;; [1 2 3]
(interpose 0 [1 2 3])          ;; [1 0 2 0 3]
(partition 2 [1 2 3 4 5])      ;; [[1 2] [3 4]] (tail dropped)
(frequencies [1 2 1])          ;; map {1: 2, 2: 1}
(sort [4 1 3 2])               ;; [1 2 3 4] (default <, input kept)
(sort > [4 1 3 2])             ;; [4 3 2 1] (custom comes-before cmp)
(group-by pos? [1 -2 3])       ;; map {1: [1 3], 0: [-2]}
(zipmap [10 20] [1 2])         ;; map {10: 1, 20: 2}
(select-keys m [1 3])          ;; only keys 1 and 3 from map m
(mapcat wrap [1 2])            ;; f → vector per elem, concatenated
(keep f [1 2 3])               ;; non-0 (f x) results only
(flatten [1 [2 [3]] 4])        ;; [1 2 3 4] (deep)
(get-in m [1 0])               ;; walk maps/vectors by key path
(update m 5 f)                 ;; map-set m 5 (f (map-get m 5))
(sort-by abs [-3 1 -2])        ;; [1 -2 -3] (key fn, ascending)
(map-indexed f [a b])          ;; like map, f gets [idx x]
(take-nth 2 [1 2 3 4 5])       ;; [1 3 5]
(dedupe [1 1 2 2 1])           ;; [1 2 1] (consecutive only)
(merge a b)                    ;; clone of a + b's keys (b wins)
(dissoc m 2 3)                 ;; clone without keys 2 and 3
(assoc-in m [1 6] 60)          ;; nested assoc, input kept
(update-in m [1 6] f)          ;; assoc-in with (f current)
(reduce-kv f 0 m)              ;; fold over [acc k v]
(keys m) (vals m)              ;; key / value vectors
(min 3 7) (max 3 7)            ;; 3 , 7

;; Inline lambda (beta-reduced into the loop):
(map (fn [x] (* x 2)) [1 2 3])
```

Empty `(map)` still creates a **hash map**. Use `map-set` / `map-get` for maps.

### Keyword arguments (`kwargs`)

Trailing keyword options are packed **explicitly** with the `kwargs` built-in
(so `(map-set m :k v)` is not rewritten):

```clojure
(require "lib/kw" :as kw)

(defn greet [msg opts]
  (let [name (kw/lookup-or opts "name" "world")]
    (println name)))

(greet "hi" (kwargs :name "Ada" :times 3))
;; opts = ["name" "Ada" "times" 3]
```

Keywords themselves lower to strings like `":foo"` when used as values.

### `if` — Conditional

```clojure
(if condition
  then-expr
  else-expr)
```

The `else-expr` is optional and defaults to `nil`. Non-zero integers are truthy
(branch condition is `≠ 0`).

### Built-in macros (control & iteration)

| Macro | Role |
|-------|------|
| `when` / `unless` / `when-not` | body when truthy / falsy |
| `if-not` | `(if (not c) then else)` |
| `if-let` / `when-let` | bind + truthy test |
| `and` / `or` / `cond` / `case` | short-circuit / multi-way |
| `doseq` / `for` / `dotimes` / `while` | iteration |
| `partial` / `fnil` / `complement` / `constantly` / `juxt` / `comp` / `identity` / `apply` | first-class fn helpers |
| `->` / `->>` | threading |

```clojure
(when cond body...)          ;; (if cond (do body...) nil)
(unless cond body...)        ;; (if (not cond) (do body...) nil)
(when-not cond body...)      ;; alias of unless
(if-not cond then else?)     ;; (if (not cond) then else)

(if-let [x (maybe)]
  then-expr
  else-expr)                 ;; else optional → nil

(when-let [x (maybe)]
  body...)                   ;; (let [x (maybe)] (when x body...))

(partial f a b)              ;; (fn [x] (apply f a b [x]))
(complement pred)            ;; (fn [x] (not (pred x)))
(constantly v)               ;; (fn [_] v)  — v evaluated once
(juxt f g h)                 ;; (fn [x] (vector (f x) (g x) (h x)))
(comp f g h)                 ;; (fn [x] (f (g (h x))))  — rightmost first
(fnil f d)                   ;; (fn [x] (f (if x x d)))  — 0/nil → default
(fnil f d1 d2)               ;; same for 2–3 args
(identity x)                 ;; → x (runtime builtin)
```

`if-let` / `when-let` bind a single name; the body runs only when the init
value is truthy.

### Threading macros `->` / `->>`

```clojure
(-> 1 (+ 2) (* 3))           ;; (* (+ 1 2) 3) → 9
(->> 5 (+ 1) (* 2))          ;; (* 2 (+ 1 5)) → 12
```

`->` inserts the value as the **first** argument of each form; `->>` as the
**last**.

### `cond` — Multi-way Conditional

```clojure
(cond
  (= x 1) "one"
  (= x 2) "two"
  :else   "other")
```

`:else` (or any keyword as the last condition) acts as a catch-all.

### `case` — equality dispatch

```clojure
(case n
  1 10
  2 20
  3 30
  0)                     ;; default when no constant matches

(case n
  (1 2 3) 1              ;; multi-const group → or of =
  [4 5]   2              ;; vector group also OK
  0)
```

Pairs of `constant` / `result`. A list or vector of constants matches if **any**
equals the scrutinee. An odd trailing form is the default (`nil` if omitted).
The scrutinee is evaluated **once**.

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

### Automatic TCO (self-recursive `defn`)

The self-hosted compiler automatically converts **self-tail-recursive** calls
into loops, so deep recursion runs in constant stack space:

```clojure
(defn count-down [n]
  (if (= n 0)
    0
    (count-down (- n 1))))   ;; tail call → compiled as a loop

(count-down 1000000)          ;; no stack overflow
```

- Tail positions: last body expression, both branches of `if`, last
  expression of `do`, last body expression of `let`, `match` arm bodies.
- The call must be to the same function with the same number of arguments;
  anything else stays an ordinary call.
- Self-calls inside a nested `loop` or `fn` are not converted.
- Non-tail self-calls (e.g. `(+ 1 (fact (- n 1)))`) stay recursive calls.
- Caveat: a tail call that swaps bare parameters — `(f b a)` — can
  miscompile (sequential `recur` assignment, a pre-existing `loop`/`recur`
  limitation). Compute swapped values into `let` bindings first.
- Mutual recursion is not optimized; use explicit `loop`/`recur` there.

### `def` — Global Variable

A top-level `(def name init)` creates a **real global**, initialized once
before `main` runs and readable (and re-assignable) from every function:

```clojure
(def max-items 42)
(def nums (vector 1 2 3))

(defn add-num [n]
  (push nums n))          ;; shared mutable state via the container

(defn main []
  (do (println max-items) ;; 42
      (add-num 4)
      (println (count nums)))) ;; 4
```

- Initializers run once, in source order, in `__bars_init_globals`
  (called by the C main wrapper before `_bars_main`).
- A later `def` may reference an earlier global.
- Works in scripts without `main` as well as in programs with one.
- Do **not** shadow a global name with a local binding of the same name,
  and do not give a global the same name as a function.
- `def` inside a function body stays a local mutable slot (unchanged).

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

### `and` / `or`

Short-circuiting macros (not function calls):

```clojure
(and a b c)   ;; (if a (if b c false) false)
(or a b c)    ;; (let [t a] (if t t (or b c))) — no double-eval
(and)         ;; true
(or)          ;; false
```

Any non-zero / non-`false` / non-`nil` value is truthy (including integers other than 0).

### First-class functions

Named top-level functions and lambdas can be passed as values and called
through a local:

```clojure
(defn apply1 [f x] (f x))
(defn double [n] (* n 2))

(apply1 double 21)           ;; → 42
(apply1 (fn [n] (+ n 1)) 41) ;; → 42  (closed lambda lifted to __lamN)

(let [y 10]
  (apply1 (fn [x] (+ x y)) 32))  ;; → 42  (capturing closure)
```

Closed lambdas are lifted to top-level functions. Capturing lambdas pack free
locals into an env vector; the runtime `bars_icall0`…`bars_icall8` passes env
as the first argument when the callee is a local (higher arities error). Nested
`fn` forms are lifted **bottom-up**, so an inner lambda can capture both outer
free locals and the outer lambda’s parameters.

```clojure
(let [a 1]
  (let [f (fn [x]
            (let [g (fn [y] (+ (+ a x) y))]
              (g 10)))]
    (f 2)))   ;; → 13
```

Undefined names print `error: hir: undefined …` at compile time (link still
fails). Set `BARS_STRICT_HIR=1` to skip the backend after HIR errors.

HOF `map`/`filter`/`reduce` still beta-reduce inline lambdas (no allocation).

### `apply` — call with a vector of args

```clojure
(apply f [a b c])      ;; same as (f a b c)
(apply f a b [c d])    ;; fixed args then spread last vector → (f a b c d)
```

`apply` spreads into `bars_icall0`…`bars_icall8` (max 8 args total). The last
argument must be a vector; any preceding args after `f` are prepended.

```clojure
(let [f add2]
  (apply f [20 22]))          ;; → 42

(apply add3 10 [20 12])       ;; → 42
```

### `partial` — freeze leading args

```clojure
(partial f a b)   ;; → (fn [x] (apply f a b [x]))
```

Returns a **one-argument** function. Useful for specializing HOFs:

```clojure
(let [p (partial add3 10 20)]
  (p 12))                     ;; → 42
```

### `doseq` / `for` — iterate a vector

```clojure
(doseq [x coll]
  (println x))               ;; side effects; returns nil

(for [n coll]
  (* n 10))                  ;; → vector of body results

;; Multiple binding pairs nest (cartesian product):
(doseq [x xs y ys]
  (println (+ x y)))

(for [a as b bs]
  (* a b))                   ;; flattened result vector
```

Bindings are pairs `[name coll …]`. Each `coll` must be a vector. Bodies may be
multiple expressions (`do`-style); `for` collects the **last** expression
(flattened when there is more than one binding pair).

### `dotimes` — repeat n times

```clojure
(dotimes [i 4]
  (println i))               ;; prints 0 1 2 3; returns nil
```

Binding is `[name n]`; `n` is evaluated once. `name` runs from `0` to `n-1`.

### `while` — loop while condition is truthy

```clojure
(let [xs (vector 1 2 3)]
  (while (> (count xs) 0)
    (println (last xs))
    (pop xs)))               ;; pop removes last; prints 3 2 1
```

Expands to a `loop`/`recur`. The condition is re-evaluated every iteration.
Prefer `loop`/`recur` when you need pure functional accumulators.### Threading Macros

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

## Modules and Namespaces

```clojure
(require "lib/core" :as core)
(require "lib/math" :as math)

(defn main []
  (println (core/inc 41))
  (println (math/square 5)))
```

`require` loads a module and binds it to an alias. All public definitions (`def`, `defn`, `defstruct`, `deftype`, `extern`, `defmacro`) from the module are accessible via qualified names: `alias/name`.

Modules are isolated — two modules can define the same name without conflict. `require` also supports nested modules: a module may itself `require` other modules.

Search paths for `require`:
1. Relative to the current file (and its parent directories)
2. `lib/` in the compiler's manifest directory (standard library)
3. `target/bars-deps/*/src/` (resolved package dependencies)

If the path does not end in `.brs`, it is automatically appended.

## Testing

Use `lib/test` for suites (self-hosted and host):

```clojure
(require "lib/test" :as t)

(t/deftest test-math
  (do
    (t/is ctx (= (+ 1 2) 3) "add")
    (t/is-eq ctx 42 (* 6 7) "mul")))

(defn main []
  (let [ctx (t/suite "math")]
    (test-math ctx)
    (t/finish ctx)))   ;; non-zero exit if any assertion failed
```

See `docs/04-stdlib.md` (`lib/test.brs`) and `examples/deftest_demo.brs`.

### User macros (`defmacro`)

The self-hosted expander supports user `defmacro` in two styles:

**1. Syntax-quote templates** (most macros):

```clojure
(defmacro twice [x]
  `(+ ~x ~x))

(defmacro unless [cond body]
  `(if (not ~cond) ~body nil))
```

Unquote (`~`) and splice (`~@`) work inside `` ` `` templates. `~` evaluates
expressions at expand-time (not only symbol lookup).

**2. Expand-time interpreter** (list/cons/if/let bodies):

```clojure
(defmacro my-or [a b]
  (list (quote if) a a b))

(defmacro thrice [x]
  (let [v x]
    (list (quote *) v 3)))
```

Builtins at expand-time: `list`, `cons`, `first`, `rest`, `count`, `=`, `+`/`-`/`*`,
`not`, `symbol?`/`list?`/`vector?`, plus `if`/`let`/`do`/`quote`.

Macro definitions are compile-time only (stripped after expansion). Modules
rename `defmacro` names like `defn`, so `(require "lib/test" :as t)` +
`(t/deftest …)` works.
