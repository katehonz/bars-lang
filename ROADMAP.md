# Bars — Системен Lisp с Ownership

> **Bars** (барс) — Снежната леопард. Бърз, независим, опасен.
>
> Системен език за програмиране със синтаксис на Clojure, ownership като Rust (по-лек), и компилация до нативен код през QBE / Cranelift / LLVM.

---

## Философия

```
Clojure синтаксис  +  Rust памет  +  C скорост  =  Bars
```

- **Скобите показват scope** — естествено съответстват на lifetime-и.
- **Ownership без borrow checker ад** — по-леки правила, позволяващи по-бърз цикъл.
- **Множество бекенди** — QBE за debug/AOT, Cranelift за JIT/REPL, LLVM за release.
- **Zero-cost FFI** — директен достъп до C ABI.
- **.brs** — разширение на изходните файлове.

---

## Архитектура

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   .brs      │────→│   Reader    │────→│   AST/HIR   │────→│   Ownership │
│   файл      │     │  (S-exprs)  │     │  + Macros   │     │   Analysis  │
└─────────────┘     └─────────────┘     └─────────────┘     └──────┬──────┘
                                                                    │
┌───────────────────────────────────────────────────────────────────┼──────┐
│                           BACKENDS                                │      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │      │
│  │   QBE IR    │  │  Cranelift  │  │    LLVM     │◄──────────────┘      │
│  │  (qbe-rs)   │  │   (JIT/AOT) │  │  (inkwell)  │                      │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                      │
│         │                │                │                             │
│         ▼                ▼                ▼                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                      │
│  │  qbe/cc     │  │   JIT mem   │  │   llc/opt   │                      │
│  └─────────────┘  └─────────────┘  └─────────────┘                      │
└─────────────────────────────────────────────────────────────────────────┘
         │
         ▼
  ┌─────────────┐
  │  Runtime    │
  │  (Boehm GC  │
  │  + libc)    │
  └─────────────┘
```

---

## Технологичен Стек

| Компонент | Технология | Алтернатива | Статус |
|-----------|-----------|-------------|--------|
| Език | Rust | — | ✅ |
| Парсер | `nom` / ръчен | `lalrpop` | 🚧 |
| CLI | `clap` | ръчен | 🚧 |
| REPL | `rustyline` | ръчен | 🚧 |
| **QBE Backend** | `qbe-rs` | — | 🚧 |
| **Cranelift Backend** | `cranelift-codegen` + `cranelift-module` | — | 📋 |
| **LLVM Backend** | `inkwell` | `llvm-sys` | 📋 |
| GC | Boehm GC | Собствен RC | 📋 |
| Типова система | Hindley-Milner + Ownership | — | 📋 |

**Легенда:** ✅ Готов | 🚧 В разработка | 📋 Планирано

---

## Уникални Характеристики

### 1. Лек Ownership (Bars Ownership)

За разлика от Rust, където borrow checker е строг и понякога фрустриращ, Bars използва **по-лека модел**:

```clojure
;; Преместване (move) — по подразбиране за heap стойности
(def buf (buffer/new 1024))      ; owns buf
(buffer/fill buf 0)              ; OK — ползваме го
(let [b2 buf]                    ; move: buf вече е невалиден
  (buffer/fill b2 1))
;; (buffer/fill buf 2)           ; ГРЕШКА: buf е moved

;; Borrow — препратка без прехвърляне на ownership
(defn process [^buf data]
  ; ^buf казва: "borrow this"
  (buffer/read data 0))

(process buf)                    ; OK — buf остава валиден
```

**Правила (опростени спрямо Rust):**
- Всеки обект има един owner.
- При присвояване на променлива: по подразбиране се `move`-ва (като Rust).
- За borrow използваш `^` (caret) — аналог на `&` в Rust.
- Mutable borrow: `^mut` — аналог на `&mut`.
- **Няма lifetime annotations** — компилаторът използва по-прости эвристики.
- **GC fallback** — ако ownership системата не може да докаже безопасност, обектът отива в GC хипа.

### 2. Хибридна Памет

```
Stack-allocated    →  Локални примитиви, small structs, borrowed refs
Ownership-managed  →  Буфери, файлови handle-ове, линейни типове
GC-managed         →  Колекции, графи, циклични структури, closures
```

```clojure
;; Stack — автоматично
(let [x 42] ...)

;; Ownership — ръчно управление
(def file (fs/open "data.txt"))
(fs/read file)
(fs/close file)                  ; ясно освобождаване

