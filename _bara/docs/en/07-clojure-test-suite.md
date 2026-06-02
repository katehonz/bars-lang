
[← Back to Index](index.md)

---

# Clojure Test Suite Compatibility

Bara Lang participates in the cross-dialect **[jank-lang/clojure-test-suite](https://github.com/jank-lang/clojure-test-suite)** — the standard Clojure compliance test suite that validates behavior across all Clojure dialects.

## Supported Dialects

The Clojure Test Suite is officially maintained for these dialects:

| Dialect | Status | Runtime |
|---------|--------|---------|
| Clojure (JVM) | ✅ Official | JVM |
| ClojureScript | ✅ Official | JavaScript / Node.js |
| Babashka | ✅ Official | GraalVM native-image |
| Clojure CLR | ✅ Official | .NET CLR |
| Basilisp | ✅ Official | Python |
| **Bara Lang** | 🚀 Candidate | **Nim → C → Native** |

## Quick Start

### 1. Clone the Test Suite

```bash
git clone https://github.com/jank-lang/clojure-test-suite.git /tmp/clojure-test-suite
```

### 2. Run Individual Tests

Use `test_single.py` to run a specific test file:

```bash
python3 test_single.py /tmp/clojure-test-suite/test/clojure/core_test/nil_qmark.cljc
```

### 3. Run a Batch

```bash
python3 test_single.py
# Runs: zipmap, zero_qmark, with_out_str
```

Edit the `test_single.py` file to add more test files to the batch list.

## Test Format

Each test file is a `.cljc` (cross-platform Clojure/ClojureScript) file with a standard structure:

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

## Reader Conditional Handling

Bara Lang's `test_single.py` pre-processes `.cljc` files, stripping `#?` and `#?@` reader conditionals and extracting the `:default` branch:

```clojure
;; Before
#?(:cljs :refer-macros :default :refer)

;; After
:refer

;; Before  
#?@(:cljs [] :default [1 2 3])

;; After
[1 2 3]
```

This follows the standard cross-dialect convention — each dialect resolves `:default` per its platform.

## Current Test Scope

The test suite covers **212+ `clojure.core` functions** and **8 `clojure.string` functions**. Bara Lang is working toward full compliance.

See the [Roadmap](06-roadmap.md) for implementation status.

---

## Dialect-Specific Test Setup

For reference, here are links to the official dialect setup guides for running the test suite on other platforms:

| Dialect | Setup Guide |
|---------|-------------|
| Clojure (JVM) | [clojure.md](https://github.com/jank-lang/clojure-test-suite/blob/main/doc/clojure.md) |
| ClojureScript | [clojurescript.md](https://github.com/jank-lang/clojure-test-suite/blob/main/doc/clojurescript.md) |
| Babashka | [babashka.md](https://github.com/jank-lang/clojure-test-suite/blob/main/doc/babashka.md) |
| Clojure CLR | [clojureclr.md](https://github.com/jank-lang/clojure-test-suite/blob/main/doc/clojureclr.md) |
| Basilisp | [basilisp.md](https://github.com/jank-lang/clojure-test-suite/blob/main/doc/basilisp.md) |
| **Bara Lang** | **This document** |

---

*Last updated: 2026-05-09*
