# Task Board for AI Agents

> Pick a task, implement it, test it, commit it. Each task is self-contained.

## Legend
- 🔴 Large — 1+ week
- 🟡 Medium — 2-5 days
- 🟢 Small — few hours
- ⬜ Not started / 🔄 In progress / ✅ Done

---

## Phase 4: AI-Native Tooling (Complete)

| ID | Task | Status | Complexity | Files | Acceptance Criteria |
|---|---|---|---|---|---|
| T4.1 | JSON REPL mode | ✅ | 🟡 | `src/repl.nim` | `./cljnim repl --json` works, structured I/O |
| T4.2 | Batch evaluation | ✅ | 🟢 | `src/repl.nim` | `{"op":"eval-batch","forms":["(defn f[x]x)","(f 42)"]}` works |
| T4.3 | File operations | ✅ | 🟡 | `lib/cljnim_runtime.nim`, `src/emitter.nim` | `(file/read)`, `(file/write)`, `(file/ls)` work |
| T4.4 | Git operations | ✅ | 🟡 | `lib/cljnim_runtime.nim`, `src/emitter.nim` | `(git/status)`, `(git/commit)`, `(git/push)` work |
| T4.5 | nREPL protocol | ✅ | 🟡 | `src/repl.nim` | REPL speaks JSON over TCP with `--tcp PORT`. |
| T4.6 | Tool-call format | ✅ | 🟢 | `src/repl.nim` | Accept `{"tool":"cljnim/eval","args":{"form":"..."}}`. |

---

## Phase 5: Persistent Data Structures

| ID | Task | Status | Complexity | Files | Acceptance Criteria |
|---|---|---|---|---|---|
| T5.1 | HAMT Vector — core structure | ✅ | 🔴 | New: `lib/cljnim_pvec.nim`, `lib/cljnim_runtime.nim` | `PersistentVector` with 32-way trie, structural sharing. `nth` in O(log₃₂ n). 14 tests. |
| T5.2 | HAMT Vector — integration | ✅ | 🔴 | `lib/cljnim_runtime.nim`, `src/emitter.nim` | `ckVector` uses HAMT. All 51 `vecData` usages migrated. |
| T5.3 | HAMT Map | ✅ | 🔴 | New: `lib/cljnim_pmap.nim`, `lib/cljnim_runtime.nim` | Persistent Hash Map with HAMT. `assoc`, `dissoc`, `get` in O(log₃₂ n). 16 tests. |
| T5.4 | Persistent Set | ✅ | 🟡 | `lib/cljnim_runtime.nim` | Set backed by Persistent Hash Map. `conj`, `disj`, `contains?`, `get`, `count`. Reader emits `(set [items])`. |
| T5.5 | Transients | ✅ | 🟡 | `lib/cljnim_runtime.nim` | `transient`, `persistent!`, `conj!`, `assoc!` for batch mutations. Use with `let`. |

**Why HAMT matters**: Current Vector is a Nim `seq` — every `conj` copies the entire array (O(n)). Real Clojure uses Hash Array Mapped Trie for O(log₃₂ n) updates with structural sharing.

**Starting point for T5.1**: Read `lib/cljnim_vector.nim` (if exists) or research Clojure's `PersistentVector.java`. Key concepts: 32-way branching, path copying, tail optimization.

---

## Phase 6: Clojure Core Library

| ID | Task | Status | Complexity | Files | Acceptance Criteria |
|---|---|---|---|---|---|
| T6.1 | `str` — string concatenation | ✅ | 🟢 | `lib/cljnim_runtime.nim`, `src/emitter.nim` | `(str "a" 1 true)` → `"a1true"`. `cljStrConcat` in runtime. |
| T6.2 | `pr-str` — readable representation | ✅ | 🟢 | `lib/cljnim_runtime.nim` | `(pr-str [1 2 3])` → `"[1 2 3]"`. `cljPrStrConcat` in runtime. |
| T6.3 | `slurp` — read file to string | ✅ | 🟢 | `lib/cljnim_runtime.nim`, `src/emitter.nim` | `(slurp "file.txt")` returns content. Maps to `cljFileRead`. |
| T6.4 | `spit` — write string to file | ✅ | 🟢 | `lib/cljnim_runtime.nim`, `src/emitter.nim` | `(spit "file.txt" "content")` writes file. Maps to `cljFileWrite`. |
| T6.5 | `read-line` — read from stdin | ✅ | 🟢 | `lib/cljnim_runtime.nim` | `(read-line)` reads one line from stdin. |
| T6.6 | `range` — lazy number sequence | ✅ | 🟡 | `lib/cljnim_runtime.nim` | `(range 10)`, `(range 1 10)`, `(range 1 10 2)`. Eager with 3-arg. |
| T6.7 | `repeat`, `cycle`, `iterate` | ✅ | 🟡 | `lib/cljnim_runtime.nim` | `(repeat n x)`, `(cycle n coll)`, `(iterate n f x)`. Eager. |
| T6.8 | `take`, `drop` — seq slicing | ✅ | 🟢 | `lib/cljnim_runtime.nim` | `(take 5 (range 100))`, `(drop 5 [1 2 3 4 5])`. |
| T6.9 | `partition`, `interleave` | ✅ | 🟢 | `lib/cljnim_runtime.nim` | `(partition 2 [1 2 3 4])`, `(interleave [1 2] [3 4])`. |
| T6.10 | `meta`, `with-meta`, `vary-meta` | ✅ | 🟡 | `lib/cljnim_runtime.nim`, `src/emitter.nim` | Metadata support on vars, functions, collections. |
| T6.11 | `type`, `instance?` | ✅ | 🟢 | `lib/cljnim_runtime.nim` | `(type 42)` → `:integer`. `(instance? :integer 42)` → true. |