;; GC — автоматично
(def data {:a [1 2 3] :b {:c 2}})
```

### 3. Множество Бекенди

| Режим | Бекенд | Use Case |
|-------|--------|----------|
| `bars build` | QBE | Бърза AOT компилация, small binaries |
| `bars repl` | Cranelift | JIT за интерактивна разработка |
| `bars build --release` | LLVM | Максимални оптимизации |
| `bars run` | QBE (C backend) | Бърз цикъл compile-run-debug |

---

## Фази на Разработка

### Фаза 0: Скелет + Reader (Седмица 1)

**Цел:** Работеща инфраструктура и парсване на `.brs` файлове.

```bash
cargo new bars
cd bars
cargo add qbe clap rustyline nom thiserror anyhow
```

**Задачи:**
- [x] Инициализиране на проекта
- [x] Структура на crates: `bars-reader`, `bars-ast`, `bars-hir`, `bars-qbe`, `bars-cli`
- [ ] Lexer: токени за S-expressions
- [ ] Reader: парсване на атоми, списъци `()`, вектори `[]`, maps `{}`
- [ ] Поддръжка на коментари `;`, строки `"`, keywords `:`
- [ ] CLI: `bars run file.brs`, `bars build file.brs`, `bars repl`
- [ ] Грешки с line/column информация

**Резултат:** `bars read file.brs` → pretty-printed AST.

---

### Фаза 1: Базов AST → QBE IR (Седмица 2-3)

**Цел:** Компилация на прости изрази до работещи бинарни файлове.

**Поддържани конструкции:**
```clojure
42                   ; константи
(+ 1 2)              ; аритметика
(let [x 5] x)        ; локални променливи
(if true 1 2)        ; условно изпълнение
(defn add [a b] (+ a b))   ; функции
```

**Типова система (фаза 1):**
- `i64`, `f64`, `bool`
- Автоматично type inference за locals

**Примерна компилация:**
```clojure
(defn main []
  (let [x 5]
    (+ x 1)))
```
→ QBE IR:
```qbe
function w $main() {
@start
    %x =w copy 5
    %t =w add %x, 1
    ret %t
}
```

**Задачи:**
- [ ] AST типове (`Expr`, `Stmt`, `FnDef`)
- [ ] Типов inference за примитиви
- [ ] QBE IR generation (`qbe-rs`)
- [ ] `main` функция и entry point
- [ ] Build pipeline: `.brs` → `.ssa` → `.c` → binary

**Резултат:** Можеш да компилираш `(+ 1 2)` до изпълним файл.

---

### Фаза 2: Функции, Scope, Рекурсия (Седмица 4)

**Цел:** Пълноценни функции и lexical scope.

```clojure
(defn factorial [n]
  (if (<= n 1)
    1
    (* n (factorial (- n 1)))))

(defn main []
  (println (factorial 5)))
```

**Задачи:**
- [ ] `defn` с параметри
- [ ] Function calls и return стойности
- [ ] Lexical scope (nested functions)
- [ ] Tail call optimization (TCO) — опционално
- [ ] Forward declarations

**Резултат:** Работещи рекурсивни функции.

---

### Фаза 3: Ownership Анализатор (Седмица 5-6)

**Цел:** Лека ownership система.

```clojure
(defn use-buffer [^buf b]
  (buffer/read b 0))

(defn main []
  (def data (buffer/new 16))
  (use-buffer data)              ; borrow — OK
  (use-buffer data))             ; borrow отново — OK
  ;; (buffer/free data)          ; освобождаване
```

**Задачи:**
- [ ] Borrow checker с `^` и `^mut`
- [ ] Move semantics по подразбиране
- [ ] Проверка за use-after-move
- [ ] Проверка за double-free
- [ ] Drop/close семантика за ресурси
- [ ] FFI safety за C указатели

**Резултат:** Компилаторът хваща грешки в паметта.

---

### Фаза 4: Runtime + GC (Седмица 7-8)

**Цел:** Колекции и garbage collection.

**Типова йерархия:**
```
Value
├── Primitive (i64, f64, bool)
├── String (pointer + length)
├── Vector (динамичен масив / HAMT)
├── Map (HAMT hash map)
└── Function (closure)
```

**Задачи:**
- [ ] Интеграция с Boehm GC
- [ ] `String`, `Vector`, `Map` runtime типове
- [ ] Memory layout за boxed стойности
- [ ] Runtime функции: `println`, `str`, `count`, `nth`
- [ ] GC roots от stack-а

**Резултат:** `(println "hello, bars!")` работи. Колекции са GC-управлявани.

---

### Фаза 5: REPL с Cranelift JIT (Седмица 9-10)

**Цел:** Интерактивен цикъл с JIT.

