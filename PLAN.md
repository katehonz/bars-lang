# Bars — Текущ План за Разработка

> Актуален към: 2026-06-03  
> Философия: Минимален core, богата екосистема. Като Rust.
> 
> Спринт 8 завършен ✅ — ADTs с deftype, exhaustiveness checking, Option/Result stdlib

---

## Философия

**По-важно е съществуващият код да работи перфектно, отколкото да добавяме нови фичъри.**

Нов фокус след спринт 5:
1. **Минимален core** — Bars предоставя само основата (ownership, types, компилация)
2. **Специфичните неща са за пакетите** — async I/O, web frameworks, system bindings идват отвън
3. **Няма вградена async рунтайм** — нито tokio, нито нещо подобно в езика
4. **Пакетна система като Cargo** — отделен инструмент, независим от компилатора

---

## Спринт 1: Runtime и Pretty-Print (1-2 дни) ✅

### Проблем
`println` за колекции отпечатва паметни адреси вместо четимо съдържание.

```
 bars> (println [1 2 3])
 140546983526368    ;; трябва да е [1 2 3]
```

### Задачи
- [x] **1.1** Добави `bars_print_any_i64` в C runtime с dynamic type detection чрез magic numbers.
- [x] **1.2** Промени `println` във всички backend-ове (QBE, Cranelift, LLVM) да използват `bars_print_any_i64` за променливи стойности.
- [x] **1.3** Тествай с всички примери.

**Критерий за приемане:** ✅ Всички примери с колекции отпечатват четими стойности.

---

## Спринт 2: Build Pipeline (1-2 дни) ✅

### Проблем
`bars build` принтира QBE IR на stdout, но не създава изпълним файл.

### Задачи
- [x] **2.1** `bars build` произвежда бинарен файл по подразбиране (име на файла без `.brs`).
- [x] **2.2** Пълен pipeline за QBE backend: `.brs` → QBE IR → qbe → асемблер → cc + runtime → binary.
- [x] **2.3** Cranelift AOT: компилира обект файл и линква с runtime.
- [x] **2.4** LLVM: компилира обект файл и линква с runtime.
- [x] **2.5** Автоматично линкване с `runtime/bars_runtime.o` и `-lgc` (Boehm GC).

**Критерий за приемане:** ✅
```bash
bars build examples/hello.brs -o hello
./hello
# → 42
```

---

## Спринт 3: Ownership Warnings за GC Обекти (1 ден) ✅

### Проблем
Всеки GC-managed обект (vector, map, set) предизвиква ownership warning за resource leak, макар че GC ще го освободи.

```
⚠️ Ownership warning: Resource leak: 'v' is owned but never consumed or dropped
```

### Задачи
- [x] **3.1** GC-managed конструктори (`vector`, `map`, `set`, `string`, `range`) са маркирани като "copy" в ownership checker.
- [x] **3.2** Ownership checker не проверява за resource leaks на copy/GC-managed стойности.
- [x] **3.3** Запазени warnings за ownership-managed ресурси (structs и бъдещи linear типове).

**Критерий за приемане:** ✅ Всички примери с колекции минават без ownership warnings. Structs все още се проверяват (както е правилно).

---

## Спринт 4: REPL Полиране (1-2 дни) ✅

### Задачи
- [x] **4.1** Pretty-print на резултати в REPL чрез `bars_print_any_i64` — вектори, карти, низове, числа.
- [x] **4.2** Multi-line input — вече работи чрез `depth` tracking на скобите.
- [x] **4.3** История на командите — добавен `rustyline` с `.bars_history` файл.
- [x] **4.4** Специални REPL команди: `:quit`, `:help`, `:ast <expr>`, `:type <expr>`.

---

## Спринт 5: Return Type Annotations (1 ден) ✅

### Проблем
Парсерът има TODO на ред 267: `let ret_type = None; // TODO: parse return type annotations`

### Задачи
- [x] **5.1** Синтаксис: `(defn add [a b] -> i64 (+ a b))`
- [x] **5.2** Парсване на `-> Type` след параметрите в `parse_defn`.
- [x] **5.3** Съхраняване в `Expr::Defn` AST.
- [x] **5.4** Type checker вече проверява съвпадение чрез constraint `body_ty == ret_type`.

---

## Спринт 6: TCO — Tail Call Recognition (2-3 дни) ✅

### Защо това е приоритет
В Lisp рекурсията е идиоматична. TCO позволява deep recursion без stack overflow.

### Задачи
- [x] **6.1** HIR lowering с `is_tail` флаг — `if`, `do`, `let`, `match` в tail position не създават merge blocks
- [x] **6.2** HIR `tail_call_optimize` pass — разпознава self-recursive `Call` + `Return` и ги заменя с `TailCall` terminator
- [x] **6.3** `TailCall` terminator добавен в HIR
- [x] **6.4** QBE backend: `TailCall` → `call` + `ret` (QBE не поддържа loop-back jump с променливи стойности)
- [x] **6.5** Cranelift backend: `TailCall` → `call` + `ret` (Cranelift SSA block params не позволяват прост TCO)
- [x] **6.6** LLVM backend: `TailCall` → `call` с `tail call` hint (`musttail` изисква LLVM 18+)
- [x] **6.7** Fix: `bars_print_any_i64` threshold увеличен до 256MB за да не dereference големи integers
- [x] **6.8** Тестове: tail-recursive `sum` и `factorial` работят за n=100

