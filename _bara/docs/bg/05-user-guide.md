
[← Към индекса](index.md)

---

# Ръководство за Потребителя — Bara Lang

## Инсталация

### Изисквания
- Nim >= 2.0
- GCC или Clang
- make

### Изграждане от Източник
```bash
git clone https://gitlab.com/balvatar/lisp-nim.git
cd lisp-nim
make build
```

## CLI Команди

### `compile` — Компилиране до Nim
```bash
./cljnim compile input.clj output.nim
```
Генерира `.nim` файл от Clojure изходен код.

### `run` — Компилиране и Изпълнение
```bash
./cljnim run examples/hello.clj
```
Компилира до Nim, после до C, после до бинарен файл, и го изпълнява.

### Глобални Флагове

#### `--lib-path <dir>` — Потребителска Директория за Библиотеки
Презаписва стандартния път за търсене на `lib/`. Проверява се преди `CLJNIM_LIB_PATH` environment променлива и вградените пътища.

```bash
./cljnim --lib-path ./my_project/lib run app.clj
```

Алтернатива чрез environment променлива:
```bash
export CLJNIM_LIB_PATH=./my_project/lib
./cljnim run app.clj
```

### `read` — Парсиране и Отпечатване на AST
```bash
./cljnim read examples/hello.clj
```
Показва Clojure AST като S-изрази.

### `repl` — Интерактивен REPL
```bash
# Човешки режим
./cljnim repl

# AI режим (структуриран JSON)
./cljnim repl --json
```

## Писане на Bara Lang Програми

### Базов Синтаксис
```clojure
; Коментарите започват с точка и запетая

; Дефиниране на променлива
(def x 42)

; Дефиниране на функция
(defn greet [name]
  (println "Здравей, " name))

; Функция с docstring
(defn greet "Поздравява някого" [name]
  (str "Здравей, " name))

; Multi-arity функция
(defn greet-multi
  ([name] (greet-multi name "Здравей"))
  ([name greeting] (str greeting ", " name)))

; Функция с rest параметри
(defn sum-all [x & rest]
  (+ x (reduce + rest)))

; Извикване на функция
(greet "Свят")
(greet-multi "Алиса")          ;; => "Здравей, Алиса"
(greet-multi "Алиса" "Здрасти") ;; => "Здрасти, Алиса"
(sum-all 1 2 3 4)              ;; => 10

; Аритметика
(+ 1 2 3)      ; => 6
(* 10 20)      ; => 200
(/ 100 4)      ; => 25

; Условни изрази
(if (> x 0)
  "положително"
  "неположително")

; Локални обвързвания
(let [a 10
      b 20]
  (+ a b))     ; => 30
```

### Работа с Данни
```clojure
; Вектори (използват Nim seq вътрешно)
(def nums [1 2 3 4 5])

; Ключови думи
(def person {:name "Алиса" :age 30})

; Ключова дума като функция (търсене в карта)
(:name person)                 ;; => "Алиса"
(:age person)                  ;; => 30

; Картите и множествата използват persistent HAMT структури
; със structural sharing и O(log₃₂ n) операции.
```

### Рекурсия
```clojure
(defn factorial [n]
  (if (= n 0)
    1
    (* n (factorial (- n 1)))))

(println (factorial 5))  ; => 120
```

### Функции от Първи Клас
Потребителските функции могат да се подават като стойности на функции от по-висок ред:

```clojure
(defn square [x] (* x x))
(defn odd? [x] (= 1 (mod x 2)))

(map square [1 2 3 4])         ;; => [1 4 9 16]
(filter odd? [1 2 3 4])        ;; => [1 3]
(apply + [1 2 3])              ;; => 6
```

### Loop / Recur
```clojure
(defn find-header [headers name]
  (loop [pairs (seq headers)]
    (if (empty? pairs)
      nil
      (let [[k v] (first pairs)]
        (if (= k name)
          v
          (recur (rest pairs)))))))

(find-header [[:content-type "text/html"] [:accept "*/*"]] :accept)
;; => "*/*"
```

## Ръководство за AI REPL

JSON REPL е проектиран за програмно взаимодействие.

### Стартиране на AI REPL
```bash
./cljnim repl --json
```

### Оценка на Форма
```json
{"op": "eval", "form": "(+ 1 2 3)"}
```
Отговор:
```json
{
  "status": "ok",
  "result": {"printed": "6"},
  "meta": {"ns": "user", "ms": 861, "form": "(+ 1 2 3)"}
}
```

### Batch Оценка
```json
{"op": "eval-batch", "forms": ["(defn f [x] x)", "(f 42)"]}
```

### Листване на Дефиниции
```json
{"op": "get-defs"}
```
Отговор:
```json
{"status": "ok", "defs": ["f"], "ns": "user"}
```

### Изчистване на Сесия
```json
{"op": "clear"}
```

### Изход
```json
{"op": "quit"}
```

## Съвети

- Използвайте `:help` в човешки REPL за налични команди.
- Дефинициите в REPL се запазват през оценките в рамките на една сесия.
- Флагът `--json` прави REPL изцяло машинно-четим.