```bash
$ bars repl
bars> (+ 1 2)
3
bars> (defn square [x] (* x x))
#'square
bars> (square 7)
49
bars> (def nums [1 2 3 4])
#'nums
bars> (map square nums)
[1 4 9 16]
```

**Задачи:**
- [ ] Read-Eval-Print Loop с `rustyline`
- [ ] Cranelift JIT backend
- [ ] Environment за дефинирани символи
- [ ] Повторно дефиниране на функции
- [ ] Error handling без crash
- [ ] Command history

**Резултат:** Интерактивен Lisp REPL.

---

### Фаза 6: Макроси (Седмица 11-13)

**Цел:** Хомоиконични макроси като Clojure.

```clojure
(defmacro when [cond & body]
  `(if ~cond
     (do ~@body)
     nil))

(defmacro unless [cond & body]
  `(if (not ~cond)
     (do ~@body)
     nil))
```

**Задачи:**
- [ ] `quote` форма
- [ ] `syntax-quote` (`` ` ``)
- [ ] `unquote` (`~`)
- [ ] `unquote-splicing` (`~@`)
- [ ] `defmacro` форма
- [ ] Macro expansion phase
- [ ] Hygiene (опционално)

**Резултат:** Пълноценна макросистема.

---

### Фаза 7: LLVM Backend + Оптимизации (Седмица 14+)

**Цел:** Release builds с LLVM.

**Задачи:**
- [ ] LLVM IR generation чрез `inkwell`
- [ ] LLVM оптимизационни passes
- [ ] Inline функции
- [ ] Constant folding
- [ ] Dead code elimination
- [ ] Cross-compilation

---

## Структура на Проекта

```
bars/
├── Cargo.toml
├── Cargo.lock
├── README.md
├── ROADMAP.md
├── examples/
│   ├── hello.brs
│   ├── math.brs
│   ├── ownership.brs
│   └── fib.brs
├── tests/
│   ├── reader_tests.rs
│   ├── compiler_tests.rs
│   └── ownership_tests.rs
└── src/
    ├── main.rs              # CLI entry point
    ├── lib.rs               # Library API
    ├── repl.rs              # REPL loop
    ├── reader/
    │   ├── mod.rs           # Публичен API
    │   ├── lexer.rs         # Tokenizer
    │   └── parser.rs        # S-expr parser
    ├── ast/
    │   ├── mod.rs           # AST типове
    │   └── display.rs       # Pretty print
    ├── hir/
    │   ├── mod.rs           # High-level IR
    │   ├── ownership.rs     # Ownership analysis
    │   └── types.rs         # Type system
    ├── backends/
    │   ├── mod.rs           # Backend trait
    │   ├── qbe/
    │   │   ├── mod.rs       # QBE IR generation
    │   │   └── codegen.rs   # Code generation
    │   ├── cranelift/
    │   │   ├── mod.rs       # Cranelift JIT/AOT
    │   │   └── jit.rs       # JIT compilation
    │   └── llvm/
    │       ├── mod.rs       # LLVM IR generation
    │       └── opt.rs       # Optimization passes
    ├── runtime/
    │   ├── mod.rs           # Runtime API
    │   ├── gc.rs            # Boehm GC wrapper
    │   ├── string.rs        # String ops
    │   ├── vector.rs        # Vector ops
    │   └── map.rs           # Map ops
    └── macro/
        ├── mod.rs           # Macro expansion
        └── expander.rs      # Expansion logic
```

---

## Примерен Workflow

### Компилация

```bash
# Debug build (QBE)
bars build examples/hello.brs
./hello

# Release build (LLVM)
bars build --release examples/hello.brs
./hello

# Run директно
bars run examples/fib.brs

# REPL
bars repl
```

### Примерен `.brs` файл

```clojure
;; examples/hello.brs
(defn main []
  (println "Здравей, свят!"))
```

```clojure
;; examples/ownership.brs
(defn process [^buf data]
  (buffer/read data 0))

(defn main []
  (def b (buffer/new 16))
  (process b)
  (buffer/free b))
```

---

## Вдъхновение

- **Clojure** — синтаксис, макроси, персистентни структури
- **Rust** — ownership, безопасност, zero-cost abstractions
- **QBE** — простота, SSA, бърза компилация
- **Cranelift** — JIT, бърз кодоген
- **Carp** — Lisp с Rust-подобна типова система
- **Jank** — Clojure на C++
- **Bara Lang** (_bara/) — Clojure диалект върху Nim, нашето вдъхновение

---

## Лиценз

MIT или Apache-2.0

---

*Създадено: 2026-06-02*  
*Версия на плана: 2.0 — Bars*
