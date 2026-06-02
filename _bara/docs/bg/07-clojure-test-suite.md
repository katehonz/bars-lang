
[← Обратно към индекса](index.md)

---

# Съвместимост с Clojure Test Suite

Bara Lang участва в между-диалектния **[jank-lang/clojure-test-suite](https://github.com/jank-lang/clojure-test-suite)** — стандартният Clojure тестови пакет за съответствие, който валидира поведението на всички Clojure диалекти.

## Поддържани диалекти

Clojure Test Suite се поддържа официално за следните диалекти:

| Диалект | Статус | Runtime |
|---------|--------|---------|
| Clojure (JVM) | ✅ Официален | JVM |
| ClojureScript | ✅ Официален | JavaScript / Node.js |
| Babashka | ✅ Официален | GraalVM native-image |
| Clojure CLR | ✅ Официален | .NET CLR |
| Basilisp | ✅ Официален | Python |
| **Bara Lang** | 🚀 Кандидат | **Nim → C → Native** |

## Бърз старт

### 1. Клониране на тестовия пакет

```bash
git clone https://github.com/jank-lang/clojure-test-suite.git /tmp/clojure-test-suite
```

### 2. Пускане на индивидуални тестове

Използвайте `test_single.py` за пускане на конкретен тестов файл:

```bash
python3 test_single.py /tmp/clojure-test-suite/test/clojure/core_test/nil_qmark.cljc
```

### 3. Пускане на пакет

```bash
python3 test_single.py
# Пуска: zipmap, zero_qmark, with_out_str
```

Редактирайте файла `test_single.py`, за да добавите още тестови файлове към списъка.

## Формат на тестовете

Всеки тестов файл е `.cljc` (cross-platform Clojure/ClojureScript) файл със стандартна структура:

```clojure
(ns clojure.core-test.nil-qmark
  (:require [clojure.test :as t :refer [are deftest is testing]]
            [clojure.core-test.portability :refer [when-var-exists]]))

(when-var-exists nil?
  (deftest test-nil?
    (testing "common"
      (are [in ex] (= (nil? in) ex)
        nil   true
        0     false
        false false
        ""    false))))
```

## Обработка на Reader Conditionals

`test_single.py` на Bara Lang предварително обработва `.cljc` файловете, като премахва `#?` и `#?@` reader conditionals и извлича `:default` клона:

```clojure
;; Преди
#?(:cljs :refer-macros :default :refer)

;; След
:refer

;; Преди  
#?@(:cljs [] :default [1 2 3])

;; След
[1 2 3]
```

Това следва стандартната между-диалектна конвенция — всеки диалект разрешава `:default` според своята платформа.

## Текущ обхват на тестовете

Тестовият пакет покрива **212+ функции от `clojure.core`** и **8 функции от `clojure.string`**. Bara Lang работи към пълно съответствие.

Вижте [Roadmap](06-roadmap.md) за статуса на имплементацията.

---

## Настройка на тестове за отделните диалекти

За справка, ето линкове към официалните ръководства за настройка на тестовете за други платформи:

| Диалект | Ръководство за настройка |
|---------|--------------------------|
| Clojure (JVM) | [clojure.md](https://github.com/jank-lang/clojure-test-suite/blob/main/doc/clojure.md) |
| ClojureScript | [clojurescript.md](https://github.com/jank-lang/clojure-test-suite/blob/main/doc/clojurescript.md) |
| Babashka | [babashka.md](https://github.com/jank-lang/clojure-test-suite/blob/main/doc/babashka.md) |
| Clojure CLR | [clojureclr.md](https://github.com/jank-lang/clojure-test-suite/blob/main/doc/clojureclr.md) |
| Basilisp | [basilisp.md](https://github.com/jank-lang/clojure-test-suite/blob/main/doc/basilisp.md) |
| **Bara Lang** | **Този документ** |

---

*Последно обновено: 2026-05-09*
