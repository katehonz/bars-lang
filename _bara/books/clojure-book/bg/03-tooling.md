# Чист Clojure: Структура на проекта и инструменти

## Съдържание

1. [Структура на проекта](#1-структура-на-проекта)
2. [deps.edn и CLI инструменти](#2-depsedn-и-cli-инструменти)
3. [Инфраструктура за тестване](#3-инфраструктура-за-тестване)
4. [Работен процес за разработка](#4-работен-процес-за-разработка)
5. [Инструменти за качество на кода](#5-инструменти-за-качество-на-кода)
6. [Изграждане и деплойване](#6-изграждане-и-деплойване)
7. [Екосистема от библиотеки](#7-екосистема-от-библиотеки)
8. [Техники за дебъгване](#8-техники-за-дебъгване)
9. [Индекс](#9-индекс)

---

## 1. Структура на проекта

### 1.1 Типична структура на проект

```
myproject/
├── deps.edn
├── src/
│   └── myproject/
│       ├── core.clj
│       ├── util.clj
│       └── spec/
│           └── core_spec.clj
├── test/
│   └── myproject/
│       ├── core_test.clj
│       └── util_test.clj
├── resources/
├── doc/
│   └── intro.md
└── README.md
```

### 1.2 Namespace като файлови пътища

Namespaces се мапват към файлови пътища:

```clojure
;; src/myproject/core.clj
(ns myproject.core)

;; src/myproject/util.clj
(ns myproject.util)

;; src/myproject/spec/user.clj
(ns myproject.spec.user)
```

### 1.3 Multi-module проекти

```clojure
;; deps.edn с множество модули
{:paths ["src" "modules/common/src"]
 :deps {org.clojure/clojure {:mvn/version "1.11.1"}}
 :aliases
 {:dev {:extra-paths ["test"]
        :extra-deps {}}}}
```

### 1.4 Разделяне на Source и Test

- Source код: директория `src/`
- Тестове: директория `test/`
- И двете се добавят към classpath по време на разработка

---

## 2. deps.edn и CLI инструменти

### 2.1 Референция на deps.edn

```clojure
{:deps {org.clojure/clojure {:mvn/version "1.11.1"}
        org.clojure/data.json {:mvn/version "2.4.0"}
        clojure.java-time/clojure.java-time {:mvn/version "1.4.2"}
        }
 :paths {:src ["src"]
         :test ["test"]}
 :aliases
 {:test {:extra-paths ["test"]
         :extra-deps {org.clojure/test.check {:mvn/version "1.1.1"}}}
  :dev {:jvm-opts ["-Xmx4g"]}
  :bench {:extra-deps {criterium/criterium {:mvn/version "0.4.4"}}}}
```

### 2.2 Пускане на код

```bash
# Пускане на скрипт
clj -M script.clj

# Пускане с test alias
clj -M:test -m myproject.test-runner

# Пускане на REPL с deps
clj -M

# Пускане с конкретни deps
clj -Sdeps '{:deps {org.clojure/clojure {:mvn/version "1.11.1"}}}'
```

### 2.3 Разбиране на aliases

Aliases модифицират classpath или поведение:

```bash
# Тест с generative проверка
clj -M:test:gen

# Production build
clj -M:prod build

# Dev mode с допълнителни проверки
clj -M:dev
```

### 2.4 Създаване на зависимости

```clojure
;; deps.edn
{:deps {io.github.clojure/data.json {:git/sha "..."}}}

;; Classpath
clj -Sdescribe  # Покажи ефективния classpath
```

---

## 3. Инфраструктура за тестване

### 3.1 test.check за генеративно тестване

```clojure
(require '[clojure.test.check :as tc]
         '[clojure.test.check.generators :as gen]
         '[clojure.test.check.properties :as prop])

(def prop-sort-idempotent
  (prop/for-all
    [v (gen/vector gen/int)]
    (= (sort v) (sort (sort v)))))

(tc/quick-check 100 prop-sort-idempotent)
;; => {:result true, :pass? true, ...}
```

### 3.2 Fixtures за setup/teardown

```clojure
(ns myproject.test-util
  (:require [clojure.test :as t]
            [myproject.db :as db]))

(defn with-test-db [f]
  (db/connect! :test)
  (f)
  (db/disconnect!))

(defn with-logging [f]
  (println "Преди тест")
  (f)
  (println "След тест"))

;; Прилагане на fixtures
(t/use-fixtures :each with-test-db with-logging)
(t/use-fixtures :once db/setup-once)
```

### 3.3 Тестови namespace-и

```clojure
(ns myproject.core-test
  (:require [clojure.test :as t]
            [myproject.core :as core]))

(t/deftest ^:integration api-test
  "Интеграционни тестове за външно API"
  ...)

;; Пускане на конкретни тестове
(t/run-tests 'myproject.core-test)
(t/run-tests #"myproject.*test")
```

### 3.4 Expectations-style тестване

```clojure
;; Използване на expectations библиотека
(require '[expectations :refer [expect]])

(expect 4 (+ 2 2))
(expect ArithmeticException (/ 1 0))
(expect [:a :b :c] (filterv odd? [1 2 3 4]))
```

### 3.5 Midje (за четимост)

```clojure
(require '[midje.sweet :refer [fact facts =>]])

(fact "събирането работи"
  (+ 2 2) => 4)

(facts "за низовете"
  (fact "upper-case работи"
    (clojure.string/upper-case "hello") => "HELLO"))
```

---

## 4. Работен процес за разработка

### 4.1 REPL-driven разработка

```clojure
;; Стартиране на REPL
user=> (require '[myproject.core :as core] :reload)

;; Редактиране на код, презареждане
user=> (require '[myproject.core :as core] :reload :verbose)

;; Презареждане на всички променени namespaces
user=> (require '[clojure.tools.namespace.repl :as ns]
                 :refer [refresh refresh-all])
user=> (refresh)
```

### 4.2 Hot Loading на код

```clojure
;; В REPL
(def server (atom nil))

(defn start-server []
  (swap! server assoc :running true))

;; След редактиране на core, просто презаредете
(require '[myproject.core :as core] :reload)
```

### 4.3 Проследяване на source

```clojure
;; Проследяване на променени файлове
(require '[clojure.java.io :as io]
         '[clojure.tools.namespace.track :as track])

(defn track-changes []
  (let [tracker (atom (track/tracker))]
    (fn []
      (swap! tracker track/step)
      (track/deps @tracker))))
```

### 4.4 Богати comment блокове

```clojure
(defn process-data [input]
  {:pre [(sequential? input)]}
  (mapv inc input))

(comment
  ;; Експерименти по време на разработка
  (process-data [1 2 3])

  ;; Тестване на гранични случаи
  (process-data [])

  ;; Интерактивно дебъгване
  (def test-data (load-data))
  )
```

---

## 5. Инструменти за качество на кода

### 5.1 eastwood (Linter)

```clojure
;; deps.edn alias
:lint {:extra-deps {lancem待/clojure-eastwood {:mvn/version "..."}}}

;; Пускане
clj -M:lint -m eastwood.lint
```

### 5.2 clj-kondo (Бърз Linter)

```bash
# Инсталиране
brew install clj-kondo

# Пускане върху проект
clj-kondo --lint src/
```

### 5.3 Форматиране с cljfmt

```clojure
;; deps.edn
:format {:extra-deps {com.github.cljfmt/cljfmt {:mvn/version "..."}}}

# Проверка
clj -M:format check src/

# Поправка
clj -M:format fix src/
```

### 5.4 Typed Clojure (Незадължително проверяване на типове)

```clojure
(require '[clojure.core.typed :as t])

(t/ann my-function [t/Int -> t/Int])
(defn my-function [x]
  (inc x))

;; Проверка на типовете
(t/check-ns)
```

---

## 6. Изграждане и деплойване

### 6.1 Изграждане на Uberjars

```clojure
;; tools.build
(require '[clojure.tools.build.api :as b])

(def lib 'com.mycompany/myapp)
(def version "1.0.0")
(def target-dir "target")

(defn uberjar [opts]
  (b/java-command
    {:basis (:basis opts)
     :main 'myproject.core
     :jar-file (b/path target-dir "myapp.jar")
     :uber-jar true}))
```

### 6.2 Native Image с GraalVM

```bash
# Компилиране на Clojure до JVM bytecode първо
clojure -M:build compile

# Изграждане на native image
native-image --initialize-at-build-time=clojure.lang.RT \
             -jar myapp.jar
```

### 6.3 Docker интеграция

```dockerfile
FROM clojure:openjdk-17-lein

WORKDIR /app
COPY deps.edn .
RUN clj -M -P

COPY src src
COPY test test

ENVlein uberjar
ENTRYPOINT ["java", "-jar", "target/myapp.jar"]
```

### 6.4 CI/CD Pipeline

```yaml
# GitHub Actions пример
name: Clojure CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: DeLaGuardo/setup-clojure@10
        with:
          backend: 'cli'
          version: '1.11.1'
      - run: clj -M:test
      - run: clj -M:lint
```

---

## 7. Екосистема от библиотеки

### 7.1 Web разработка

```clojure
;; HTTP Сървър - Ring (чист Clojure)
{:deps {ring/ring {:mvn/version "1.9.5"}}

;; Routes - Compojure
{:deps {compojure/compojure {:mvn/version "1.6.2"}}}
```

### 7.2 Обработка на данни

```clojure
;; Манипулация на данни
{:deps {zipkin/zikaron {:mvn/version "1.0.0"}}}

;; CSV handling
{:deps {org.clojure/data.csv {:mvn/version "1.0.1"}}

;; JSON (чист Clojure)
{:deps {org.clojure/data.json {:mvn/version "2.4.0"}}}
```

### 7.3 Асинхронно програмиране

```clojure
;; Core async е вграден
;; Няма допълнителни зависимости за канали

;; За допълнителни async модели
{:deps {manifold/manifold {:mvn/version "0.4.0"}}}
```

### 7.4 Достъп до бази данни

```clojure
;; Чист Clojure JDBC wrapper
{:deps {org.clojure/java.jdbc {:mvn/version "0.7.12"}}

;; SQL DSL
{:deps {sqlkorma/sqlkorma {:mvn/version "0.4.0"}}}
```

### 7.5 Библиотеки за тестване

```clojure
{:deps {expectations/expectations {:mvn/version "2.0.0"}}
       {midje/midje {:mvn/version "1.9.10"}}
       {org.clojure/test.check {:mvn/version "1.1.1"}}}
```

### 7.6 Намиране на библиотеки

- Clojars.org - Общностно хранилище
- Clojuredocs.org - Документация с примери
- Awesome-clojure - Куриран списък

---

## 8. Техники за дебъгване

### 8.1 Print дебъгване

```clojure
;; Прости отпечатвания
(println "Debug:" variable)

;; С pretty printer
(require '[clojure.pprint :as pp])
(pp/pprint data-structure)

;; Tap за дебъгване
(tap> {:event :processing :data x})
```

### 8.2 Stack traces

```clojure
;; Вземете пълен stack trace
(.printStackTrace *e)

;; Ex-data за spec грешки
(try
  (s/conform ::spec value)
  (catch Exception e
    (ex-data e)))
```

### 8.3 REPL дебъгване

```clojure
;; Инспектиране на стойности
user> (def data (s/gen ::my-spec))
user> data

;; Стъпка по стъпка с trace
(trace (reduce + (range 10)))
```

### 8.4 Watching state

```clojure
;; Watch atoms
(add-watch my-atom :debug
           (fn [k r o n]
             (println "Променено:" o "->" n)))

;; Watch refs в транзакция
(dosync
  (trace (alter my-ref f)))
```

### 8.5 Breakpoints

```clojure
;; Използване на dbg macro (от tools.trace)
(require '[clojure.tools.trace :as t])
(t/dbg expression)
```

### 8.6 Logging

```clojure
(require '[clojure.tools.logging :as log])

(log/info "Приложението стартира")
(log/debug "Обработка" :item item)
(log/error e "Неуспех при обработка")
```

---

## 9. Индекс

### A

- `add-watch` - [8.4](#84-watching-state)
- `alias` - [1.2](#12-референция-на-depsedn)

### B

- `build` - [6.1](#61-изграждане-на-uberjars)

### C

- `check-ns` - [5.4](#54-typed-clojure-незадължително-проверяване-на-типове)
- `clojure.tools.namespace` - [4.1](#41-repl-driven-разработка)
- `comment` - [4.4](#44-богати-comment-блокове)

### D

- `dbg` - [8.5](#85-breakpoints)
- `deps.edn` - [2.1](#21-референция-на-depsedn)

### E

- `eastwood` - [5.1](#51-eastwood-linter)

### F

- `find-libs` - [7.6](#76-намиране-на-библиотеки)

### G

- `gen` - [3.1](#31-testcheck-за-генеративно-тестване)

### I

- `instrument` - [3.1](#31-testcheck-за-генеративно-тестване)

### L

- `lein` - [6.3](#63-docker-интеграция)
- `load-file` - [4.2](#42-hot-loading-на-код)

### M

- `memoize` - [4.3](#43-проследяване-на-source)
- `merge` - [8.2](#82-stack-traces)

### N

- `ns-publics` - [4.1](#41-repl-driven-разработка)

### P

- `pp/pprint` - [8.1](#81-print-дебъгване)
- `profile` - [8.3](#83-repl-дебъгване)

### Q

- `quick-check` - [3.1](#31-testcheck-за-генеративно-тестване)

### R

- `reduce` - [8.3](#83-repl-дебъгване)
- `refresh` - [4.1](#41-repl-driven-разработка)
- `reload` - [4.1](#41-repl-driven-разработка)
- `run-tests` - [3.3](#33-тестови-namespace-и)

### S

- `s/conform` - [8.2](#82-stack-traces)
- `s/gen` - [3.1](#31-testcheck-за-генеративно-тестване)
- `shadow` - [6.2](#62-native-image-с-graalvm)
- `spec` - [8.2](#82-stack-traces)

### T

- `tap>` - [8.1](#81-print-дебъгване)
- `test` - [3.3](#33-тестови-namespace-и)
- `trace` - [8.5](#85-breakpoints)
- `track` - [4.3](#43-проследяване-на-source)

### U

- `uberjar` - [6.1](#61-изграждане-на-uberjars)
- `use-fixtures` - [3.2](#32-fixtures-за-setupteardown)

### V

- `verify` - [3.1](#31-testcheck-за-генеративно-тестване)

---

*Чист Clojure: Структура на проекта и инструменти*
