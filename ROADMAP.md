# Bars — Пътна Карта (v6.0)

> Актуална към: 2026-06-05  
> Състояние: Фази 0–11 завършени. Фаза 12 в прогрес.  
> Философия: Следващите версии на компилатора се пишат на Bars.
> 
> Структура: `bootstrap/` — Rust bootstrap (замразен), `compiler/` — компилатор на Bars, `lib/` — stdlib

---

## Обобщение

Bars е работещ компилатор за системен Lisp с ownership.  
**~5000 реда Rust**, **~380 реда C runtime**, 3 backend-а, ADTs, FFI, макросистема, pattern matching, структури, колекции, REPL, build pipeline, generics, type inference, stdlib.

```
.brs файл → Reader → AST → Macros → Ownership → Type Inference → HIR Lowering → HIR Optimizations → Backend (QBE/Cranelift/LLVM) → Binary
```

---

## Фаза 0: Инфраструктура ✅

- [x] Проектна структура (Cargo, crates)
- [x] Reader: lexer + parser за S-expressions
- [x] Поддръжка на атоми, списъци `()`, вектори `[]`, keywords `:`
- [x] Коментари `;`, низове `"`
- [x] CLI скелет с `clap`

---

## Фаза 1: AST → Нативен Код ✅

- [x] AST типове (`Expr`, `Pattern`, `Program`)
- [x] QBE IR generation
- [x] Build pipeline: `.brs` → `.ssa` → binary
- [x] Базови конструкции: константи, аритметика, `let`, `if`, `defn`

---

## Фаза 2: Архитектурен Рефактор ✅

- [x] Ownership анализатор: borrow checker, move semantics, NLL, drop checking
- [x] HIR (High-level IR): `Const`, `Call`, `Load`, `Store`, `Alloc`, `Branch`, `Jump`, `Return`
- [x] Lowering pass: AST → HIR
- [x] QBE backend (HIR-based)
- [x] Cranelift JIT + AOT backend
- [x] LLVM backend (`inkwell`, зад feature gate)

---

## Фаза 3: Езикови Възможности ✅