---

## Phase 7: Project Compilation

| ID | Task | Status | Complexity | Files | Acceptance Criteria |
|---|---|---|---|---|---|
| T7.1 | `ns` declaration parsing | ✅ | 🟡 | `src/emitter.nim` | `(ns my.app (:require [other.lib :as lib]))` parses, extracts aliases, resolves. |
| T7.2 | Multi-file compilation | ✅ | 🔴 | `src/cljnim.nim`, `src/emitter.nim` | `./cljnim run app.clj` finds required files (hyphen→underscore), inlines defs. |
| T7.3 | Module caching | ✅ | 🟡 | `src/cljnim.nim` | Compiled `.nim` files cached in `nimcache/`. Rebuild only if source changed. |
| T7.4 | Dependency resolution | ✅ | 🔴 | New: `src/deps.nim`, `tests/test_deps.nim` | Read `deps.edn` format. Download Git deps to `.deps/`. `cljnim deps` command. 12 tests. |

---

## Phase 8: Self-Hosted REPL

| ID | Task | Status | Complexity | Files | Acceptance Criteria |
|---|---|---|---|---|---|
| T8.1 | In-memory compilation | ✅ | 🔴 | `src/eval.nim`, `src/repl.nim` | Tree-walking interpreter evaluates common forms in <1ms, no temp files. Falls back to compilation for complex cases. 66 tests. |
| T8.2 | Fast REPL startup | ✅ | 🟡 | `src/eval.nim`, `src/repl.nim` | REPL eval in ~0.02ms (vs 1133ms compiled). Sub-millisecond for arithmetic, collections, higher-order fns. |
| T8.3 | Hot code reloading | ✅ | 🟡 | `src/eval.nim` | `def`/`defn` update environment immediately. Redefined functions used by all callers at call time. |

---

## Phase 9: Concurrency

| ID | Task | Status | Complexity | Files | Acceptance Criteria |
|---|---|---|---|---|---|
| T9.1 | Atoms (CAS) | ✅ | 🟡 | `lib/cljnim_runtime.nim` | `(def a (atom 0))`, `(swap! a inc)`, `(reset! a 42)`, `(deref a)`. Already implemented. |
| T9.2 | Agents | ✅ | 🟡 | `lib/cljnim_runtime.nim`, `src/eval.nim` | `(def a (agent 0))`, `(send a inc)`, `(deref a)`. Sync dispatch in interpreter, async-ready in runtime. |
| T9.3 | core.async channels | ✅ | 🔴 | New: `lib/cljnim_async.nim`, `src/eval.nim` | `(chan)`, `(chan n)`, `(>! ch val)`, `(<! ch)`, `(close! ch)`, `(go ...)`. Interpreter-first. |

---

## Quick Wins (do these first!)

These tasks are **small, well-defined, and high impact**:

1. **T6.1 `str`** ✅ — Done. `cljStrConcat` in runtime, `str` mapping in emitter.
2. **T6.3 `slurp`** ✅ — Done. ``(slurp "file.txt")`` works.
3. **T6.4 `spit`** ✅ — Done. ``(spit "file.txt" "content")`` works.
4. **T6.8 `take`, `drop`** ✅ — Done. `cljTake`, `cljDrop` in runtime, emitter mappings.
5. **T6.11 `type`, `instance?`** ✅ — Done. `cljType`, `cljInstanceP` in runtime.
6. **T4.6 Tool-call format** ✅ — Done. REPL accepts `{"tool":"cljnim/eval","args":{"form":"..."}}`.

---

## Phase 10: AI Integration + Core Polish (9 May 2026)

