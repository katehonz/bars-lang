# Pure Clojure: Project Structure and Tools

## Table of Contents

1. [Project Structure](#1-project-structure)
2. [deps.edn and CLI Tools](#2-depsedn-and-cli-tools)
3. [Testing Infrastructure](#3-testing-infrastructure)
4. [Development Workflow](#4-development-workflow)
5. [Code Quality Tools](#5-code-quality-tools)
6. [Building and Deployment](#6-building-and-deployment)
7. [Library Ecosystem](#7-library-ecosystem)
8. [Debugging Techniques](#8-debugging-techniques)
9. [Index](#9-index)

---

## 1. Project Structure

### 1.1 Typical Project Layout

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

### 1.2 Namespaces as File Paths

Namespaces map to file paths:

```clojure
;; src/myproject/core.clj
(ns myproject.core)

;; src/myproject/util.clj
(ns myproject.util)

;; src/myproject/spec/user.clj
(ns myproject.spec.user)
```

### 1.3 Multi-module Projects

```clojure
;; deps.edn with multiple modules
{:paths ["src" "modules/common/src"]
 :deps {org.clojure/clojure {:mvn/version "1.11.1"}}
 :aliases
 {:dev {:extra-paths ["test"]
        :extra-deps {}}}}
```

### 1.4 Source vs Test Separation

- Source code: `src/` directory
- Tests: `test/` directory
- Both added to classpath during development

---

## 2. deps.edn and CLI Tools

### 2.1 deps.edn Reference

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

### 2.2 Running Code

```bash
# Run a script
clj -M script.clj

# Run with test alias
clj -M:test -m myproject.test-runner

# Run REPL with deps
clj -M

# Run with specific deps
clj -Sdeps '{:deps {org.clojure/clojure {:mvn/version "1.11.1"}}}'
```

### 2.3 Understanding Aliases

Aliases modify classpath or behavior:

```bash
# Test with generative checking
clj -M:test:gen

# Production build
clj -M:prod build

# Dev mode with extra checks
clj -M:dev
```

### 2.4 Making Dependencies

```clojure
;; deps.edn
{:deps {io.github.clojure/data.json {:git/sha "..."}}}

;; Classpath
clj -Sdescribe  # Show effective classpath
```

---

## 3. Testing Infrastructure

### 3.1 test.check for Generative Testing

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

### 3.2 Fixtures for Setup/Teardown

```clojure
(ns myproject.test-util
  (:require [clojure.test :as t]
            [myproject.db :as db]))

(defn with-test-db [f]
  (db/connect! :test)
  (f)
  (db/disconnect!))

(defn with-logging [f]
  (println "Before test")
  (f)
  (println "After test"))

;; Apply fixtures
(t/use-fixtures :each with-test-db with-logging)
(t/use-fixtures :once db/setup-once)
```

### 3.3 Test Namespaces

```clojure
(ns myproject.core-test
  (:require [clojure.test :as t]
            [myproject.core :as core]))

(t/deftest ^:integration api-test
  "Integration tests for external API"
  ...)

;; Run specific tests
(t/run-tests 'myproject.core-test)
(t/run-tests #"myproject.*test")
```

### 3.4 Expectations-style Testing

```clojure
;; Using expectations library
(require '[expectations :refer [expect]])

(expect 4 (+ 2 2))
(expect ArithmeticException (/ 1 0))
(expect [:a :b :c] (filterv odd? [1 2 3 4]))
```

### 3.5 Midje (for readablity)

```clojure
(require '[midje.sweet :refer [fact facts =>]])

(fact "addition works"
  (+ 2 2) => 4)

(facts "about strings"
  (fact "upper-case works"
    (clojure.string/upper-case "hello") => "HELLO"))
```

---

## 4. Development Workflow

### 4.1 REPL-driven Development

```clojure
;; Start REPL
user=> (require '[myproject.core :as core] :reload)

;; Edit code, reload
user=> (require '[myproject.core :as core] :reload :verbose)

;; Reload all changed namespaces
user=> (require '[clojure.tools.namespace.repl :as ns]
                 :refer [refresh refresh-all])
user=> (refresh)
```

### 4.2 Hot Loading Code

```clojure
;; In REPL
(def server (atom nil))

(defn start-server []
  (swap! server assoc :running true))

;; After editing core, just reload
(require '[myproject.core :as core] :reload)
```

### 4.3 Source Tracking

```clojure
;; Track which files changed
(require '[clojure.java.io :as io]
         '[clojure.tools.namespace.track :as track])

(defn track-changes []
  (let [tracker (atom (track/tracker))]
    (fn []
      (swap! tracker track/step)
      (track/deps @tracker))))
```

### 4.4 Rich Comment Blocks

```clojure
(defn process-data [input]
  {:pre [(sequential? input)]}
  (mapv inc input))

(comment
  ;; Development experiments
  (process-data [1 2 3])

  ;; Test edge cases
  (process-data [])

  ;; Interactive debugging
  (def test-data (load-data))
  )
```

---

## 5. Code Quality Tools

### 5.1 eastwood (Linter)

```clojure
;; deps.edn alias
:lint {:extra-deps {lancem对待/clojure-eastwood {:mvn/version "..."}}}

;; Run
clj -M:lint -m eastwood.lint
```

### 5.2 clj-kondo (Fast Linter)

```bash
# Install
brew install clj-kondo

# Run on project
clj-kondo --lint src/
```

### 5.3 Formatting with cljfmt

```clojure
;; deps.edn
:format {:extra-deps {com.github.cljfmt/cljfmt {:mvn/version "..."}}}

;; Check
clj -M:format check src/

;; Fix
clj -M:format fix src/
```

### 5.4 Typed Clojure (Optional Type Checking)

```clojure
(require '[clojure.core.typed :as t])

(t/ann my-function [t/Int -> t/Int])
(defn my-function [x]
  (inc x))

;; Check types
(t/check-ns)
```

---

## 6. Building and Deployment

### 6.1 Building Uberjars

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

### 6.2 Native Image with GraalVM

```bash
# Compile Clojure to JVM bytecode first
clojure -M:build compile

# Build native image
native-image --initialize-at-build-time=clojure.lang.RT \
             -jar myapp.jar
```

### 6.3 Docker Integration

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
# GitHub Actions example
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

## 7. Library Ecosystem

### 7.1 Web Development

```clojure
;; HTTP Server - Ring (pure Clojure)
{:deps {ring/ring {:mvn/version "1.9.5"}}

;; Routes - Compojure
{:deps {compojure/compojure {:mvn/version "1.6.2"}}}
```

### 7.2 Data Processing

```clojure
;; Data manipulation
{:deps {zipkin/zikaron {:mvn/version "1.0.0"}}}

;; CSV handling
{:deps {org.clojure/data.csv {:mvn/version "1.0.1"}}

;; JSON (pure Clojure)
{:deps {org.clojure/data.json {:mvn/version "2.4.0"}}}
```

### 7.3 Async Programming

```clojure
;; Core async is built-in
;; No additional dependencies for channels

;; For additional async patterns
{:deps {manifold/manifold {:mvn/version "0.4.0"}}}
```

### 7.4 Database Access

```clojure
;; Pure Clojure JDBC wrapper
{:deps {org.clojure/java.jdbc {:mvn/version "0.7.12"}}

;; SQL DSL
{:deps {sqlkorma/sqlkorma {:mvn/version "0.4.0"}}}
```

### 7.5 Testing Libraries

```clojure
{:deps {expectations/expectations {:mvn/version "2.0.0"}}
       {midje/midje {:mvn/version "1.9.10"}}
       {org.clojure/test.check {:mvn/version "1.1.1"}}}
```

### 7.6 Finding Libraries

- Clojars.org - Community repository
-.Clojuredocs.org - Documentation with examples
- Awesome-clojure - Curated list

---

## 8. Debugging Techniques

### 8.1 Print Debugging

```clojure
;; Simple prints
(println "Debug:" variable)

;; Withprympr
(require '[clojure.pprint :as pp])
(pp/pprint data-structure)

;; Tap for debugging
(tap> {:event :processing :data x})
```

### 8.2 Stack Traces

```clojure
;; Get full stack trace
(.printStackTrace *e)

;; Ex-data for spec errors
(try
  (s/conform ::spec value)
  (catch Exception e
    (ex-data e)))
```

### 8.3 REPL Debugging

```clojure
;; Inspect values
user> (def data (s/gen ::my-spec))
user> data

;; Step through with trace
(trace (reduce + (range 10)))
```

### 8.4 Watching State

```clojure
;; Watch atoms
(add-watch my-atom :debug
           (fn [k r o n]
             (println "Changed:" o "->" n)))

;; Watch refs in transaction
(dosync
  (trace (alter my-ref f)))
```

### 8.5 Breakpoints

```clojure
;; Using dbg macro (from tools.trace)
(require '[clojure.tools.trace :as t])
(t/dbg expression)
```

### 8.6 Logging

```clojure
(require '[clojure.tools.logging :as log])

(log/info "Application started")
(log/debug "Processing" :item item)
(log/error e "Failed processing")
```

---

## 9. Index

### A

- `add-watch` - [8.4](#84-watching-state)
- `alias` - [1.2](#12-depsedn-reference)

### B

- `build` - [6.1](#61-building-uberjars)

### C

- `check-ns` - [5.4](#54-typed-clojure-optional-type-checking)
- `clojure.tools.namespace` - [4.1](#41-repl-driven-development)
- `comment` - [4.4](#44-rich-comment-blocks)

### D

- `dbg` - [8.5](#85-breakpoints)
- `deps.edn` - [2.1](#21-depsedn-reference)

### E

- `eastwood` - [5.1](#51-eastwood-linter)

### F

- `find-libs` - [7.6](#76-finding-libraries)

### G

- `gen` - [3.1](#31-testcheck-for-generative-testing)

### I

- `instrument` - [3.1](#31-testcheck-for-generative-testing)

### L

- `lein` - [6.3](#63-docker-integration)
- `load-file` - [4.2](#42-reloading-code)

### M

- `memoize` - [4.3](#43-source-tracking)
- `merge` - [8.2](#82-stack-traces)

### N

- `ns-publics` - [4.1](#41-repl-driven-development)

### P

- `pp/pprint` - [8.1](#81-print-debugging)
- `profile` - [8.3](#83-repl-debugging)

### Q

- `quick-check` - [3.1](#31-testcheck-for-generative-testing)

### R

- `reduce` - [8.3](#83-repl-debugging)
- `refresh` - [4.1](#41-repl-driven-development)
- `reload` - [4.1](#41-repl-driven-development)
- `run-tests` - [3.3](#33-test-namespaces)

### S

- `s/conform` - [8.2](#82-stack-traces)
- `s/gen` - [3.1](#31-testcheck-for-generative-testing)
- `shadow` - [6.2](#62-native-image-with-graalvm)
- `spec` - [8.2](#82-stack-traces)

### T

- `tap>` - [8.1](#81-print-debugging)
- `test` - [3.3](#33-test-namespaces)
- `trace` - [8.5](#85-breakpoints)
- `track` - [4.3](#43-source-tracking)

### U

- `uberjar` - [6.1](#61-building-uberjars)
- `use-fixtures` - [3.2](#32-fixtures-for-setupteardown)

### V

- `verify` - [3.1](#31-testcheck-for-generative-testing)

---

*Pure Clojure: Project Structure and Tools*
