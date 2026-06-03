# Bars — Пътна Карта (v4.0)

> Актуална към: 2026-06-03  
> Състояние: Фази 0–5 завършени. Фаза 6 е следваща.  
> Философия: Минимален core, богата екосистема.

---

## Обобщение

Bars вече е работещ компилатор за системен Lisp с ownership.  
**~4000 реда Rust**, **~400 реда C runtime**, 3 backend-а, макросистема, pattern matching, структури, колекции, REPL, build pipeline, return type annotations.

```
.brs файл → Reader → AST → Macros → HIR → Ownership → Type Inference → Backend (QBE/Cranelift/LLVM)
```

---

## Фаза 0: Инфраструктура ✅ ЗАВЪРШЕНА

- [x] Проектна структура (Cargo, crates)
- [x] Reader: lexer + parser за S-expressions
- [x] Поддръжка на атоми, списъци `()`, вектори `[]`, keywords `:`
- [x] Коментари `;`, низове `"`
- [x] CLI скелет с `clap`

**Резултат:** `bars read file.brs` → AST

---

## Фаза 1: AST → Нативен Код ✅ ЗАВЪРШЕНА

- [x] AST типове (`Expr`, `Stmt`, `FnDef`)
- [x] QBE IR generation — стар AST backend
- [x] `main` функция и entry point
- [x] Build pipeline: `.brs` → `.ssa` → `.c` → binary
- [x] Базови конструкции: константи, аритметика, `let`, `if`, `defn`

**Резултат:** `(+ 1 2)` се компилира до работещ бинарен файл.

---

## Фаза 2: Архитектурен Рефактор ✅ ЗАВЪРШЕНА

### 2.1 Ownership Анализатор
- [x] Borrow checker с `^` и `^mut`
- [x] Move semantics по подразбиране
- [x] Use-after-move проверка
- [x] NLL (Non-Lexical Lifetimes) — borrow изтича след последна употреба
- [x] Struct field tracking — забрана за достъп след move
- [x] Implicit borrow за owned стойности, подадени на borrow параметри
- [x] Drop checking — warnings за resource leaks (GC обектите са exempt)
- [x] Span/локация в OwnershipError

### 2.2 HIR (High-level IR)
- [x] HIR типове: `Const`, `Load`, `Store`, `Alloc`, `FieldLoad`, `Call`, `Branch`, `Jump`, `Label`, `Return`
- [x] Lowering pass: AST → HIR
- [x] HIR optimizations

### 2.3 Бекенди върху HIR
- [x] QBE backend (нов, HIR-based)
- [x] Cranelift JIT backend
- [x] Cranelift AOT backend (`--backend cranelift`)
- [x] LLVM backend (`inkwell`, `--backend llvm`)

**Резултат:** Всички backend-ове работят през HIR. Старият QBE AST backend е премахнат.

---

## Фаза 3: Езикови Възможности ✅ ЗАВЪРШЕНА

