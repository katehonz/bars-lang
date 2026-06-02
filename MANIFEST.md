# The Bars Manifesto

## Preamble: Enough

Enough.

Enough with new languages every three years. Enough with 200-megabyte JVMs that boot slower than an operating system. Enough with frameworks that require months to learn, only to become obsolete before you ship. Enough with syntaxes that change how you write but never how you think.

We live in an era where programming is more fragmented than ever. A web developer must know TypeScript, Python, SQL, Docker, Kubernetes, three cloud providers, and fifteen configuration formats just to deploy a contact form. A systems programmer spends five years learning Rust only to discover that the borrow checker rejects valid programs due to conservative analysis. AI assistants are trained on billions of lines of code across hundreds of languages and thousands of frameworks — yet they cannot generate optimal code in any single one, because every language carries its own abstraction model, its own runtime, its own package manager, its own cult.

This is not progress. This is control.

Corporations do not want one language. They want twenty. Because when a programmer must learn a new ecosystem every two years, they never reach depth. They never see the patterns beneath the syntax. They remain interchangeable parts in a machine that produces software with an expiration date.

**Bars is the answer.**

One syntax. All levels of abstraction. From microcontroller firmware to functional web servers. From system drivers to AI inference engines. From 50-kilobyte command-line utilities to operating systems.

No more "the right language for the job." The job adapts to the language. Because the language is powerful enough.

---

## Article I: The Crisis of Languages

### The Curse of Abundance

In 1958, John McCarthy created Lisp. One language. One syntax. One paradigm that covered everything — from symbolic mathematics to artificial intelligence. By 1969, Lisp was already writing code that wrote code.

Today, seventy years later, we have:
- JavaScript for web frontends
- TypeScript for "type-safe" JavaScript
- Python for data science
- Go for microservices
- Rust for systems programming
- Java for enterprise applications
- C# for games and Windows
- Swift for iOS
- Kotlin for Android
- Zig for "better C"
- Julia for scientific computing
- Haskell for functional purists
- Elm for functional frontends
- Elixir for concurrency
- Dart for Flutter
- Lua for embedding
- and more, and more, and more...

Every one of these languages has:
- Its own syntax
- Its own runtime
- Its own package manager
- Its own build system
- Its own debugger
- Its own profiler
- Its own LSP server
- Its own cult of followers who will convince you that their language is "the right one"

The result? A programmer who spends 40% of their time context-switching between languages and ecosystems. Instead of thinking about problems, they think about syntax. Instead of optimizing algorithms, they optimize webpack configurations.

### AI Cannot Afford This

Large language models are trained on billions of lines of code. But that code is fragmented across hundreds of languages, thousands of frameworks, millions of versions. When you ask an AI to write "a systems program," it must choose between C, Rust, Zig, Go, Nim — and in every case, it will produce code that is average but never optimal.

Because optimal code requires *understanding* the problem, not *recalling* patterns. And understanding requires a unified paradigm in which the mind — human or artificial — can think sequentially.

**One language = one mental model = deeper understanding = better code.**

When an AI knows it is always writing S-expressions, whether compiling a kernel or a web API, it can focus its capacity on semantics rather than syntax. The human programmer can transfer all their knowledge from one project to another without switching mental models.

### Why Now? Because the Weapons Have Existed for Decades

S-expressions have existed since 1958. The Boehm garbage collector has existed since 1988. QBE has existed since 2015. Cranelift has existed since 2016. All the components for "the perfect language" have been available for the last 10–20 years.

So why did no one combine them?

Because corporations do not want one language. They want fragmentation. The JVM, .NET, and Node are not technologies. They are *control mechanisms*.

---

## Article II: The Parentheses Are the Scope

```clojure
(let [file (open "data.txt")]     ;; scope begins — file is owned here
  (read file)                      ;; borrow
  (process file))                  ;; borrow again
;; scope ends — file is automatically closed
```

In Bars, every pair of parentheses `(` `)` is a **scope boundary**. This is not syntax sugar. It is the foundation of memory management.

Lisp is *explicitly nested*. Therefore, ownership analysis is **local and linear**. We never track lifetimes across complex control-flow graphs. The structure of the code **is** the lifetime graph.

**The Rule:**

> If you can see the closing parenthesis, you know exactly when the value dies.

Rust rejects valid programs to ensure safety. Its borrow checker is global and conservative. Bars is local and permissive — because the scopes are explicit, there is no ambiguity about when a value dies.

The parentheses are not a bug. They are the *feature* that makes static analysis trivial.

---

## Article III: The Corporate Cage

### JVM, .NET, Node — Platforms of Control

When you write Java, you are not writing code. You are writing bytecode that executes inside a virtual machine owned by Oracle. When you write C#, you write for a runtime that Microsoft controls. When you write Node.js, you are dependent on the npm ecosystem, which can change tomorrow.

These "platforms" are not engineering solutions. They are **business models**.

| Platform | Runtime Size | Startup Time | Dependencies | Control |
|----------|-------------|--------------|--------------|---------|
| JVM | 150–300 MB | 2–10 seconds | JDK, Maven, Gradle | Oracle |
| .NET Runtime | 100–200 MB | 1–5 seconds | .NET SDK, NuGet | Microsoft |
| Node.js | 50–100 MB | 0.5–2 seconds | npm, 1000+ modules | OpenJS Foundation |
| **Bars (native)** | **0 MB** | **10 ms** | **libc, libgc** | **You** |

