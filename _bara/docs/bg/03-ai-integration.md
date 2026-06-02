[← Към индекса](index.md)

# AI-First Философия на Дизайна

## Защо AI-First?

Съвременната софтуерна разработка се извършва все повече от **AI агенти**, работещи в терминални среди. Тези агенти не използват GUI, IDE или syntax highlighting. Те се нуждаят от:

1. **Структуриран I/O** — JSON/EDN, не просто текст
2. **Програмно Управление** — Всяка операция трябва да е скриптваема
3. **Самоописващи Се Системи** — AI може да открива възможности по време на изпълнение
4. **Git Интеграция** — Контрол на версиите като част от работния процес

## Принципи

### 1. Структуриран I/O

Цялата REPL комуникация използва JSON:

```json
// Вход
{"op": "eval", "form": "(+ 1 2)", "request-id": "uuid"}

// Изход
{
  "status": "ok",
  "request-id": "uuid",
  "result": {"type": "int", "value": 3, "printed": "3"},
  "meta": {"ms": 0.5, "ns": "user"}
}
```

### 2. Batch Операции

AI агентите оценяват множество форми наведнъж:

```json
{"op": "eval-batch",
 "forms": [
   "(defn add [a b] (+ a b))",
   "(add 10 20)"
 ]}
```

### 3. Персистентност на Сесията

Дефинициите се запазват в рамките на REPL сесия, позволявайки инкрементална разработка:

```json
{"op": "eval", "form": "(defn square [x] (* x x))"}
{"op": "eval", "form": "(square 5)"}
{"op": "get-defs"}
```

### 4. Възстановяване от Грешки

Всички грешки са структурирани с тип, съобщение и контекст:

```json
{
  "status": "error",
  "error": {
    "type": "compiler/unknown-symbol",
    "symbol": "unknwon-fn",
    "message": "Unknown symbol: unknwon-fn",
    "form": "(unknwon-fn 1 2)"
  }
}
```

## AI Работен Процес

```bash
# 1. Клониране на репото
git clone git@gitlab.com:balvatar/lisp-nim.git
cd lisp-nim

# 2. Стартиране на AI REPL
cljnim repl --json

# 3. AI оценява форми, получава структурирани отговори
# 4. AI пише файлове през (file/write ...) [бъдеще]
# 5. AI commit-ва през (git/commit ...) [бъдеще]
# 6. AI push-ва през (git/push) [бъдеще]
```

## Сравнение

| Аспект | Човешки IDE | AI Терминал |
|---|---|---|
| Интерфейс | GUI + мишка | Текст + команди |
| Навигация | Кликване | `(apropos ...)`, `(doc ...)` |
| Рефакториране | Ръчно | Batch eval + git diff |
| Тестване | Run button | `(run-tests)` структуриран отговор |
| Commit | GUI диалог | `(git/commit "msg")` |

## Бъдеще: Tool-Call Формат

Директна интеграция с AI frameworks:

```json
{
  "tool": "cljnim/eval",
  "arguments": {
    "code": "(defn fib [n] ...)",
    "mode": "compile"
  }
}
```
