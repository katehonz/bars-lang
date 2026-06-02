# Bara Lang Документация

> Clojure диалект, който се компилира до Nim → C → native бинарни файлове.
> **Единствената самостоятелна Clojure имплементация, напълно независима от Java екосистемата.**

## Избор на език / Choose Language

| 🇧🇬 Български | 🇬🇧 English |
|-------------|------------|
| [Българска Документация](index.md) | [English Documentation](../en/index.md) |

## Бързи връзки

- **GitHub/GitLab:** [lisp-nim](https://gitlab.com/balvatar/lisp-nim)
- **Build:** `make build && make check`
- **Тестове:** 276+ теста в 8 тестови пакета
- **AI Интеграция:** DeepSeek API, OpenAI-compatible, Xiaomi MiMo
- **Test Suite:** [Съвместимост с Clojure Test Suite](07-clojure-test-suite.md) — между-диалектно тестване за съответствие

## Документация

| # | Тема | Файл |
|---|------|------|
| 1 | Първи стъпки | [01-getting-started.md](01-getting-started.md) |
| 2 | Архитектура | [02-architecture.md](02-architecture.md) |
| 3 | AI Интеграция | [03-ai-integration.md](03-ai-integration.md) |
| 4 | API Справочник | [04-api-reference.md](04-api-reference.md) |
| 5 | Ръководство за потребителя | [05-user-guide.md](05-user-guide.md) |
| 6 | Пътна карта | [06-roadmap.md](06-roadmap.md) |
| 7 | Clojure Test Suite | [07-clojure-test-suite.md](07-clojure-test-suite.md) |

## Защо Bara Lang?

За разлика от всеки друг Clojure диалект, Bara Lang има **нула зависимост от Java екосистемата** — нито JVM, нито GraalVM, нито Google Closure Compiler, нито Java стандартна библиотека.

| Диалект | Зависимост от Java екосистемата |
|---------|--------------------------------|
| Clojure (JVM) | Пълна — работи върху JVM |
| ClojureScript | Голяма — Google Closure Compiler |
| Babashka | Средна — GraalVM native-image |
| **Bara Lang** | **Никаква — напълно самостоятелен** |

### Уникални предимства

1. **Native HAMT Persistent структури от данни** — Изградени от нулата в Nim (Persistent Vector, Map, Set със структурно споделяне)
2. **Множество таргети** — Native бинарен файл, shared library (.so/.dll), WASM и JavaScript от един codebase
3. **AOT Компилатор** — Clojure → Nim → C → native, работи със скоростта на C
4. **Nim/C Interop** — Директен FFI без overhead от JVM bridging
5. **AI-Native Tooling** — Вградена AI интеграция за генериране на код, оптимизация и дебъгване
6. **Конкурентност без JVM** — Atoms, Agents и core.async channels без Java нишки
7. **Миниатюрни бинарни файлове** — Единични изпълними файлове под 1MB без runtime зависимости
