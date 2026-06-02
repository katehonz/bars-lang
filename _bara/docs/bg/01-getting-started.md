
[← Към индекса](index.md)

---

# Първи стъпки

> Диалект на Clojure, който се компилира до Nim → C → нативен бинарен файл.

## Изисквания

- **Nim** >= 2.0.0
- **GCC** или **Clang**
- **make**
- **curl** (за AI функциите, незадължително)

## Инсталация

```bash
git clone https://gitlab.com/balvatar/lisp-nim.git
cd lisp-nim
make build
```

## Проверка

```bash
make check    # компилация + 276+ теста + всички примери
```

## CLI Команди

| Команда | Описание |
|---------|----------|
| `./cljnim compile <file.clj>` | Компилиране до Nim изходен код |
| `./cljnim compile-lib <file.clj>` | Компилиране с експортирани функции (`*`) |
| `./cljnim run <file.clj>` | Компилиране и изпълнение |
| `./cljnim read <file.clj>` | Парсиране и печат на AST |
| `./cljnim repl` | Стартиране на човешки REPL |
| `./cljnim repl --json` | JSON REPL (за AI агенти) |
| `./cljnim deps` | Разрешаване на зависимости от `deps.edn` |
| `./cljnim -e '<код>'` | Оценка на израз |
| `./cljnim ai '<описание>'` | Генериране на Clojure код с AI |

## Бързи примери

### Hello World
```clojure
;; examples/hello.clj
(println "Hello, Nim world!")
(println (+ 1 2 3))
```

```bash
$ ./cljnim run examples/hello.clj
Hello, Nim world!
6
```

### Функции и рекурсия
```clojure
(defn square [x] (* x x))
(defn factorial [n]
  (if (= n 0)
    1
    (* n (factorial (- n 1)))))

(let [a 5]
  (println (square a))
  (println (factorial a)))
```

### loop/recur
```clojure
(defn sum [n]
  (loop [acc 0 i 1]
    (if (> i n)
      acc
      (recur (+ acc i) (inc i)))))
(println (sum 10))  ;; => 55
```

### Atoms (REPL)
```clojure
user> (def a (atom 0))
user> (swap! a inc)
1
user> (reset! a 42)
42
user> (deref a)
42
```

## AI Настройка (незадължително)

```bash
export DEEPSEEK_API_KEY="sk-..."
# или OPENAI_API_KEY, или MIMO_API_KEY
```

Виж [03-ai-integration.md](03-ai-integration.md) за пълна AI документация.

## Структура на проекта

```
├── src/              # Изходен код на компилатора
│   ├── cljnim.nim    # CLI входна точка
│   ├── reader.nim    # EDN парсер
│   ├── emitter.nim   # Clojure AST → Nim
│   ├── eval.nim      # Интерпретатор (REPL бърз път)
│   └── ai_assist.nim # AI API интеграция
├── lib/              # Runtime библиотеки
│   ├── cljnim_runtime.nim      # Нативен runtime
│   └── cljnim_runtime_js.nim   # JS runtime
├── tests/            # Тестове (8 файла, 276+ теста)
├── examples/         # Примери .clj
├── benchmarks/       # Бенчмаркове
├── docs/             # Документация
└── experiments/      # Web, WASM, native-lib target-и
```

## Следващи стъпки

- [02-architecture.md](02-architecture.md) — Как работи компилаторът
- [03-ai-integration.md](03-ai-integration.md) — AI-асистирана разработка
- [04-api-reference.md](04-api-reference.md) — JSON REPL протокол
- [05-user-guide.md](05-user-guide.md) — Макроси, interop, напреднали шаблони
