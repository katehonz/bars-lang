
[← Към индекса](index.md)

---

# Архитектура на Bara Lang

## Общ Преглед

Bara Lang е **компилатор**, не интерпретатор. Следва модела на ClojureScript: Clojure изходният код се чете, разширява с макроси, анализира и се генерира като Nim изходен код, който после се компилира до C и накрая до native бинарен файл.

## Компилационен Пайплайн

```
┌─────────────┐
│  .clj Файл  │
└──────┬──────┘
       │
  ┌────▼────┐
  │ Reader  │  ← EDN парсер. Произвежда Clojure структури от данни.
  └────┬────┘
       │
  ┌────▼────┐
  │ Макроси │  ← Разширение на defmacro. Работи върху Clojure данни.
  └────┬────┘
       │
  ┌────▼────┐
  │Анализатор│  ← Специални форми, locals, анализ на closures.
  └────┬────┘
       │
  ┌────▼────┐
  │ Генератор│  ← Генерира Nim AST / изходен код.
  └────┬────┘
       │
  ┌────▼────┐
  │ Nim CC  │  ← Nim → C компилация.
  └────┬────┘
       │
  ┌────▼────┐
  │   C CC  │  ← C → машинен код (GCC/Clang).
  └────┬────┘
       │
  ┌────▼────┐
  │  Бинарен│  ← Единичен native изпълним файл.
  └─────────┘
```

## Уникални Предимства

### Независимост от Java Екосистемата
Bara Lang е **единственият** Clojure диалект с абсолютно никаква зависимост от Java екосистемата:

| Диалект | JVM | GraalVM | Google Closure | Java stdlib |
|---------|-----|---------|----------------|-------------|
| Clojure (JVM) | ✅ | ❌ | ❌ | ✅ |
| ClojureScript | ❌ | ❌ | ✅ | ❌ |
| Babashka | ❌ | ✅ | ❌ | Частично |
| **Bara Lang** | ❌ | ❌ | ❌ | ❌ |

Това означава:
- **Без JVM warmup** — бинарните файлове стартират мигновенно
- **Без GraalVM сложност** — без native-image конфигурация
- **Без нужда от Java инсталация** — самият компилатор е единичен бинарен файл
- **Истинско standalone разгръщане** — един файл, нула runtime зависимости

### Native HAMT Имплементация
Нашите persistent структури от данни са изградени от нулата в Nim, оптимизирани за Nim's ORC garbage collector:
- **32-way branching** като Clojure's `PersistentVector`, но без Java object overhead
- **Структурно споделяне** през copy-on-write HAMT възли
- **O(log₃₂ n)** за `assoc`/`dissoc`/`nth` — същата асимптотична сложност като JVM Clojure
- **Nim ref обекти** вместо Java интерфейси — по-просто разположение в паметта, по-добра кеш локалност

### Мулти-таргет Компилация
Един и същ Clojure изходен код се компилира до четири различни таргета от един codebase:
1. **Native бинарен файл** — `nim c` → C → машинен код
2. **Shared library** — `nim c --app:lib` → `.so` / `.dll` / `.dylib`
3. **WASM** — `nim c -d:emscripten` → browser-native WebAssembly
4. **JavaScript** — `nim js` → браузър/Node.js

Никоя друга Clojure имплементация не предлага толкова широк спектър от таргети без външни инструменти.

## Ключови Дизайн Решения

### 1. AOT Компилатор
Компилираме предварително (ahead-of-time), като ClojureScript. Това ни дава:
- Бързо изпълнение (скорост на C)
- Малък размер на бинарния файл
- Без overhead на интерпретатор

Компромисът е, че компилацията в REPL е по-бавна (всяка форма се компилира индивидуално).

### 2. Clojure Макроси върху Clojure Данни
Разширяването на макроси става **преди** да стигнем до Nim. Nim никога не вижда Clojure макроси:

```clojure
(defmacro unless [condition & body]
  `(if (not ~condition)
     (do ~@body)))
```

Този макро оперира върху `CljVal` обекти (Clojure списъци, символи), не върху Nim AST.

### 3. Runtime в Nim
Модулът `lib/cljnim_runtime.nim` предоставя:
- `CljVal` — tagged union, представящ всички Clojure стойности
- `cljAdd`, `cljMul`, и т.н. — полиморфна аритметика
- `cljRepr` — текстово представяне

### 4. Nim Interop
Вместо Java interop, имаме директен Nim interop:

```clojure
(nim/math/sin x)
(nim/strutils/toUpper s)
```

Nim модулите се импортират автоматично при извикване през `nim/module/fn` шаблона.

## Отговорности на Модулите

| Модул | Роля |
|---|---|
| `src/reader.nim` | Парсира `.clj` текст към `CljVal` AST |
| `src/emitter.nim` | Трансформира `CljVal` AST в Nim изходен код |
| `src/repl.nim` | Имплементация на human и AI REPL |
| `src/eval.nim` | Tree-walking interpreter за бързо in-memory eval |
| `src/deps.nim` | Резолюция на зависимости (deps.edn формат) |
| `src/core.nim` | Core runtime функции (AOT компилирани) |
| `src/types.nim` | Типове на AST възли (използват се от reader/emitter) |
| `src/macros.nim` | Двигател за разширяване на макроси |
| `src/runtime.nim` | Допълнителни runtime помощници |
| `lib/cljnim_runtime.nim` | Основна runtime библиотека |
| `lib/cljnim_pvec.nim` | Persistent Vector (HAMT имплементация) |
| `lib/cljnim_pmap.nim` | Persistent Hash Map (HAMT имплементация) |
| `lib/cljnim_async.nim` | core.async channels runtime |

## Модел на Паметта

- Използва Nim's ORC garbage collector
- `CljVal` е `ref object` (заделя се на heap)
- Persistent структури от данни (Vector, Map, Set) използват структурно споделяне през HAMT
