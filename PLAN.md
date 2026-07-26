# Bars — План за Разработка v6.0

> Актуален към: 2026-07-26
> Философия: Следващите версии на компилатора се пишат на Bars. Като Nim и Rust.

---

## Нова Посока (от 2026-06-05)

**Целта НЕ е просто компилаторът да може да се self-compile-не.**
Целта е следващите версии на езика да се пишат на самия Bars.

Както Nim (95.8% Nim в репото) и Rust (90.2% Rust) — bootstrap езикът (Pascal/OCaml) е почти невидим. Така и Bars: Rust bootstrap ще остане като `csources` (както Nim пази `csources_v3`), но реалната разработка ще е на Bars.

**QBE отпада като основен backend.** QBE е за малки/учебни проекти. За сериозен език трябва LLVM (като Rust) или C кодогенерация (като Nim).

---

## Какво вече имаме (Фази 0-11) ✅

Текущият Rust bootstrap компилатор (~7500 реда) покрива:
- Reader (lexer + parser), AST
- Type inference (Hindley-Milner), generics
- Ownership checker (NLL borrow checking)
- HIR lowering + оптимизации (constant folding, TCO, dead blocks)
- Три backend-а: QBE, Cranelift (JIT + AOT), LLVM
- ADTs (deftype), FFI (extern), макроси, pattern matching
- Runtime (C + Boehm GC): strings, vectors, maps, sets, I/O
- REPL, CLI, LSP, пакетна система (Bars.toml)

---

## Фаза 12: Self-Hosted Компилатор на Bars (пренаписване)

> **Архитектура на Self-Hosted компилатора** (по модел на Nim/Rust):

```
compiler/
├── reader.brs       # Lexer + Parser ✅
├── hir.brs          # AST → HIR lowering ✅
├── build.brs        # Оркестрация ✅
├── types.brs        # Type inference ✅ (не е в pipeline)
├── ownership.brs    # Ownership checker ✅ (не е в pipeline)
├── macros.brs       # Macro expansion ✅
├── modules.brs      # Модулна система ✅ (framework)
├── codegen/
│   └── llvm.brs     # LLVM IR backend ✅
└── (entry = build.brs main)
```

### Stage 0-4: Вече готово ✅

- [x] Stage 0: String tooling, CLI args, `exit` — preparatory work
- [x] Stage 1: Self-hosted Reader — lexer + parser с tagged S-expression AST (`lib/reader.brs`, 360 реда)
- [x] Stage 2: Self-hosted HIR Lowering — AST → HIR с tail call recognition (`lib/hir.brs`, 182 реда)
- [x] Stage 3: Self-hosted QBE Codegen — HIR → QBE SSA IR (`lib/qbe.brs`, 273 реда)
- [x] Stage 4: Self-hosted Build Pipeline — orchestration (`lib/build.brs`, 60 реда)
- [x] Bootstrap proof: `bars build --backend cranelift selfhost.brs` произвежда binary

### Stage 5: Self-Hosted Type Inference ✅

- [x] **12.5** Пренасяне на Hindley-Milner type inference от Rust в Bars (`compiler/types.brs`)
- [x] **12.6** Unification, generalization, instantiation в Bars
- [x] **12.7** Type environment + builtin functions в Bars
- [ ] **12.8** Интегриране в компилационния pipeline (преди HIR lowering)

**Защо първо:** Без type checker self-hosted компилаторът не може да валидира входния код. Това е критично за надеждност.

**Статус:** ~680 реда, генериран чрез `tools/gen_types.py`. Компилира се с `BARS_SKIP_TYPECHECK=1` (bootstrap pattern — като Go/Rust/Nim).
Бинарният файл работи. Интеграцията в build.brs е блокирана от Cranelift hyphen issue (`_m_types_var-id`).
Всички self-recursive функции са конвертирани към `loop`/`recur`.

### Stage 6: Self-Hosted Ownership Checker ✅

- [x] **12.9** Пренасяне на ownership checker от Rust в Bars (`compiler/ownership.brs`)
- [x] **12.10** NLL borrow checking с states (Owned, Borrowed, MutBorrowed, Moved)
- [x] **12.11** Интегриране в `build.brs` pipeline — light NLL ON by default
  - Detects use-after-move on let-bindings (exit 4)
  - Fixed `env-lookup` infinite loop (sentinel `-1` re-armed after index exhaust)
  - Real `env-pop-scope` via `pop` + update-in-parent-scope (no leak across scopes)
  - Copy inherit; string/number/bool/copy-ops; vector literals ignored (host-like)
  - Loop rebinds are not moves (counters/accumulators); self-host ownership clean

