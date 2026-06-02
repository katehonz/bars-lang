# Bara Lang: Native Clojure

> Същият език, който обичаш. Компилиран до нативен код. Без JVM.

---

## Какво е Bara Lang?

**Bara Lang** е пълен диалект на Clojure, който се компилира до нативен машинен код през Nim компилатора. Това не е интерпретатор — това е истински компилатор с пълен pipeline за оптимизация:

```
Твоят .clj файл
      ↓
  Reader (EDN парсер)
      ↓
  Разширяване на макроси (defmacro, syntax-quote, ->, ->>)
      ↓
  Emitter (Clojure AST → Nim изходен код)
      ↓
  Nim компилатор → C код
      ↓
  C компилатор → Нативен бинарен файл
```

Резултатът е един изпълним файл, често под **1 MB**, който стартира мигновено — **без JVM warmup**.

### Защо native?

| JVM Clojure | Bara Lang |
|-------------|-------------|
| Нуждае се от Java runtime | Самостоятелен бинарен файл |
| ~2-5 секунди startup | Мигновен старт |
| ~100-300 MB RAM | ~1-10 MB |
| JIT паузи | Ahead-of-time, предсказуем |
| Идеален за сървъри | Идеален за CLI, embedded, WASM |

Това не е играчка. Това е production компилатор с **276+ теста**, **persistent структури от данни (HAMT)**, **core.async канали** и **AI-асистиран workflow**.

---

## Инсталация

```bash
git clone https://gitlab.com/balvatar/lisp-nim.git
cd lisp-nim
make build
make check   # всички тестове + примери
```

**Изисквания:** Nim ≥ 2.0, GCC или Clang, make.

Толкова. Няма Java. Няма Leiningen. Няма deps, които се свалят по десет минути.

---

## Първа програма

Създай `hello.clj`:

```clojure
(println "Здравей от native Clojure!")
(println (+ 1 2 3 4 5))
```

Изпълни:

```bash
$ ./cljnim run hello.clj
Здравей от native Clojure!
15
```

Забележи: програмата беше парсирана, разширена с макроси, емитирана като Nim, компилирана до C, компилирана до машинен код и изпълнена — всичко за под секунда.

---

## REPL: Два режима

### Човешки REPL

```bash
$ ./cljnim repl
user> (defn square [x] (* x x))
user> (square 7)
=> 49
user> (atom 42)
=> (atom 42)
user> :ai функция за фибоначи
🤖 Мисля...
💡 AI Предложение:
   (defn fib [n]
     (loop [a 0 b 1 i 0]
       (if (= i n) a (recur b (+ a b) (inc i)))))
```

### JSON REPL (за AI агенти)

```bash
$ ./cljnim repl --json
{"status":"ready","ns":"user","mode":"json"}

> {"op":"eval","form":"(+ 1 2 3)"}
{"status":"ok","result":{"printed":"6"},"meta":{"ms":12}}

> {"tool":"cljnim/eval","args":{"form":"(defn greet [name] (str \"Hello \" name))"}}
{"status":"ok","result":{"type":"var","name":"greet"},...}
```

JSON REPL е проектиран за програмно взаимодействие. Всяка операция има структуриран вход и изход. AI агенти могат да откриват възможности, оценяват код, инспектират дефиниции и обработват batch форми без парсиране на човешки текст.

---

## AI-асистирана разработка

Bara Lang е първата Clojure имплементация, в която AI асистенцията е първокласна функция.

### Обяснение на грешки

Когато компилацията fail-не, компилаторът пита AI за помощ:

```bash
$ ./cljnim run broken.clj
Compilation failed
Error: identifier expected, but got 'keyword var'

💡 AI Предложение:
   Грешката е защото `var` е запазена дума в Nim.
   Оправи: Преименувай функцията на `my-var`.
```

### Генериране на код

Генерирай идиоматичен Clojure от описание:

```bash
$ ./cljnim ai "функция, която филтрира четните числа"
(defn filter-even [coll]
  (loop [remaining coll result []]
    (if (empty? remaining)
      result
      (let [x (first remaining)]
        (recur (rest remaining)
               (if (even? x) (conj result x) result))))))
```

