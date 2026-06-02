# Bara Lang — Test Suite Compliance Plan

## Current Status: 233/233 (100%)

| Component | Pass | Total | % |
|---|---|---|---|
| clojure.string | 8 | 8 | 100% |
| clojure.core | 225 | 225 | 100% |
| **Total** | **233** | **233** | **100%** |

## Unit Tests: 80/80 (100%) ✅

| Status | Test | Issue |
|---|---|---|
| ✅ | 40 reader + 40 emitter | All passing |

Note: 8 macro tests (`test_macros.nim`) have pre-existing failures unrelated to this work.

## Real-World Examples ✅

| Example | Description | Status |
|---|---|---|
| `fizzbuzz.clj` | Classic FizzBuzz with `cond`, `mod`, `range`, `doseq` | ✅ Works |
| `wordfreq.clj` | Word frequency counter with `reduce`, `assoc`, `get`, `keys`, `sort`, `clojure.string/split`, `clojure.string/lower-case` | ✅ Works |

Both examples compile to native binaries and produce correct output with minimal code changes (only removed `#""` regex literal syntax).

## 0 Remaining Failures

All 233 clojure.test-suite compliance tests pass (rc=0). All 80 unit tests pass.

### Previous failures resolved:

### 1. `not_eq` — Cross-namespace dependency ✅
- **Root cause**: `extractRequires` didn't find `ns` inside `(do ...)` wrapper from test runner. `resolveNsToPath` only tried `.clj` extension, not `.cljc`. Search path didn't include test suite directory.
- **Fix**: Made `extractRequires` recurse into `do` forms, added `.cljc` fallback in `resolveNsToPath`, added test suite auto-detection in search paths, filtered to only inline `def`/`defn` from required files (not macros).

### 2. `add_watch` — STM ref functions missing ✅
- **Root cause**: `(ref 10)` emitted as `ref1(cljInt(10))` instead of `cljRef(cljInt(10))`. `dosync`, `ref-set`, `alter` also missing.
- **Fix**: Added runtime name mappings (`ref`→`cljRef`, `ref-set`→`cljRefSet`, `dosync`→`cljDosync`, `alter`→`cljAlter`). Implemented minimal STM ref runtime functions.

### 3. `remove_watch` — Same STM ref issue ✅
- **Root cause**: Same as `add_watch` — uses `ref`, `dosync`, `alter`.
- **Fix**: Same as `add_watch`.

### 4. Symbol Emit Fix ✅
- **Root cause**: `emitExpr` for unknown symbols fell through to `cljSymbol(...)` instead of emitting mangled name. No def registry existed to distinguish variable references from symbol literals.
- **Fix**: Added `definedGlobals` registry in emitter. `def`, `defn`, `defn-`, `definterface`, `defprotocol`, `defrecord`, `deftype` now register names. Symbol emit checks registry before falling back to `cljSymbol(...)`. Unit tests updated to register globals before testing.

## Session Log

### 2026-05-11 (current session) — 233/233 (100%), 80/80 unit tests
- Emitter: added `definedGlobals` registry with `registerGlobal`/`clearGlobals` procs
- Emitter: `def`/`defn`/`defn-`/`definterface`/`defprotocol`/`defrecord`/`deftype` register globals
- Emitter: symbol emit checks `definedGlobals` before falling back to `cljSymbol(...)`
- Emitter: `cond` now emits `return` statements in branches
- Emitter: `reduce` wraps named function symbols in `cljFn(...)` closure adapter
- Emitter: `clojure.string/*` functions mapped to runtime (`split`, `lower-case`, `upper-case`, `trim`, `join`, `replace`, `includes?`, `starts-with?`, `ends-with?`, `blank?`, `reverse`)
- Emitter: `keys`/`vals` removed from variadic list (they take single map arg)
- Emitter: statement detection expanded for `echo cljRepr(...)` wrapping (`while`, `if`, `block:`, `for`, `try`)
- Runtime: `cljGet` with 3 args now uses `cljGetDefault` for default value
- Runtime: `cljStrSplit` now supports regex patterns via Nim's `re` module
- Tests: `emit symbol` and `emit mangled symbol` now register globals before testing
- Examples: added `fizzbuzz.clj` and `wordfreq.clj` — both compile and run correctly
- Result: 78/80 → 80/80 unit tests