### Stage 7: Self-Hosted LLVM Backend ✅

- [x] **12.12** HIR → LLVM IR кодогенерация (`compiler/codegen/llvm.brs`)
- [x] **12.13** Генериране на LLVM IR текст (human-readable `.ll` формат)
- [x] **12.14** Интеграция: `.brs` → HIR → LLVM IR → `clang` → binary
- [x] **12.15** Поддръжка: assign, call, ops, branch, return, stringlit, params

### Stage 8: Self-Hosted Macro System ✅

- [x] **12.16** Macro expander в Bars (`compiler/macros.brs`)
- [x] **12.17** Built-in макроси: `when`, `unless`, `cond`, …
- [x] **12.18** Интегриран в `build.brs` pipeline

### Stage 9: Self-Hosted Module System ✅

- [x] **12.19** `require` parse, rename, merge-module (`compiler/modules.brs`)
- [x] **12.20** Пълна мулти-файлова компилация в self-hosted pipeline
  - Nested requires: skip re-prefix of already-mangled `_m_*` names
  - Cycle/duplicate detection via visited set (no hang)
  - Path search: exact → relative to file dir → `lib/`
  - `resolve-requires-main` seeds visited with main path + dirname base
  - self-test includes `module_demo` + `module_nested`
- [x] **12.21** Интеграция с пакетната система (Bars.toml path + git dependencies)
  - `compiler/pkg.brs`: TOML `[dependencies] name = { path|git = "..." }`
  - Walk up for Bars.toml; `find-module` resolves package name → `src/lib.brs`
  - path deps: join project dir; git deps: `git clone` → `target/bars-deps/<name>`
  - **Pins:** `branch` / `tag` (`--branch`) or `rev` (full clone + checkout); precedence rev>tag>branch
  - Cache via `.bars-dep-pin`; re-clone when pin changes
  - Examples: `pkg_app`/`pkg_lib` (path); self-test smoke for git + branch pin + cache

### Stage 10: Пълен Bootstrap 🚧

- [x] **12.22** Bars компилаторът компилира `.brs` → работещ binary (LLVM + clang)
  - HIR: temp counter (no loop-var rebind), skip non-defn top-level
  - HIR: `loop`/`recur` + `jump`; if-as-expression with join
  - LLVM: quoted ids, correct runtime names, alloca for mutables
  - Macros: flat `cond`; special-form expand (let/defn bindings not treated as calls)
  - Modules: `_m_alias_` prefix, resolve requires, subst qualified
  - Link: `clang … runtime/bars_runtime.o -lgc -lm`
- [x] **12.23a** Gen1 self-host: host → `bars-self` compiles real programs (math, match, loop, modules)
- [x] **12.23b** Gen2 binary: `bars-self` compiles `compiler/build.brs` → `bars-self2` (~120KB, 190 funcs)
- [x] **12.23c** Gen2 correctness: fixed `special-tag` hash collision (`mk-if`/`mk-do` ≡ `match`); const match patterns; polymorphic count; dominate allocas
- [x] **12.24** Identity test (IR): Gen3.ll == Gen4.ll fixed point; Gen3 compiles math/match/loop/cond
- [x] **12.25** Rust = bootstrap only (Nim `csources`): `bootstrap/FROZEN.md`, `make bars-self|identity|self-test`
- [x] **12.26** types in pipeline (default ON; soft); Gen2-safe infer (no ctx loop rebind); Gen2 suite 12/12 + identity
- [x] **12.27** ownership walk in pipeline (default ON; hard-fail); env-lookup fix; Gen1+Gen2 suite 12/12
- [x] **12.28** ownership FP reduction: scope pop, Copy inherit, no loop-moves, vector skip; self-host with ownership ON

**HIR Stage 10+ features (2026-07-26):**
- deftype → constructors as vectors `[disc, fields…]`
- match → tag checks + field binds + wildcard + **const patterns** (int/bool/nil)
- vector literals tag 28 + unwrap in let/loop/defn/params
- loop/recur + if-join; loop as expression
- C main wrapper (`bars_set_args` + `_bars_main`)
- modules: `/` operator not treated as qualifier
- reader: `special-tag` exact name match (no first_char×len collisions)
- HIR: strip `^type` meta from defn params; `(vector a b…)` → new+push; `(def x v)` assign
- HIR: top-level exprs without `main` → synthetic `main`
- modules: auto-append `.brs` on require paths; map runtime ops in LLVM