### Ограничения
> **Истинско TCO (deep recursion без stack overflow) е partial.**  
> HIR разпознава tail calls, но backend-овете ги компилират като обикновени calls. За deep recursion (>10_000), използвайте `loop`/`recur`, което е вече оптимизирано.

**Критерий за приемане:** ✅ Tail-recursive функции работят коректно. HIR pass разпознава `TailCall`. Тестове за `sum` и `factorial` минават.

---

## Спринт 7: Generics — Implicit Polymorphism (3-4 дни) ✅

### Задачи
- [x] **7.1** Let-polymorphism/generalization в type inference — `(defn id [x] x)` става `forall 'a. 'a → 'a`
- [x] **7.2** `instantiate` вече замества bound type variables с fresh vars при всяко извикване
- [x] **7.3** Type checking интегрирано в compilation pipeline — `bars build`/`run` хващат type errors
- [x] **7.4** Fix: recursive function support чрез placeholder типове преди inference
- [x] **7.5** Fix: forward-referenced functions (sum → sum-helper) чрез предварителна регистрация
- [x] **7.6** Fix: pattern match bindings (`match` arms) се добавят в type environment
- [x] **7.7** Fix: macro expansion `Quote` unwrap за `FnCall` func (syntax-quote + unquote)
- [x] **7.8** Fix: `println` и други I/O функции са полиморфни в builtin_env
- [x] **7.9** Тестове: generic `id`, `const`, multi-type usage

**Критерий за приемане:** ✅ `(defn id [x] x)` работи за i64, f64, bool, string, vector без type errors.

---

## Спринт 8: Algebraic Data Types (ADTs) (3-4 дни) ✅

### Задачи
- [x] **8.1** `deftype` за sum types (enum-like): `(deftype Option [Some i64] [None])`
- [x] **8.2** `match` вече работи с ADTs (вече има pattern matching, трябва да се свърже с типовете)
- [x] **8.3** `Result` тип в stdlib: `(deftype Result [Ok T] [Err E])`
- [x] **8.4** Exhaustiveness checking в `match` — compiler error ако липсва клон
- [x] **8.5** Тестове за ADTs + pattern matching

**Критерий за приемане:** ✅ Можеш да дефинираш `Option` и `Result` и да pattern match-ваш по тях.

---

## Спринт 9: FFI (`extern`) (2-3 дни) ✅

### Задачи
- [x] **9.1** Синтаксис: `(extern "printf" [fmt i64] -> i64)`
- [x] **9.2** Деклариране на C функции в HIR без body
- [x] **9.3** Pointer типове за C структури: всички аргументи i64 (pointer-compatible)
- [x] **9.4** Backend-ове да генерират правилни `extern` declarations (QBE/Cranelift/LLVM)
- [x] **9.5** Тест: извикване на `putchar` от C

**Критерий за приемане:** ✅ `(extern "putchar" [c i64] -> i64)` работи и отпечатва 'A'.

---

## Фаза 10: Минимална Stdlib (1 седмица) ✅

### Философия
**Само базови неща.** Всичко специфично (async, web, crypto, GUI) е за пакети.

### Задачи
- [x] **10.1** Higher-order функции: `map`, `filter`, `reduce` — inline loop desugaring в HIR
- [x] **10.2** String ops: `str-count`, `str-concat` ↔ C runtime
- [x] **10.3** Math: `sqrt`, `pow`, `abs` ↔ C runtime (libm wrappers)
- [x] **10.4** Error handling: `assert` macro, `deftype` за `Option`/`Result`
- [x] **10.5** Basic I/O: `slurp`, `spit` ↔ C runtime
- [x] **10.6** Testing helpers: `assert` macro

### Изрично НЕ в stdlib
- ❌ Async/await — няма вградена async рунтайм
- ❌ HTTP client/server — за пакети
- ❌ TCP/UDP sockets — за пакети
- ❌ Database drivers — за пакети
- ❌ GUI bindings — за пакети
- ❌ Cryptography — за пакети

**Критерий за приемане:** Можеш да напишеш скрипт, който чете файл, обработва string-ове, и пише резултат. Без нужда от външни пакети.

---

## Фаза 11: Пакетна Система ✅

### Философия
**Като Cargo за Rust — отделен crate в същия workspace.** `bars-pkg` е отделна библиотека, но CLI командите са интегрирани в `bars`.

### Задачи
- [x] **11.1** Формат на манифест: `Bars.toml` (като Cargo.toml)
- [x] **11.2** Git-based и path разрешаване на dependencies
- [x] **11.3** `bars new my-project` — scaffold проект
- [x] **11.4** `bars add <package>` — добавя dependency
- [x] **11.5** `bars build` (в проект) — резолва dependencies, компилира
- [x] **11.6** Lock файл (`Bars.lock`)
- [ ] **11.7** Central registry (бъдеще)
- [x] **11.8** Модули и namespaces: `(require "http" :as http)`

---

## Бъдещи подобрения (компилатор)

- [ ] Generic ADTs: `(deftype Option [Some T] [None])`
- [ ] Още string операции: `split`, `join`, `trim`, `substring`
- [x] `--release` флаг за всички backend-ове (QBE: `cc -O2`, Cranelift: `speed_and_size`, LLVM: `Aggressive`)
- [ ] Подобрени error messages
- [ ] LSP сървър

---

## Процес

За всеки спринт:
1. Напиши тестове преди кода (ако е възможно).
2. Внедри промените.
3. Увери се, че `cargo test` минава.
4. Увери се, че всички `examples/*.brs` работят.
5. Commit с ясно съобщение.

---

*План версия: 3.0 | Актуализиран: 2026-06-03*
