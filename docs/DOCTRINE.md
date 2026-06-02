# The Bars Doctrine

## Preamble

We hold these truths to be self-evident:

1. **Lisp syntax is the most powerful syntax ever invented.** S-expressions are not a bug — they are the feature. Code is data. Data is code.
2. **Clojure proved Lisp scales to industry.** Millions of lines of production code. Fortune 500 companies. Real money. Real developers.
3. **Systems programming should not require C syntax.** Memory safety, native performance, and Lisp macros are not mutually exclusive.
4. **Rust proved ownership works.** But it also proved that lifetime annotations are a tax most developers refuse to pay.
5. **No existing language combines all three.** Until now.

This is the doctrine of Bars. Read it. Understand it. Build with it.

---

## Article I: The Parentheses Are the Scope

In Bars, every pair of parentheses `(` `)` is a **scope boundary**. This is not syntax sugar. It is the foundation of memory management.

```clojure
(let [file (open "data.txt")]     ;; scope begins — file is owned here
  (read file)                      ;; borrow
  (process file))                  ;; borrow again
;; scope ends — file is automatically closed
```

Because Lisp is *explicitly nested*, ownership analysis is **local and linear**. We never track lifetimes across complex control flow graphs. The structure of the code **is** the lifetime graph.

**This is why Bars beats Rust on ergonomics.** Rust's borrow checker is global and conservative. It rejects valid programs to ensure safety. Bars' checker is local and permissive — because the scopes are explicit, there is no ambiguity about when a value dies.

### The Rule

> If you can see the closing parenthesis, you know exactly when the value dies.

---

## Article II: Clojure Is the Industrial Standard

Clojure is not an academic language. It is not a toy. It is the **industrial standard for Lisp**.

- Datomic, Pedestal, Ring, core.async — production systems handling billions of dollars
- Developers who *choose* parentheses because they make them more productive
- A REPL-driven culture where code is shaped in real time

But Clojure made a trade-off: the JVM. Great for web services. Unacceptable for:
- OS kernels
- Device drivers
- Game engines
- Embedded systems
- 50KB command-line tools

**Bars keeps everything that makes Clojure great. It removes the JVM.**

| What We Keep | What We Add |
|-------------|-------------|
| S-expression syntax | Native compilation (QBE AOT + Cranelift JIT) |
| Homoiconic macros | Ownership checking (no lifetime annotations) |
| REPL-driven development | Zero-cost C FFI |
| Vectors `[]` and maps `{}` | Optional GC (Boehm) |
| Keywords `:foo` | `loop` / `recur` tail recursion |
| Immutable-by-default | Small binaries (no 200MB runtime) |

---

## Article III: The First Serious Attempt

Others have tried. All have failed or surrendered.

| Language | Lisp | Native | Ownership | Status |
|----------|------|--------|-----------|--------|
| Common Lisp | ✅ | ✅ | ❌ | Declining, no memory safety |
| Scheme | ✅ | ❌ | ❌ | Academic |
| Clojure | ✅ | ❌ | ❌ | JVM-bound |
| Racket | ✅ | ❌ | ❌ | Educational |
| Carp | ✅ | ✅ | ✅ | **Abandoned** |
| Rust | ❌ | ✅ | ✅ | No macros, lifetime hell |
| Zig | ❌ | ✅ | ✅ | No Lisp syntax, no macros |
| Jai | ❌ | ✅ | ✅ | Closed source |
| **Bars** | ✅ | ✅ | ✅ | **Alive and building** |

Carp proved the concept. Bars executes it.

---

## Article IV: Memory Is a Hierarchy, Not a Religion

Bars rejects the false dichotomy of "GC vs manual memory management." Memory is a hierarchy:

| Tier | Management | Use When |
|------|-----------|----------|
| **Stack** | Automatic | Primitives, small structs, hot loops |
| **Ownership** | Compile-time checked | Files, sockets, custom resources |
| **GC** | Boehm | Vectors, maps, strings, complex graphs |

You choose the tool for the job. No GC pauses in your renderer. No manual memory management in your config parser.

### Copy Types

Primitive types (`i64`, `bool`, `f64`) are **Copy** — passed by value, no move semantics, no overhead:

```clojure
(let [x 42]
  (let [y x]          ;; x is copied, not moved
    (+ x y)))         ;; both valid → 84
```