| ID | Task | Status | Complexity | Files | Acceptance Criteria |
|---|---|---|---|---|---|
| T10.1 | AI error messages — cache + full coverage | ✅ | 🟡 | `src/ai_assist.nim`, `src/cljnim.nim` | Error cache (50 entries, TTL 1h). ReaderError/EmitterError get AI explanations. |
| T10.2 | AI code generation — eval builtin + REPL | ✅ | 🟡 | `src/eval.nim`, `src/repl.nim` | `(ai/generate "...")` in interpreter. `:ai`, `ai-generate` in all REPL modes. |
| T10.3 | AI optimization hints | ✅ | 🟢 | `src/eval.nim`, `src/repl.nim` | `(ai/optimize "...")` in interpreter. `:optimize`, `ai-optimize` in all REPL modes. |
| T10.4 | AI debugging — special form | ✅ | 🟡 | `src/eval.nim`, `src/repl.nim` | `(ai/debug expr)` as special form. `:debug`, `ai-debug` in all REPL modes. |
| T10.5 | try/catch/finally — full implementation | ✅ | 🟡 | `src/emitter.nim`, `tests/test_emitter.nim` | Exception type respected. Binding is cljMap with :type/:message. 4 tests. |
| T10.6 | Reader edge cases | ✅ | 🟢 | `src/reader.nim`, `tests/test_reader.nim` | `-.5`, `+.25`, `1e5`, `1.5e-3`, `-.5e-3`, `.25`. Scientific notation. 13 tests. |
| T10.7 | CljVal type unification | ✅ | 🔴 | `src/types.nim`, `lib/cljnim_runtime.nim`, `src/runtime.nim`, `lib/cljnim_runtime_js.nim` | Identical CljKind enum (15 values) across all 4 files. All case statements cover new variants. |

## Phase 11: BRing Compiler Fixes (12 May 2026)

Real-world fixes discovered during BRing web framework development.

| ID | Task | Status | Complexity | Files | Acceptance Criteria |
|---|---|---|---|---|---|
| T11.1 | Docstrings in `defn`/`defn-` | ✅ | 🟢 | `src/emitter.nim` | `(defn f "doc" [x] ...)` compiles correctly. |
| T11.2 | Multi-arity `defn` | ✅ | 🟡 | `src/emitter.nim` | `(defn f ([x] ...) ([x y] ...))` dispatches by `args.len`. |
| T11.3 | Keyword-as-function `(:key map)` | ✅ | 🟢 | `src/emitter.nim` | `(:name person)` emits `cljGet(person, keyword)` instead of `cljApply`. |
| T11.4 | `&` rest parameters | ✅ | 🟡 | `src/emitter.nim` | `(defn f [x & rest] ...)` accepts variadic args as `seq[CljVal]`. |
| T11.5 | Nim interop name mangling | ✅ | 🟢 | `src/emitter.nim` | `nim/foo-bar` emits `foo_bar` in Nim. `sanitizeNimIdent` for interop chains. |
| T11.6 | `getLibPath()` + `--lib-path` flag | ✅ | 🟢 | `src/cljnim.nim`, `src/repl.nim` | `--lib-path <dir>` CLI flag. Checks CLI → env → cwd → appDir. |
| T11.7 | `:paths` in `deps.edn` | ✅ | 🟢 | `src/deps.nim` | Parses `:paths` and includes in `searchPaths`. |
| T11.8 | `loop` + `if/else` discard fix | ✅ | 🟡 | `src/emitter.nim` | `loopResult` variable. `loop` returns value correctly in all branches. |
| T11.9 | `clj_` prefix for identifiers | ✅ | 🟢 | `src/emitter.nim` | All generated procs get `clj_` prefix. Nim interop excluded. |
| T11.10 | `when isMainModule` skip for libs | ✅ | 🟢 | `src/emitter.nim` | `emitProgramLib` skips `when isMainModule` guard. |
| T11.11 | `try`/`catch`/`finally` fixes | ✅ | 🟢 | `src/emitter.nim` | `finally` discards expression results. `catch` uses original name for scope. |
| T11.12 | First-class `defn` functions | ✅ | 🟡 | `src/emitter.nim` | `defn` symbols used as values emit `cljFn(...)` wrapper. Direct calls unchanged. |
| T11.13 | `loop` in expression context (IIFE) | ✅ | 🟡 | `src/emitter.nim` | `loop` wraps in `(proc(): CljVal = ...)()` when `needsValue=true`. |

---

## How to claim a task

1. Read this file
2. Pick an unclaimed task (marked ⬜)
3. Implement it
4. Run `make test && make check`
5. Update this file: change ⬜ to ✅
6. Commit: `(git/commit "T6.1: Add str function")`
7. Push: `(git/push)`