- [x] Функции с параметри (`defn`)
- [x] Return type annotations: `(defn add [a b] -> i64 (+ a b))`
- [x] Lexical scope
- [x] Рекурсия (включително `loop`/`recur`)
- [x] Lambda функции (анонимни)
- [x] Pattern matching (`match`)
- [x] Structs/records (`defstruct`, field access `.x`)
- [x] Макроси (`defmacro`, `` ` ``, `~`, `~@`)
- [x] `load` за модули
- [x] Типов inference за locals и функции

**Резултат:** Можеш да пишеш сложни програми с макроси, pattern matching и type annotations.

---

## Фаза 4: Runtime и Колекции ✅ ЗАВЪРШЕНА

- [x] Boehm GC интеграция (C runtime)
- [x] Runtime типове: `bars_value_t` с tag
- [x] String (pointer + length)
- [x] Vector (динамичен масив, i64-only helpers)
- [x] Map (hash map, i64-only helpers)
- [x] Set (backed by map)
- [x] Nested collections (вектори от вектори, maps с ключови думи)
- [x] Runtime функции: `println`, `count`, `get`, `push`, `map-set`, `set-add`
- [x] Pretty-print на колекции чрез `bars_print_any_i64`

**Резултат:** Колекциите работят и се отпечатват четимо.

---

## Фаза 5: REPL, CLI и Build Pipeline ✅ ЗАВЪРШЕНА

- [x] Read-Eval-Print Loop (Cranelift JIT)
- [x] `bars run file.brs`
- [x] `bars check file.brs`
- [x] `bars read file.brs`
- [x] `bars repl` — с history, multi-line, pretty-print
- [x] `bars build file.brs -o binary` — реален изпълним файл за трите backend-а
- [x] `--backend` флаг (`qbe`, `cranelift`, `llvm`)
- [x] REPL команди: `:quit`, `:help`, `:ast`, `:type`

**Резултат:** Пълен pipeline от `.brs` до binary. Интерактивен REPL.

---

## Фаза 6: TCO и Оптимизации 📋 СЛЕДВАЩА

> **Приоритет: КРИТИЧЕН.** Без TCO рекурсията в Lisp е опасна.

- [ ] Tail Call Optimization (TCO) — jump вместо call за tail calls
- [ ] HIR-level constant folding
- [ ] Dead code elimination
- [ ] Inline на малки функции

**Резултат:** `(defn sum [n acc] (if (= n 0) acc (sum (- n 1) (+ acc n))))` работи за n=1_000_000.

---

## Фаза 7: Типова Система 📋 ПЛАНИРАНА

- [ ] Generic функции (`defn id [x] x`) с monomorphization
- [ ] Generic структури (`defstruct Pair [a b]`)
- [ ] Algebraic Data Types (`deftype`, `defvariant`)
- [ ] `Result` и `Option` типове в stdlib
- [ ] Exhaustiveness checking в `match`

**Резултат:** Можеш да пишеш generic функции и ADTs с exhaustiveness checking.

---

## Фаза 8: FFI и Системно Програмиране 📋 ПЛАНИРАНА

- [ ] `extern` за C функции: `(extern "printf" [fmt & args] -> i32)`
- [ ] Pointer типове за C структури: `*T` или `^c T`
- [ ] Struct layout съвместим с C
- [ ] `sizeof`, `alignof`
- [ ] Модули и namespaces

**Резултат:** Можеш да пишеш системен код и да ползваш C библиотеки.

---

## Фаза 9: Минимална Стандартна Библиотека 📋 ПЛАНИРАНА

> **Философия: Само базови неща. Като Rust std — thin, но достатъчна.**  
> Всичко специфично (async, web, crypto, GUI) е за пакети.

### Включва
- [ ] Higher-order функции: `map`, `filter`, `reduce`, `for-each`
- [ ] String manipulation: `split`, `join`, `trim`, `substring`, `concat`
- [ ] Math: `pow`, `sqrt`, `sin`, `cos` (C math library wrappers)
- [ ] Error handling: `Result`/`Option` + helper macros (`try!`, `when-let`)
- [ ] Basic I/O: `read-line`, `slurp` (цял файл в string), `spit` (string в файл)
- [ ] Testing: `assert`, `assert=`

### Изрично НЕ включва
- ❌ Async/await — няма вградена async рунтайм (tokio и подобни са за пакети)
- ❌ HTTP client/server — за пакети
- ❌ TCP/UDP sockets — за пакети
- ❌ Database drivers — за пакети
- ❌ GUI bindings — за пакети
- ❌ Cryptography — за пакети

**Резултат:** Можеш да напишеш скрипт, който чете файл, обработва string-ове, и пише резултат. Без нужда от външни пакети за базови неща.

---

## Фаза 10: Пакетна Система 📋 ПЛАНИРАНА

> **Като Cargo за Rust. Отделна от компилатора.**

- [ ] `Bars.toml` манифест формат
- [ ] `bars new my-project` — scaffold проект
- [ ] `bars add <package>` — добавя dependency
- [ ] Git-based разрешаване на dependencies
- [ ] Semantic versioning и `Bars.lock`
- [ ] Модули и namespaces: `(require "http" :as http)`
- [ ] (Бъдеще) Central registry

**Резултат:** Екосистема от пакети. Потребителите могат да публикуват и ползват библиотеки.

---

## Фаза 11: Екосистема и Tooling (Далечно бъдеще) 📋 ПЛАНИРАНА

- [ ] Language Server Protocol (LSP) — autocomplete, go-to-definition, hover types
- [ ] Formatter (`bars fmt`)
- [ ] Linter (`bars lint`)
- [ ] Documentation generator (`bars doc`)
- [ ] Debugger integration
- [ ] Cross-compilation (`--target`)
- [ ] `--release` флаг с LLVM + O2/O3

**Резултат:** Bars е пълноценен инструмент за production разработка.

---

## Легенда

| Символ | Значение |
|--------|----------|
| ✅ | Завършено |
| 📋 | Планирано |

---

*Версия: 4.0 | Актуализирано: 2026-06-03*