Complex types (`Vector`, `Map`, `String`) are **Move** — ownership transfers:

```clojure
(let [v (vector 1 2)]
  (let [w v]          ;; v is moved to w
    v))               ;; ERROR: use after move
```

This is intuitive. Numbers copy. Objects move.

---

## Article V: Compilers Are a Toolchain, Not a Religion

Bars does not worship LLVM. LLVM is powerful but slow. Bars uses the right tool for each job:

| Backend | Use Case | Compile Speed | Runtime Speed |
|---------|----------|---------------|---------------|
| **QBE** | AOT debug/release builds | **Seconds** | Good |
| **Cranelift** | JIT / REPL | **Instant** | Good |
| **LLVM** | Optimized release (planned) | Minutes | Best |

QBE compiles **100x faster than LLVM** while producing code within 10-15% of performance. For most development, this is the sweet spot.

Cranelift gives us a **true JIT REPL** — evaluate expressions in milliseconds, not seconds.

---

## Article VI: Macros Must Be Homoiconic

Procedural macros are a workaround. Textual macros (`#define`) are a hack. True macros manipulate the AST directly because **the AST is the syntax**.

```clojure
;; In Bars, this IS the AST
(when (ready?)
  (launch)
  (log "started"))

;; Expands to:
(if (ready?)
  (do (launch)
      (log "started"))
  nil)
```

No macro expansion phase that runs before parsing. No separate syntax. The code you write **is** the data structure the compiler sees.

This is why Lisp macros are more powerful than C++ templates, Rust proc macros, or Zig comptime. They can introspect, transform, and generate code at the semantic level.

---

## Article VII: The Target Programmer

Bars is for the programmer who:

- **Thinks in S-expressions** — nested structure, functional composition, immutable data
- **Needs native performance** — game loops, system daemons, embedded firmware
- **Wants memory safety** — no segfaults, no use-after-free, no data races
- **Refuses to give up macros** — code that writes code
- **Hates waiting for LLVM** — fast compilation is a feature
- **Loves the REPL** — shape code interactively, see results instantly

This programmer has had no home. Until now.

---

## Article VIII: We Will Win

### vs Rust
> *"Same safety, 10x faster compilation, no lifetime book required."*

Bars gives you ownership without the learning cliff. The parentheses make the scopes explicit. The checker is local, not global. You get safety in hours, not months.

### vs Clojure
> *"Clojure without the JVM."*

Same syntax. Same macros. Same REPL. But your binary is 50KB, starts in 10ms, and can talk to C without JNI overhead.

### vs C/Zig
> *"Systems programming with real macros."*

You want to generate code based on a schema? In Bars, your macro sees the AST as a data structure. In C, you use the preprocessor. In Zig, you use comptime — powerful, but not homoiconic.

### vs Carp
> *"Carp was the proof. Bars is the product."*

Carp showed it could work. Then it stopped. Bars takes the same vision — Lisp + ownership + native — and executes it with modern backends, active development, and a real standard library.

---

## Article IX: This Is Only the Beginning

Bars v0.1.0 has:
- ✅ Reader, AST, ownership checker
- ✅ QBE AOT backend
- ✅ Cranelift JIT REPL
- ✅ Built-in macros (`when`, `unless`, `cond`, `->`, `->>`)
- ✅ `loop` / `recur`
- ✅ Standard library
- ✅ `load` system
- ✅ 39 passing tests

What comes next:
- 🚧 User-defined macros (`defmacro` + `syntax-quote`)
- 🚧 Type inference
- 🚧 LLVM backend for release builds
- 🚧 WASM target
- 🚧 Package manager
- 🚧 LSP / IDE support

---

## Final Article: Join or Build

Bars is open source. The code is at [codeberg.org/bars-lang/bars-lang](https://codeberg.org/bars-lang/bars-lang).

If you believe that:
- Parentheses are a feature, not a bug
- Memory safety should not require a PhD
- Native performance and Lisp macros belong together
- Compilation should be measured in seconds, not minutes

Then Bars is your language. **Join or build.**

*The first serious attempt at a systems Lisp is here. It will not be the last. But it will be the one that proves it works.*

---

**Adopted this day by the Bars language project.**

*Bars — the Snow Leopard. Fast, independent, dangerous.*