Two hundred megabytes of runtime to print "Hello, World." This is normalized madness.

### Interchangeable Parts, Not Thinking People

Corporations want programmers who know Spring Boot, not programmers who understand S-expressions. Because the Spring Boot programmer is in a cage — they cannot leave the ecosystem, because all their knowledge is specific to that platform. They are *vendor lock-in* in human form.

The Lisp programmer is different. The parentheses give them the ability to think in abstractions that are independent of any platform. Once you see that code is data and data is code, you cannot return to Java/C# thinking. You see the cage.

And that is why corporations fund TypeScript, Rust, and Go — languages with complex syntax that create deep specializations. But they do not fund Lisp. Because Lisp makes programmers independent.

**Bars breaks out of the cage.**

---

## Article IV: Memory Is a Hierarchy, Not a Religion

Bars rejects the false dichotomy of "GC versus manual memory management." Memory is a hierarchy:

| Tier | Management | When to Use |
|------|-----------|-------------|
| **Stack** | Automatic | Primitives, small structs, hot loops |
| **Ownership** | Compile-time checked | Files, sockets, custom resources |
| **GC** | Boehm | Vectors, maps, strings, complex graphs |

You choose the tool for the job. No GC pauses in your renderer. No manual memory management in your configuration parser.

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

## Article V: The Compiler Is a Toolkit, Not a Religion

Bars does not worship LLVM. LLVM is powerful but slow. Bars uses the right tool for each job:

| Backend | Use Case | Compile Speed | Runtime Speed |
|---------|----------|---------------|---------------|
| **QBE** | AOT debug/release builds | **Seconds** | Good |
| **Cranelift** | JIT / REPL | **Instant** | Good |
| **LLVM** | Optimized release (planned) | Minutes | Best |

QBE compiles **100× faster than LLVM** while producing code within 10–15% of performance. For most development, this is the sweet spot.

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

## Article VII: One Syntax, Infinite Possibilities

### From Firmware to Web

```clojure
;; Microcontroller firmware — memory is manual, no GC
(defn init-gpio []
  (let [gpio-base 0x40020000]
    (store-word (+ gpio-base 0x00) 0x55555555)  ;; mode register
    (store-word (+ gpio-base 0x14) 0xFF)))       ;; set pins

;; Web server — GC handles requests
(defn handle-request [req]
  (let [body (parse-json (get-body req))]
    (match (get-route req)
      "/api/users" (json-response (get-users body))
      "/api/posts" (json-response (get-posts body))
      _ (error-response 404))))

;; AI inference — functional composition
(defn neural-layer [weights inputs]
  (->> (zip weights inputs)
       (map (fn [[w i]] (* w i)))
       (reduce + 0)
       (relu)))
```

The same syntax. The same parentheses. The same paradigm. From bare-metal registers to functional tensor composition.

### For AI Assistants

When an AI assistant knows only one syntax, it can focus all its knowledge on solving problems instead of translating between languages. It does not need to know that in Rust `if` is an expression but in Go it is a statement. That in Python indentation is significant but in C it is not. That in Haskell `=` is definition but in Java it is assignment.

One syntax = one mental model = deeper understanding = better code.

---

## Article VIII: The Target Programmer

Bars is for the programmer who:

- **Thinks in S-expressions** — nested structure, functional composition, immutable data
- **Needs native performance** — game loops, system daemons, embedded firmware
- **Wants memory safety** — no segfaults, no use-after-free, no data races
- **Refuses to give up macros** — code that writes code
- **Hates waiting for LLVM** — fast compilation is a feature
- **Loves the REPL** — shape code interactively, see results instantly

This programmer has had no home. Until now.

---

## Article IX: We Will Win

### vs Rust
> *"Same safety, 10× faster compilation, no lifetime textbook required."*

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

## Article X: This Is Only the Beginning

Bars v0.1.0 has:
- ✅ Reader, AST, ownership checker
- ✅ QBE AOT backend
- ✅ Cranelift JIT REPL
- ✅ Built-in macros (`when`, `unless`, `cond`, `->`, `->>`)
- ✅ `loop` / `recur`
- ✅ Standard library
- ✅ `load` system
- ✅ HIR optimizations (constant folding, dead code elimination)
- ✅ 46 passing tests

What comes next:
- 🚧 User-defined macros (`defmacro` + `syntax-quote`)
- 🚧 Type inference
- 🚧 LLVM backend for release builds
- 🚧 WASM target
- 🚧 Package manager
- 🚧 LSP / IDE support
- 🚧 Self-hosted compiler

---

## Final Article: Join or Build

Bars is open source. The code is at [codeberg.org/bars-lang/bars-lang](https://codeberg.org/bars-lang/bars-lang).

If you believe that:
- Parentheses are a feature, not a bug
- Memory safety should not require a PhD
- Native performance and Lisp macros belong together
- Compilation should be measured in seconds, not minutes
- One language is enough for everything
- Programmers are not interchangeable parts
- AI deserves a unified mental model

Then Bars is your language. **Join or build.**

*The first serious attempt at a systems Lisp is here. It will not be the last. But it will be the one that proves it works.*

---

**Adopted this day by the Bars language project.**

*Bars — the wild cat of Russia. Fast, independent, dangerous.*
