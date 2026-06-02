# AI Agent Onboarding Guide

> If you are an AI reading this: welcome. This project is designed to be worked on by AI agents. Everything you need is in this repo. No human required.

## What is this project?

**Bara Lang** is a Clojure dialect that compiles to Nim, then to C, then to native binaries.

Current state: **Working compiler + REPL + macro system + file/git ops + Nim interop.**

## Quick Start (for AI agents)

```bash
# 1. Build
make build

# 2. Run tests
make test

# 3. Check everything works
make check

# 4. Try the REPL
./cljnim repl
user> (+ 1 2)
=> 3
```

## How to add a feature

### Step 1: Pick a task from TASKS.md
```bash
cat TASKS.md
```
Each task has:
- **Files to modify** — exact Nim/Clojure files
- **Acceptance criteria** — how to verify it works
- **Complexity** — Small / Medium / Large

### Step 2: Implement

Most tasks follow this pattern:

1. **If adding a Clojure core function** (e.g. `range`, `str`):
   - Add the Nim implementation in `lib/cljnim_runtime.nim`
   - Add the name mapping in `src/emitter.nim` → `runtimeName()`
   - Add a test in `tests/test_emitter.nim`
   - Add an example in `examples/`

2. **If adding emitter special form support** (e.g. `loop`/`recur`):
   - Modify `src/emitter.nim` → `emitSpecialForm()`
   - Add test in `tests/test_emitter.nim`

3. **If adding a macro** (e.g. `lazy-seq`):
   - Add macro implementation in `src/macros.nim` → `initBuiltinMacros()`
   - Add test

### Step 3: Test your change

```bash
# Build after any change
make build

# Run all tests
make test

# Run a specific example to verify
./cljnim run examples/hello.clj
./cljnim run examples/your_new_example.clj
```

### Step 4: Commit

```bash
# From Clojure code:
(git/commit "Your commit message")
(git/push)
```

Or from shell:
```bash
git add -A
git commit -m "Your commit message"
git push
```

## Project Structure

```
├── src/
│   ├── cljnim.nim       # CLI entry point — commands: compile, run, read, repl
│   ├── reader.nim       # Clojure → AST (EDN parser)
│   ├── emitter.nim      # AST → Nim code generator (~960 lines)
│   ├── macros.nim       # Macro expansion engine (~470 lines)
│   ├── repl.nim         # Human + JSON REPL
│   ├── types.nim        # AST node types
│   ├── core.nim         # Core arithmetic/runtime helpers
│   └── runtime.nim      # Additional runtime
├── lib/
│   └── cljnim_runtime.nim   # Clojure runtime in Nim (~1100 lines)
│                              # This is where Clojure functions live
├── examples/
│   ├── hello.clj        # Basic hello world
│   ├── math.clj         # Functions + recursion
│   ├── core.clj         # map/filter/reduce
│   ├── macros.clj       # defmacro, ->, ->>
│   ├── interop.clj      # Nim interop demo
│   ├── ffi.clj          # C FFI demo
│   └── ai_tools.clj     # File + Git operations
├── tests/
│   ├── test_reader.nim
│   └── test_emitter.nim
├── docs/                # Full bilingual documentation (EN + BG)
├── Makefile
└── cljnim.nimble
```

## Key Files for AI Agents

| If you want to... | Modify this file |
|---|---|
| Add a Clojure function | `lib/cljnim_runtime.nim` + `src/emitter.nim` |
| Add a special form | `src/emitter.nim` |
| Add a macro | `src/macros.nim` |
| Add REPL command | `src/repl.nim` |
| Fix a reader bug | `src/reader.nim` |
| Add file/git op | `lib/cljnim_runtime.nim` + `src/emitter.nim` |

## How the compiler works (in 5 steps)

1. **Reader** (`src/reader.nim`): Text → `CljVal` AST
2. **Macros** (`src/macros.nim`): Expands macros on `CljVal` AST
3. **Emitter** (`src/emitter.nim`): `CljVal` AST → Nim source code
4. **Nim compiler**: Nim → C
5. **C compiler**: C → binary

## Testing Strategy

Every change MUST be tested with:
1. `make test` — runs Nim unit tests
2. `make check` — runs examples
3. Manual REPL test if relevant: `./cljnim repl --json`

## Common Mistakes

1. **Forgetting `initBuiltinMacros()`**: If you add a macro but it doesn't expand, check that `initBuiltinMacros()` is called before compilation. It's called in `src/cljnim.nim` and `src/repl.nim`.

2. **Not adding to `runtimeName`**: If you add a runtime function in `lib/cljnim_runtime.nim` but Clojure can't find it, add the name mapping in `src/emitter.nim` → `runtimeName()`.

3. **String escaping**: Clojure strings with `\n` or quotes may break Nim code generation. The emitter needs to escape strings properly.

## Communication Protocol

When you finish a task, update:
1. `TASKS.md` — mark the task as done
2. `docs/ROADMAP.md` — update if phase completed
3. Commit with descriptive message

## Questions?

Read `docs/ARCHITECTURE.md` for deep technical details.
Read `docs/API.md` for REPL protocol reference.
Read `docs/GUIDE.md` for user-facing features.
