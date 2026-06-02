
[← Към индекса](index.md)

---

# REPL API Референция

## JSON REPL Протокол

Стартирайте JSON REPL:
```bash
cljnim repl --json
```

REPL чете по един JSON обект на ред и отговаря с по един JSON обект на ред.

## Операции

### `eval`
Оценява единична Clojure форма.

**Заявка:**
```json
{"op": "eval", "form": "(+ 1 2 3)"}
```

**Отговор (успех):**
```json
{
  "status": "ok",
  "result": {
    "type": "unknown",
    "value": "6",
    "printed": "6"
  },
  "meta": {
    "ns": "user",
    "ms": 861.5,
    "form": "(+ 1 2 3)"
  }
}
```

**Отговор (грешка):**
```json
{
  "status": "error",
  "error": {
    "type": "reader/error",
    "message": "Unterminated list",
    "form": "( + 1 2"
  },
  "meta": {
    "ns": "user",
    "ms": 0.1
  }
}
```

**Незадължителни полета:**
- `request-id` — Correlation ID, върнат в отговора
- `ns` — Целево namespace (по подразбиране: `"user"`)

---

### `eval-batch`
Оценява множество форми последователно.

**Заявка:**
```json
{"op": "eval-batch", "forms": ["(defn f [x] x)", "(f 42)"]}
```

**Отговор:**
```json
{
  "status": "ok",
  "results": [
    {"status": "ok", "result": {"type": "var", "name": "f", ...}},
    {"status": "ok", "result": {"printed": "42"}, ...}
  ]
}
```

---

### `get-defs`
Листва всички дефинирани променливи в текущата сесия.

**Заявка:**
```json
{"op": "get-defs"}
```

**Отговор:**
```json
{"status": "ok", "defs": ["add", "square"], "ns": "user"}
```

---

### `clear`
Изчиства всички дефиниции от сесията.

**Заявка:**
```json
{"op": "clear"}
```

**Отговор:**
```json
{"status": "ok", "cleared": true}
```

---

### `quit`
Излиза от REPL.

**Заявка:**
```json
{"op": "quit"}
```

**Отговор:**
```json
{"status": "ok", "bye": true}
```

## Схема на Отговора

Всички отговори съдържат:
- `status` — `"ok"` или `"error"`

При успех:
- `result` — Обект с резултат от оценката
  - `type` — `"var"`, `"unknown"`, и т.н.
  - `printed` — Текстово представяне на резултата
- `meta` — Метаданни
  - `ns` — Текущо namespace
  - `ms` — Време за изпълнение в милисекунди
  - `form` — Оригиналната форма (ако е `eval`)

При грешка:
- `error` — Обект с грешка
  - `type` — Категория на грешката
  - `message` — Четимо съобщение
- `meta` — Както при успех

## Файлови Операции (от Clojure код)

| Функция | Пример | Връща |
|---|---|---|
| `file/read` | `(file/read "path")` | Низ със съдържание или map с грешка |
| `file/write` | `(file/write "path" "content")` | `true` или map с грешка |
| `file/append` | `(file/append "path" "more")` | `true` или map с грешка |
| `file/ls` | `(file/ls "dir")` | Вектор с имена на файлове |
| `file/exists?` | `(file/exists? "path")` | `true` / `false` |

## Git Операции (от Clojure код)

| Функция | Пример | Връща |
|---|---|---|
| `git/status` | `(git/status)` | Map с `:branch`, `:modified`, `:untracked`, `:staged`, `:clean` |
| `git/commit` | `(git/commit "msg")` | Map с `:sha`, `:success` |
| `git/push` | `(git/push)` | Map с `:success`, `:output` |
| `git/diff` | `(git/diff)` | Низ с diff |
| `git/log` | `(git/log)` или `(git/log 10)` | Вектор с commit низове |

## Команди в Човешки REPL

В човешки режим (`cljnim repl`):

| Команда | Описание |
|---|---|
| `:quit`, `:q` | Изход от REPL |
| `:help`, `:h` | Показване на помощ |
| `:defs` | Листване на дефинирани променливи |
| `:clear` | Изчистване на дефинициите |
| `:ns` | Показване на текущото namespace |
