# Bars — Пътна Карта (v6.0)

> Актуална към: 2026-07-28  
> Състояние: Фази 0–14 готови. Фаза 15.1 — HTTP client; Фаза 16 bugfixes ✅.  
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
- [x] Debugger интеграция — `BARS_DEBUG=1` (DWARF + GDB/LLDB); `BARS_PROFILE=1` / `BARS_TIMINGS=1`
- [x] Cross-compilation — `BARS_TARGET` / `--target` (host uname, aarch64, wasm32; auto runtime)
- [x] `bars-self check` + `BARS_RELEASE=1` (QoL 14.6)
- [x] TCP networking — `lib/net.brs` + runtime sockets (14.7)
- [x] HTTP/1.1 client — `lib/http.brs` over TCP (15.1; no TLS)

## Фаза 12: Self-Hosting ✅

- [x] Stage 0–5: Reader, HIR, Build, bootstrap via Rust host ✅
- [x] Stage 6: Ownership checker (`compiler/ownership.brs`) ✅ — не е в pipeline
- [x] Stage 7: LLVM backend (`compiler/codegen/llvm.brs`) ✅
- [x] Stage 8: Macro system (`compiler/macros.brs`) ✅ — в pipeline
- [x] Stage 9: Module framework (`compiler/modules.brs`) ✅ — require + rename + `.brs` paths
- [x] Stage 10: `.brs` → HIR → `.ll` → clang → binary ✅
- [x] Stage 10b: Self-compilation Gen1→Gen2→Gen3→Gen4 ✅
- [x] Stage 10c: Identity test — Gen3.ll == Gen4.ll fixed point ✅
- [x] Stage 10e: Rust bootstrap frozen (`bootstrap/FROZEN.md`, `make bars-self`) ✅
- [x] Stage 10d: types + ownership wired in `build.brs` (soft types; light NLL ownership ON)
- [x] Phase 13.2: self-host error messages (`error: kind:`, parse unclosed, usage/exit codes)
- [x] Phase 13.2b: parse spans — `line:col` + `--> file:line:col` on reader errors
- [x] Phase 13.2c: ownership UAM + type warnings with file/line:col (AST offsets)
- [x] Phase 13.2d: source snippets under `-->` (line + caret) for parse/ownership
- [x] Stage 12.20: multi-file self-host — nested modules, cycles, path search
- [x] Stage 12.21: Bars.toml path-deps in self-host (`compiler/pkg.brs`, pkg_app example)
- [x] Stage 12.21b: Bars.toml git deps — clone to `target/bars-deps/<name>` (self-host)
- [x] Stage 12.21c: git dep pins — `branch` / `tag` / `rev` + `.bars-dep-pin` cache
- [x] Phase 13.2e: type mismatch diagnostics with line:col + source snippet
- [x] Phase 13.5: C backend (`codegen/c.brs`, `BARS_BACKEND_C=1`, self-test C suite)

**Bars-first workflow:**  
```
make host && make runtime && make bars-self   # Gen1
make self-test                               # examples suite
make identity                                # Gen3.ll == Gen4.ll
./bars-self examples/math.brs /tmp/m && /tmp/m
```

New language work goes in `compiler/*.brs`, not `bootstrap/`.

---

## Легенда

| Символ | Значение |
|--------|----------|
| ✅ | Завършено |
| 🚧 | В прогрес |
| 📋 | Планирано |

---

*Версия: 6.2 | Актуализирано: 2026-07-28*