**Bootstrap (Gen1→Gen4):**
```
BARS_SKIP_TYPECHECK=1 bars build --backend cranelift compiler/build.brs -o bars-self
./bars-self examples/math.brs /tmp/m && /tmp/m          # 7\n120\n
./bars-self compiler/build.brs /tmp/bars-self2          # Gen2
./bars-self2 compiler/build.brs /tmp/bars-self3         # Gen3
./bars-self3 compiler/build.brs /tmp/bars-self4         # Gen4; .ll identical to Gen3
```


---

## Фаза 13: Преход към Bars-First Development 🔮

> **От този момент нататък, всички нови фичъри се пишат на Bars.**

### Структура на репото след bootstrap:

```
bars/
├── bootstrap/           # Rust bootstrap компилатор (замразен, само за начално компилиране)
│   └── src/             # ~7500 реда Rust (НЕ се променя вече)
├── compiler/            # Основен компилатор — НА BARS ✅
│   ├── reader.brs
│   ├── hir.brs
│   ├── types.brs
│   ├── ownership.brs
│   ├── macros.brs
│   ├── modules.brs
│   ├── codegen/
│   │   ├── llvm.brs     # Основен backend
│   │   └── c.brs        # Алтернативен C transpiler (като Nim)
│   ├── build.brs
│   └── main.brs         # CLI entry point
├── lib/                 # Стандартна библиотека (Bars)
│   ├── core.brs
│   ├── math.brs
│   ├── vector.brs
│   ├── string.brs
│   ├── map.brs
│   ├── adt.brs
│   └── test.brs
├── runtime/             # C runtime (Boehm GC) — минимален, рядко променян
│   └── bars_runtime.c
├── tests/               # Тестове (Bars + Rust)
├── examples/            # Примери (Bars)
└── docs/                # Документация
```

### Задачи на Фаза 13:

- [x] **13.0** Bars-first entry: `make bars-self`, `scripts/selfhost-test.sh`, frozen bootstrap note
- [x] **13.1** Компилаторът е в `compiler/` (не `lib/`) — reader/hir/macros/modules/llvm/build
- [x] **13.2** Подобряване на error messages (self-host)
  - `error: <kind>: …` / `warning: type: …` / `note: …` prefixes
  - Parse: unclosed list/vector, unexpected `)`/`]`, empty program, file path
  - Type soft summary + strict fail with hint; ownership UAM + file path
  - Usage lists stages, exit codes, env flags; link failures show clang command
  - **Spans:** lexer records byte offsets; `line:col` + `--> path:line:col` on parse errors
    (`bars-read-at`, `offset-to-span`, open-paren location for unclosed forms)
  - **AST offsets:** atoms `[tag val off]`; ownership UAM reports `at line:col` + arrow
  - **Types:** warnings tagged with `[path]`; `type_check_at` / `check_ownership_at`
  - **Snippets:** host-style source line + caret under column for parse/ownership
  - **Type spans:** constraints store expr offset; mismatches print `at line:col` + snippet
- [x] **13.3** Incremental compilation (light mtime skip)
  - `bars_file_mtime` / `bars_sleep_ms` in runtime; wired through host + LLVM/C maps
  - Resolve returns loaded source paths (main + requires + Bars.toml)
  - Skip backend/link when output mtime ≥ max source mtime
  - `BARS_FORCE=1` / `BARS_NO_INCREMENTAL=1` force full rebuild
- [x] **13.4** Watch mode (`bars-self watch <in.brs> <out>`)
  - Poll every 500ms; recompile when any loaded source changes
  - On failure, wait for next source change (no spam)
  - Ctrl+C to stop
- [x] **13.5** C code generation backend (`compiler/codegen/c.brs`)
  - HIR → `.c` (int64_t temps, goto labels, runtime via bars_runtime.h)
  - Opt-in: `BARS_BACKEND_C=1 ./bars-self in.brs out` → `out.c` + `cc -I. … -lgc -lm`
  - Pointer APIs cast via `(void*)(uintptr_t)` / `(int64_t)(uintptr_t)`; void map-set/spit
  - Default remains LLVM (`.ll` + clang)
  - self-test runs full C suite (14 examples); `make self-test-c`; skip with `BARS_SKIP_C_TEST=1`

---

## Фаза 14: Езиково Съзряване 🔮

> **Всичко оттук надолу се пише на Bars. Rust bootstrap-ът не се пипа.**

### 14.1 Стандартна Библиотека (разширение)

- [x] File I/O — `lib/io.brs` + runtime `bars_file_{exists,delete,append,mtime}`
  - `read-file` / `write-file` / `append-file` / `exists?` / `delete` / `mtime`
  - Sync only (async-ready API later as package)