- [x] Функции с параметри (`defn`)
- [x] Return type annotations: `(defn add [a b] -> i64 (+ a b))`
- [x] Lexical scope, рекурсия
- [x] `loop`/`recur` (TCO)
- [x] Lambda функции
- [x] Pattern matching (`match`)
- [x] Structs/records (`defstruct`, field access `.x`)
- [x] Макроси (`defmacro`, `` ` ``, `~`, `~@`)
- [x] `load` за модули

---

## Фаза 4: Runtime и Колекции ✅

- [x] Boehm GC интеграция (C runtime)
- [x] String, Vector, Map, Set
- [x] Nested collections
- [x] Runtime функции: `println`, `count`, `get`, `push`, `map-set`, `set-add`
- [x] Pretty-print чрез `bars_print_any_i64`

---

## Фаза 5: REPL, CLI, Build Pipeline ✅

- [x] `bars run file.brs` (3 backend-а)
- [x] `bars check file.brs` (ownership + types)
- [x] `bars read file.brs` (AST dump)
- [x] `bars repl` — history, multi-line, pretty-print
- [x] `bars build file.brs -o binary`
- [x] REPL команди: `:quit`, `:help`, `:ast`, `:type`
- [x] Cranelift AOT string literals чрез `declare_data`/`define_data` (fix за self-hosting)

---

## Фаза 6: TCO и Оптимизации ✅

- [x] HIR TailCall terminator
- [x] Tail Call Recognition pass
- [x] HIR-level constant folding
- [x] Dead block elimination
- [x] Tail-recursive `sum` и `factorial`

---

## Фаза 7: Generics — Implicit Polymorphism ✅

- [x] Let-polymorphism / generalization в type inference
- [x] `instantiate` с fresh type vars
- [x] Type checking в compilation pipeline
- [x] Recursive functions support
- [x] Forward-referenced functions
- [x] Pattern match bindings в type environment
- [x] Generic `(defn id [x] x)` работи за i64, f64, bool, string, vector

---

## Фаза 8: ADT — Algebraic Data Types ✅

- [x] `(deftype Option [Some i64] [None])` синтаксис
- [x] `(deftype Result [Ok i64] [Err i64])`
- [x] Конструктори като функции (Some, None, Ok, Err)
- [x] Pattern matching с варианти по главна буква
- [x] Exhaustiveness checking в `match`
- [x] `Option`/`Result` в stdlib (`lib/adt.brs`)

---

## Фаза 9: FFI — Foreign Function Interface ✅

- [x] `(extern "putchar" [c i64] -> i64)` синтаксис
- [x] HIR `Func` има `is_extern`/`c_name` полета
- [x] QBE: пропуска body за extern, линкер резолва от libc
- [x] Cranelift: `Linkage::Import` за extern функции
- [x] LLVM: само declare без define

---

## Фаза 10: Минимална Stdlib ✅

- [x] Math: `sqrt`, `pow`, `abs` — libm wrappers в C runtime
- [x] String ops: `str-count`, `str-concat`, `str-trim`, `str-substring`, `str-split`, `str-join` — C runtime
- [x] I/O: `slurp`, `spit` — C runtime файлов I/O
- [x] Тестови helper: `assert` macro (`lib/test.brs`)
- [x] Error handling: `Option`/`Result` ADTs (`lib/adt.brs`)
- [x] Higher-order functions: `map`, `filter`, `reduce` — inlined в HIR lowering, работят с lambdas във всички backend-и

---

## Фаза 11: Пакетна Система ✅ WORKSPACE CRATE

> **Отделен crate `bars-pkg` в същия workspace.** CLI командите са интегрирани в `bars`.

- [x] `Bars.toml` манифест формат
- [x] `bars new my-project` — scaffold проект
- [x] `bars add <package>` — добавя dependency
- [x] Git-based и path разрешаване на dependencies
- [x] Lock файл `Bars.lock`
- [ ] Central registry (бъдеще)
- [x] Модули и namespaces: `(require "http" :as http)`

---

## Бъдещи подобрения (компилатор) 📋

- [x] Generic ADTs: `(deftype Option [Some T] [None])` — работят в type inference, stdlib обновен
- [x] Още string операции: `split`, `join`, `trim`, `substring`
- [x] `--release` флаг за всички backend-ове (QBE: `cc -O2`, Cranelift: `speed_and_size`, LLVM: `Aggressive`)
- [x] Подобрени error messages — цветни, с source context, точни spans
- [x] LSP сървър — hover (type info), completion, go-to-definition, diagnostics
- [ ] Debugger интеграция
- [ ] Cross-compilation

## Фаза 12: Self-Hosting 🚧

- [x] Stage 0: Подготовка — string ops, CLI args, `exit` ✅
- [x] Stage 1: Self-hosted Reader (`compiler/reader.brs`) ✅
- [x] Stage 2: Self-hosted HIR Lowering (`compiler/hir.brs`) ✅
- [x] Stage 3: Self-hosted QBE Codegen (`compiler/codegen/qbe.brs`) ✅
- [x] Stage 4: Self-hosted Build Pipeline (`compiler/build.brs`) ✅
- [x] Stage 5: Bootstrap — компилиране през Rust host toolchain ✅
- [ ] Stage 5a: Self-hosted компилаторът компилира произволен `.brs` файл
- [ ] Stage 5b: Identity test — Rust и Bars компилатори произвеждат идентичен output
- [ ] Stage 5c: Замяна на Rust host с Bars self-hosted в CI

**Текущо състояние:** `bars build --backend cranelift compiler/build.brs` произвежда работещ binary, който се изпълнява без segfault. Остава дебъгване на `compile-file` pipeline в self-hosted версията.

---

## Легенда

| Символ | Значение |
|--------|----------|
| ✅ | Завършено |
| 🚧 | В прогрес |
| 📋 | Планирано |

---

*Версия: 5.0 | Актуализирано: 2026-06-03*
