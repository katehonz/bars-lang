# jsonista.clj — Production JSON библиотека за Bara Lang

> Моделирана след [metosin/jsonista](https://github.com/metosin/jsonista), но с **нула Java зависимости**.

## Защо това е production пример?

Този пример демонстрира пълноценна JSON библиотека с API идентично на jsonista, но:

| | JVM jsonista | Bara Lang jsonista |
|---|---|---|
| JVM зависимост | ✅ Required (JVM + Jackson) | ❌ Няма |
| Jackson/databind | ✅ Required | ❌ Няма |
| GraalVM native-image | ❌ Необходим за бинарен файл | ❌ Не е необходим |
| Бинарен размер | 50MB+ | < 1MB |
| Startup time | Бавен (JVM warmup) | Мигновен |
| Java stdlib | ✅ Required | ❌ Не |

## API

```clojure
; Основни функции
(json/write-value-as-string data)                ; -> JSON string
(json/write-value-as-string data opts)           ; -> JSON string с опции
(json/read-value json-string)                    ; -> Bara Lang data
(json/read-value json-string opts)               ; -> Bara Lang data с опции
(json/write-value-to-file path data)             ; -> записва във файл
(json/write-value-to-file path data opts)        ; -> записва във файл
(json/read-value-from-file path)                 ; -> чете от файл
(json/read-value-from-file path opts)            ; -> чете от файл с опции
```

### Опции

| Опция | Тип | Описание |
|---|---|---|
| `:keyword-keys?` | `bool` | При четене, конвертира string ключове към keywords |
| `:pretty?` | `bool` | При писане, форматира JSON с отстъпи |

## Примери

### Базово encoding/decoding

```clojure
(def person {:name "Alice" :age 30})

(json/write-value-as-string person)
;; => {"name":"Alice","age":30}

(json/read-value "{\"name\":\"Alice\"}" {:keyword-keys? true})
;; => {:name "Alice"}
```

### Pretty printing

```clojure
(json/write-value-as-string
  {:user {:name "Bob" :roles [:admin :editor]}}
  {:pretty? true})
;; =>
;; {
;;   "user": {
;;     "name": "Bob",
;;     "roles": ["admin", "editor"]
;;   }
;; }
```

### File I/O

```clojure
(json/write-value-to-file "data.json" my-data {:pretty? true})
(json/read-value-from-file "data.json" {:keyword-keys? true})
```

### Error handling

```clojure
(json/read-value "{invalid}")
;; => {:error "input(1, 8) Error: string literal as key expected"}
```

## Как работи?

Вместо Jackson (Java), използваме **Nim std/json** директно през FFI/runtime слоя:

```
Clojure code
      ↓
Bara Lang Compiler
      ↓
Nim код + cljnim_runtime (std/json)
      ↓
im c -d:release
      ↓
Native binary (< 1MB)
```

Конверсията `CljVal ↔ JsonNode` се случва в `lib/cljnim_runtime.nim`:

- `ckNil` → `JNull`
- `ckBool` → `JBool`
- `ckInt` → `JInt`
- `ckFloat` → `JFloat`
- `ckString/ckKeyword` → `JString`
- `ckVector/ckList` → `JArray`
- `ckMap` → `JObject`

## Как да го пуснеш

```bash
# Компилиране и изпълнение
./cljnim run examples/jsonista.clj

# Или през Makefile
make check
```

## Реален use-case

Този пример симулира real-world API работа — парсване на HTTP response с nested структури, keyword keys, file persistence и error handling. Перфектно за:

- REST API клиенти
- Конфигурационни файлове
- Data pipelines
- Log агрегация
- Microservices

## Сравнение с оригиналния jsonista

| Feature | JVM jsonista | Bara Lang |
|---|---|---|
| `write-value-as-string` | ✅ | ✅ |
| `read-value` | ✅ | ✅ |
| Keyword keys | ✅ | ✅ |
| Pretty print | ✅ | ✅ |
| Custom mapper | ✅ | ✅ (чрез opts map) |
| File I/O | ✅ | ✅ |
| Tagged values | ✅ | Може да се добави |
| Modules (Joda, etc) | ✅ | Не е необходимо |

---

**Извод:** С Bara Lang получаваш същото production-ready JSON API, но без целия Java overhead — native бинарен файл, мигновен старт, и достъп до цялата Nim/C ecosystem.