### Настройка

```bash
export DEEPSEEK_API_KEY="sk-..."
# или OPENAI_API_KEY, или MIMO_API_KEY
```

---

## `loop` / `recur`: Истинска TCO

За разлика от JVM Clojure (който използва `recur`, за да избегне stack overflow, но все пак работи върху stack-based VM), Bara Lang компилира `loop`/`recur` до native `while` цикъл:

```clojure
(defn factorial [n]
  (loop [acc 1 i n]
    (if (= i 0)
      acc
      (recur (* acc i) (dec i)))))
```

Това генерира ефективен C код без функционални извиквания. **Истински O(1) stack space**.

---

## Cross-Compilation Target-и

Bara Lang може да таргетира множество платформи от един и същи изходен код:

### Нативен бинарен файл (по подразбиране)
```bash
./cljnim run program.clj
```

### JavaScript
```bash
./cljnim compile program.clj program.nim
nim js -o:program.js program.nim
node program.js
```

### C Shared Library
```bash
./cljnim compile-lib program.clj program.nim
nim c --app:lib -o:libprogram.so program.nim
```

### WASM (експериментално)
```bash
nim c -d:release --cpu:wasm32 --os:linux program.nim
```

Това е нещо, което JVM Clojure просто не може да направи.

---

## Persistent Структури от Данни

Bara Lang имплементира истински **Hash Array Mapped Trie (HAMT)** вектори и карти:

```clojure
(def v (vector 1 2 3))
(def v2 (conj v 4))
;; v  => [1 2 3]
;; v2 => [1 2 3 4]
;; Structural sharing: O(log₃₂ n) обновления, не O(n) копия
```

Runtime-ът използва същите алгоритми като Clojure/JVM (32-way branching, path copying, tail optimization), но компилиран до bare metal.

---

## Конкурентност

### Atoms

```clojure
(def counter (atom 0))
(swap! counter inc)    ;; => 1
(reset! counter 100)   ;; => 100
(deref counter)        ;; => 100
```

### Agents

```clojure
(def state (agent 0))
(send state + 10)
(await state)
(deref state)          ;; => 10
```

### Канали (core.async)

```clojure
(def ch (chan 10))
(put! ch 42)
(take! ch)             ;; => 42
(close! ch)
```

Всички примитиви за конкурентност работят както в компилирания runtime, така и в in-memory интерпретатора.

---

## Макроси, които работят

```clojure
(defmacro unless [condition body]
  `(if (not ~condition)
     ~body))

(unless false
  (println "Това се печата!"))
```

Threading макроси, `when-let`, `cond`, `doto`, `some->` — всички имплементирани като истински Clojure макроси, разширявани по време на компилация.

---

## Кога да използваш Bara Lang

| Use Case | Clojure/JVM | Bara Lang |
|----------|-------------|-------------|
| Големи уеб услуги | ✅ | ⚠️ (ранен етап) |
| CLI инструменти | ⚠️ (бавен старт) | ✅ (мигновен) |
| Embedded системи | ❌ | ✅ |
| WASM / браузър | ClojureScript | ✅ (native WASM) |
| Споделени библиотеки | ❌ | ✅ |
| AI agent scripting | ❌ | ✅ (JSON REPL) |
| Учене на Clojure | ✅ | ✅ (без JVM) |

---

## Допълнително четене

- [Основи](01-fundamentals.md) — Core Clojure концепции (валидни за всички диалекти)
- [Архитектура](../../docs/bg/02-architecture.md) — Как работи компилаторът вътрешно
- [AI Интеграция](../../docs/bg/03-ai-integration.md) — Детайли за AI функциите
- [API Справочник](../../docs/bg/04-api-reference.md) — Спецификация на JSON REPL протокола

---

*Bara Lang е доказателство, че не ти трябва виртуална машина, за да пишеш елегантен, функционален, immutable код. Трябва ти само добър компилатор.*
