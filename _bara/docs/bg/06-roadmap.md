
[← Към индекса](index.md)

---

# Пътна Карта за Разработка

## Фаза 0: Компилаторно Ядро ✅
- [x] Clojure Reader (EDN парсер)
- [x] Reader поддържа: списъци `()`, вектори `[]`, карти `{}`, низове, ключови думи, символи, числа, булеви, nil
- [x] Reader поддържа: quote `'`, syntax-quote `` ` ``, unquote `~`, unquote-splicing `~@`
- [x] Reader поддържа: коментари `;`, read-all
- [x] AST → Nim Генератор
- [x] CLI (`compile`, `run`, `read`, `repl`)
- [x] Специални форми: `def`, `defn`, `fn`, `let`, `if`, `do`, `quote`
- [x] Специални форми: `when`, `cond`
- [x] Аритметични оператори: `+`, `-`, `*`, `/`
- [x] Оператори за сравнение: `=`, `not=`, `not`, `<`, `>`, `<=`, `>=`
- [x] Core функции: `println`, `map`, `filter`, `reduce`
- [x] Runtime типова система: `CljVal` с `nil`, `bool`, `int`, `float`, `string`, `keyword`, `symbol`, `list`, `vector`, `map`, `fn`, `atom`

## Фаза 1: Макро Система ✅
- [x] `macroexpand`, `macroexpand-1`
- [x] `syntax-quote`, `unquote`, `unquote-splicing`
- [x] `gensym`
- [x] `defmacro` (потребителски макроси)
- [x] Вградени макроси: `->`, `->>`, `and`, `or`, `when`, `when-not`, `cond`
- [x] Вградени макроси: `cond->`, `cond->>`, `doto`, `as->`, `some->`, `some->>`
- [x] Вградени макроси: `for`, `doseq`, `dotimes`
- [x] Вградени макроси: `when-let`, `if-let`
- [x] Вградени макроси: `comment`, `assert`, `with-open`

## Фаза 2: REPL и Инструменти ✅
- [x] Човешки REPL (`:help`, `:defs`, `:clear`, `:ns`, `:quit`)
- [x] JSON REPL (`--json`) със структуриран I/O
- [x] Batch оценка (`eval-batch`)
- [x] Структурирани грешки (тип, съобщение, форма, ред)
- [x] Персистентност на сесията за `def`/`defn`

## Фаза 3: Nim Interop ✅
- [x] Извикване на Nim функции: `(nim/math/sin x)`, `(nim/strutils/toUpper s)`
- [x] C FFI през Nim `importc`

## Фаза 4: AI-Native Инструменти ✅
- [x] Файлови операции: `(file/read "path")`, `(file/write "path" "content")`, `(file/append "path" "content")`
- [x] Файлови операции: `(file/ls "dir")`, `(file/exists? "path")`
- [x] Git операции: `(git/status)`, `(git/commit "msg")`, `(git/push)`
- [x] Git операции: `(git/diff)`, `(git/log)`
- [x] nREPL протокол съвместимост (JSON over TCP, `--tcp PORT`)
- [x] Tool-call формат за интеграция с AI frameworks

## Фаза 5: Persistent Структури от Данни ✅ (Завършена)
- [x] Persistent Vector (Hash Array Mapped Trie, 32-way branching)
- [x] Persistent Map (HAMT) — `pmapAssoc`, `pmapDissoc`, `pmapGet` в O(log₃₂ n)
- [x] Persistent Set
- [x] `conj`, `assoc`, `dissoc`, `get`, `get-in`
- [x] `nth`, `first`, `rest`, `last`, `count` върху persistent колекции
- [x] Transients за batch мутации
- [x] `conj!`, `assoc!`, `persistent!`

## Фаза 6: Clojure Core Библиотека ✅ (Завършена)
- [x] `range`, `repeat`, `cycle`, `iterate`
- [x] `take`, `drop`, `partition`, `interleave`, `concat`
- [x] `str`, `pr-str`, `println`, `prn`
- [x] `slurp`, `spit`, `read-line`
- [x] `meta`, `with-meta`, `vary-meta`
- [x] `type`, `instance?`, `satisfies?`

## Фаза 7: Компилация на Проекти ✅
- [x] Компилиране на цели проекти (не само отделни файлове)
- [x] Система за namespaces (`ns`, `(:require [lib :as alias])`)
- [x] Кеширане на модули за по-бърз REPL старт
- [x] Резолюция на зависимости (deps.edn, Git deps към .deps/)

## Фаза 8: Self-Hosted REPL ✅
- [x] Компилиране на форми в паметта (tree-walking interpreter, <1ms eval)
- [x] Бърз REPL старт (~0.02ms на eval спрямо 1133ms компилиран)
- [x] Hot code reloading (def/defn обновяват средата незабавно)

## Фаза 9: Конкурентност ✅
- [x] Atoms (compare-and-swap)
- [x] Agents (send, await, deref — sync dispatch в interpreter)
- [x] core.async channels (chan, >!, <!, close!, go — interpreter-first)

## Известни Проблеми
- `->>` threading macro с вложени `map`/`reduce` изисква правилен macro expansion контекст