- [x] JSON — `lib/json.brs` pure Bars parse/stringify
  - Tagged values: null/bool/num/str/arr/obj; objects as key–value pair vectors
  - Integers only (no floats); escapes for `\" \\ \n \t \r`
- [x] Regex — `lib/regex.brs` + POSIX `bars_re_is_match` / `bars_re_find`
- [x] Random — `lib/random.brs` + `bars_srand` / `bars_rand`
- [x] Time — `lib/time.brs` + `bars_time_unix` / `bars_time_ms` / `bars_sleep_ms`
- [x] CLI args — `lib/args.brs` (`has-flag?`, `flag-value`, `positionals`)

### 14.2 Tooling

- [x] Formatter — `bars-self fmt <file> [--write]`
  - `compiler/fmt.brs` pretty-prints AST (defn/if multiline; trailing newline)
  - default: stdout; `--write` overwrites the file
- [x] Linter — `bars-self lint <file>` (exit 5 on issues)
  - style: tabs, trailing whitespace, bare CR, lines > 100 cols
  - structure: defn name/params shape
- [x] Documentation — `bars-self doc <file> [out.md]`
  - extracts `defn`/`defmacro` + leading `;;` comments → Markdown
- [ ] Debugger интеграция (GDB/LLDB)
- [ ] Profiler интеграция

### 14.3 Екосистема

- [x] Local package registry (filesystem; crates.io-style layout later)
  - `BARS_REGISTRY` or `$HOME/.bars/registry`
  - `<reg>/<name>/<version>/{Bars.toml,src/}` + `index.txt`
  - Deps: `foo = { version = "0.1.0" }` → install into `target/bars-deps`
- [x] Package CLI on `bars-self`
  - `new <name> [--bin]` — scaffold Bars.toml + src/lib.brs|main.brs
  - `publish [dir]` — copy package into local registry
  - `install <name> [version]` — materialize from registry
  - `search [query]` — list index
- [x] CI — `.github/workflows/ci.yml` (host + runtime + bars-self + self-test)
- [x] Editor support (syntax)
  - `editors/vscode/` — TextMate grammar + language-configuration
  - `editors/neovim/` — ftdetect + syntax
  - (tree-sitter grammar deferred)
- [ ] Hosted central registry (HTTP) — future

### 14.4 Езикови Фичъри (еволюция)

- [x] Trait system (v0) — macros in `compiler/macros.brs`
  - `(deftrait Show [show])` — erased declaration
  - `(impl Show for Type (defn show [x] …))` → `Show_show_Type`
  - `(trait-call Show show Type args…)` → call mangled method
  - Example: `examples/trait_demo.brs`
- [x] `defconst Name value` → zero-arg `(defn Name [] value)`
- [ ] Const generics (deferred — needs richer type system)
- [x] Async as package (not core) — `lib/async.brs` Future `[Pending|Ready]`
  - Example: `examples/async_demo.brs`
  - No HOF poll runtime yet (self-host safe)
- [ ] Compile-time VM / `const fn` (deferred)
- [x] WASM target (experimental WAT emitter)
  - `BARS_BACKEND_WASM=1` → `.wat` via `compiler/codegen/wasm.brs`
  - i64-oriented; control-flow incomplete (no full branch/jump yet)
  - Optional `wat2wasm` / `wasm-tools` for `.wasm`

---

## Сравнение с Nim и Rust (за ориентир)

| Аспект | Nim | Rust | Bars (цел) |
|--------|-----|------|------------|
| Bootstrap език | Pascal | OCaml | Rust |
| Компилатор днес | 95.8% Nim | 90.2% Rust | >90% Bars |
| Основен backend | C → gcc | LLVM | LLVM + C |
| Кодогенерация | Текстова C | LLVM API | LLVM IR текст |
| Compile-time VM | Да | Не (const fn) | Не (засега) |
| Пакетна система | Nimble | Cargo | Bars.toml (Cargo-like) |
| Комити | 23K | 328K | 0.1K (тепърва) |
| Години разработка | 18+ | 15+ | <1 |

---

## Принципи

1. **По-важно е кодът да работи, отколкото да добавяме нови фичъри.**
2. **Компилаторът се пише на Bars.** Rust bootstrap е само за начално компилиране.
3. **Минимален core, богата екосистема.**
4. **Всичко специфично (async, web, crypto) е за пакети.**
5. **LLVM е основен production backend.** QBE отпада.

---

*План версия: 6.1 | Актуализиран: 2026-07-26*
