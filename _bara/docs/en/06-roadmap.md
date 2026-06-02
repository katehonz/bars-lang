
[← Back to Index](index.md)

---

# Development Roadmap

## Phase 0: Compiler Core ✅
- [x] Clojure Reader (EDN parser)
- [x] Reader supports: lists `()`, vectors `[]`, maps `{}`, strings, keywords, symbols, numbers, booleans, nil
- [x] Reader supports: quote `'`, syntax-quote `` ` ``, unquote `~`, unquote-splicing `~@`
- [x] Reader supports: comments `;`, read-all
- [x] AST → Nim Emitter
- [x] CLI (`compile`, `run`, `read`, `repl`)
- [x] Special forms: `def`, `defn`, `fn`, `let`, `if`, `do`, `quote`
- [x] Special forms: `when`, `cond`
- [x] Arithmetic operators: `+`, `-`, `*`, `/`
- [x] Comparison operators: `=`, `not=`, `not`, `<`, `>`, `<=`, `>=`
- [x] Core functions: `println`, `map`, `filter`, `reduce`
- [x] Runtime type system: `CljVal` with `nil`, `bool`, `int`, `float`, `string`, `keyword`, `symbol`, `list`, `vector`, `map`, `fn`, `atom`

## Phase 1: Macro System ✅
- [x] `macroexpand`, `macroexpand-1`
- [x] `syntax-quote`, `unquote`, `unquote-splicing`
- [x] `gensym`
- [x] `defmacro` (user-defined macros)
- [x] Built-in macros: `->`, `->>`, `and`, `or`, `when`, `when-not`, `cond`
- [x] Built-in macros: `cond->`, `cond->>`, `doto`, `as->`, `some->`, `some->>`
- [x] Built-in macros: `for`, `doseq`, `dotimes`
- [x] Built-in macros: `when-let`, `if-let`
- [x] Built-in macros: `comment`, `assert`, `with-open`

## Phase 2: REPL & Tooling ✅
- [x] Human REPL (`:help`, `:defs`, `:clear`, `:ns`, `:quit`)
- [x] JSON REPL (`--json`) with structured I/O
- [x] Batch evaluation (`eval-batch`)
- [x] Structured errors (type, message, form, line)
- [x] Session persistence for `def`/`defn` definitions

## Phase 3: Nim Interop ✅
- [x] Call Nim functions: `(nim/math/sin x)`, `(nim/strutils/toUpper s)`
- [x] C FFI via Nim `importc`

## Phase 4: AI-Native Tooling ✅
- [x] File operations: `(file/read "path")`, `(file/write "path" "content")`, `(file/append "path" "content")`
- [x] File operations: `(file/ls "dir")`, `(file/exists? "path")`
- [x] Git operations: `(git/status)`, `(git/commit "msg")`, `(git/push)`
- [x] Git operations: `(git/diff)`, `(git/log)`
- [x] nREPL protocol compatibility (JSON over TCP, `--tcp PORT`)
- [x] Tool-call format for AI framework integration

## Phase 5: Persistent Data Structures ✅ (Complete)
- [x] Persistent Vector (Hash Array Mapped Trie, 32-way branching)
- [x] Persistent Map (HAMT) — `pmapAssoc`, `pmapDissoc`, `pmapGet` in O(log₃₂ n)
- [x] Persistent Set — backed by HAMT map, `conj`/`disj`/`contains?`/`get`
- [x] `conj`, `assoc`, `dissoc`, `get`, `get-in`
- [x] `nth`, `first`, `rest`, `last`, `count` on persistent collections
- [x] Transients for batch mutations
- [x] `conj!`, `assoc!`, `persistent!`

## Phase 6: Clojure Core Library ✅ (Complete)
- [x] `range` (0/1/2/3 args), `repeat`, `cycle`, `iterate`
- [x] `take`, `drop`, `partition`, `interleave`, `concat`
- [x] `str`, `pr-str`, `println`, `prn`
- [x] `slurp`, `spit`, `read-line`
- [x] `meta`, `with-meta`, `vary-meta`
- [x] `type`, `instance?`, `satisfies?`

## Phase 7: Project Compilation
- [x] Compile entire projects (not just single files)
- [x] Namespace system (`ns`, `(:require [lib :as alias])`)
- [x] Module caching for faster REPL startup
- [x] Dependency resolution (deps.edn, Git deps to .deps/)

## Phase 8: Self-Hosted REPL ✅
- [x] Compile forms in memory (tree-walking interpreter, <1ms eval)
- [x] Fast REPL startup (~0.02ms per eval vs 1133ms compiled)
- [x] Hot code reloading (def/defn update env immediately)

## Phase 9: Concurrency ✅
- [x] Atoms (compare-and-swap)
- [x] Agents (send, await, deref — sync dispatch in interpreter)
- [x] core.async channels (chan, >!, <!, close!, go — interpreter-first)

## Known Issues
- `->>` threading macro with nested `map`/`reduce` requires proper macro expansion context

## Recent Bug Fixes (2026-05-08)
- Fixed: ffi/interop examples — temp files now use isolated subdirectories to avoid shadowing Nim stdlib modules (e.g., `math.nim` shadowing `import math`)
- Fixed: `quot`/`rem` — added `cljQuot`/`cljRem` to runtime + interpreter support
- Cleanup: removed unused `processAgentActions` proc, unused `sequtils` import in repl.nim
