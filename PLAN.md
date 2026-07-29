# Bars — План за Разработка v6.0

> Актуален към: 2026-07-27
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

**Статус:** ~990 реда, hand-tuned (17.7–17.9); `tools/gen_types.py --check` гарантира paren balance. Компилира се с `BARS_SKIP_TYPECHECK=1` (bootstrap pattern — като Go/Rust/Nim).
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
- [x] Debugger интеграция (GDB/LLDB)
  - `BARS_DEBUG=1` → clang/cc `-g -O0`
  - LLVM: DWARF via `!dbg` + `DICompileUnit` / `DIFile` / `DISubprogram` / `DILocation`
  - Symbols map to source file (`DIFile`); `gdb ./bin` → `break _bars_main` / `break factorial`
- [x] Profiler интеграция
  - `BARS_PROFILE=1` → `-pg -g -O0` (gprof; `gprof bin gmon.out`)
  - `BARS_TIMINGS=1` → compile-stage ms (parse+modules, macros, types, ownership, hir, codegen+link, total)

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

- [x] Trait system — macros in `compiler/macros.brs`
  - `(deftrait T [m…] (default m [args] body…)*)` — required + defaults
  - `(impl T for Type …)` fills missing methods from defaults; `Self` → Type
  - `(trait-call …)` / `(tcall …)` → `T_m_Type`
  - Examples: `trait_demo.brs`, `trait_rich.brs` (defaults, override, Num/double)
- [x] `defconst Name value` → zero-arg `(defn Name [] value)`
- [ ] Const generics (deferred — needs richer type system)
- [x] Async as package (not core) — `lib/async.brs` Future `[Pending|Ready]`
  - Example: `examples/async_demo.brs`
  - No HOF poll runtime yet (self-host safe)
- [ ] Compile-time VM / `const fn` (deferred)
- [x] WASM target (WAT emitter with full CFG)
  - `BARS_BACKEND_WASM=1` → `.wat` / `.wasm` via `compiler/codegen/wasm.brs`
  - **PC dispatcher**: labels + `branch` / `jump` / `return` (loop `$dispatch` + `$__pc`)
  - i64-oriented; **WASI `fd_write`** → `$bars_println_i64` (decimal + newline)
  - Verified: `wasm_fact` → 120, `wasm_loop` → 45, `wasm_print` → `7\n120` under `wasmtime`

### 14.5 Cross-compilation ✅

- [x] `BARS_TARGET=<triple>` and `bars-self --target <triple> <in> <out>`
- [x] `compiler/target.brs` — triple helpers, runtime path, cross-cc discovery
- [x] LLVM IR `target triple = "…"` per target
- [x] Host: `x86_64-unknown-linux-gnu` (default) — single clang link
- [x] `aarch64-unknown-linux-gnu` — clang `--target` -c + `aarch64-linux-gnu-gcc` link
  - Runtime: `runtime/bars_runtime_aarch64_unknown_linux_gnu.o` (`make runtime-aarch64`)
- [x] `wasm32-unknown-unknown` → existing WASM backend
- [x] Clear error + rebuild hint when cross runtime `.o` is missing
- [x] self-test smoke for wasm target + aarch64 ELF (when toolchain present)

### 14.6 QoL — check, release, cross polish ✅

- [x] `bars-self check <file>` — parse → modules → macros → types → ownership (no codegen)
- [x] `BARS_RELEASE=1` → link with `-O2` (debug/profile still win)
- [x] Host triple from `uname -m` (x86_64 / aarch64 / arm64)
- [x] Auto-build missing `runtime/bars_runtime*.o` via host `cc` or cross-gcc / `clang --target`
- [x] self-test smoke for `check` + `BARS_RELEASE`

### 14.7 Networking (basic) ✅

- [x] C runtime TCP: `bars_tcp_{connect,listen,accept,send,recv,close}`
- [x] `lib/net.brs` — thin wrappers + `ok?`
- [x] Examples: `net_echo_server.brs`, `net_client.brs` (loopback echo on port 18765)
- [x] LLVM/C maps + type env; self-test smoke (server & client)

---

## Фаза 15: Екосистема (basic libs) 🔮

> Bars-first stdlib packages on top of runtime + Phase 14 foundations.

### 15.1 HTTP client ✅

- [x] `lib/http.brs` — HTTP/1.1 client over `lib/net` (sync, no TLS)
  - `request` / `get-req` / `post`
  - Response `[status body]`; parse status line + `Content-Length`
  - Named `get-req` (not `get`) to avoid shadowing vector `get` in the module
- [x] Examples: `http_server` / `http_client` (GET :18766 → `hello`)
  - `http_echo_server` / `http_post_client` (POST body echo :18767)
- [x] self-test smoke for GET + POST loopback

### 15.2 Next (candidates)

- [ ] TLS / HTTPS (deferred — needs crypto + OpenSSL or similar)
- [ ] Crypto hashes (SHA-256) in runtime + `lib/crypto`
- [ ] HTTP server helper package (routing beyond one-shot examples)

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

---

## Фаза 16: Бъгфиксове и Стабилизация 🪲

> Актуално към: 2026-07-28 | Открити чрез пълен код ревю; оставащите ☐ са затворени в 6.8

### 🔴 Критични

| # | Бъг | Файл | Статус |
|---|-----|------|--------|
| 1 | LLVM backend: `map-set` губи ключа — декларация с 2 параметъра вместо 3 | `bootstrap/src/backends/llvm/mod.rs` | ✅ |
| 2 | LLVM backend: `panic!()` вместо `Err` при unknown func/var | `bootstrap/src/backends/llvm/mod.rs` | ✅ |
| 3 | Type inference: hardcoded `vars: vec![0]` в `print_poly` схемата | `bootstrap/src/types/mod.rs` | ✅ |
| 4 | `recur` извън `loop` мълчаливо връща 0 вместо compile error | `compiler/hir.brs` | ✅ |
| 5 | `type_eq?` смята всички не-var/fun типове за равни (bool == i64 == str) | `compiler/types.brs` | ✅ |
| 6 | Thread макроси: nested `loop`/`recur` scope бъг | `compiler/macros.brs` | ✅ |

### 🟠 Средни

| # | Бъг | Файл | Статус |
|---|-----|------|--------|
| 7 | Unterminated string literal се приема без грешка | `bootstrap/src/reader/lexer.rs` | ✅ |
| 8 | REPL отрицателен depth води до безкрайно чакане | `bootstrap/src/main.rs` | ✅ |
| 9 | Lambda extraction не save/restore-ва `current_params` | `bootstrap/src/hir/lowering.rs` | ✅ |
| 10 | Ownership checker branch средите не са изолирани (env-copy не се вика) | `compiler/ownership.brs` | ✅ |
| 11 | Linter крашва при файл започващ с нов ред (OOB достъп) | `compiler/lint.brs` | ✅ |

### 🟡 Леки

| # | Бъг | Файл | Статус |
|---|-----|------|--------|
| 12 | Debug `eprintln!` в production код | `types/mod.rs`, `cranelift/mod.rs` | ✅ |
| 13 | `build.rs` ползва `panic!()` вместо `exit(1)` | `bootstrap/build.rs` | ✅ |
| 14 | Ownership checker третира непознати променливи като `Owned` | `bootstrap/src/ownership/checker.rs` | ✅ |
| 15 | `bars_env_set` се ползва като getter (объркващо име) | → `bars_env_is_set` | ✅ |
| 16 | `int-str` helper дублиран в ~10 файла | thin `str-from-i64` wrapper | ✅ |
| 17 | JSON parser не поддържа `\b`, `\f` escape-ове | `lib/json.brs` | ✅ |
| 18 | Hash map не се преразмерява (cap започва от 16, не расте) | `runtime/bars_runtime.c` | ✅ |
| 19 | `recv-until-close` няма лимит на размера | `lib/http.brs` | ✅ |
| 20 | `w-ident`/`c-ident` може да върне празен идентификатор | `codegen/wasm.brs`, `codegen/c.brs` | ✅ |
| 21 | `find-content-length` не обработва вариации в whitespace на HTTP хедъра | `lib/http.brs` | ✅ |
| 22 | `join-path`/`dirname` дублирани в `pkg.brs` и `build.brs` | `build.brs` → `pkg/*` | ✅ |
| 23 | Няма unit тестове за parser, type checker, ownership | bootstrap tests expanded | ✅ |
| 24 | `bars_print_any_i64` дереференцира i64 като raw pointer | `GC_base` guard | ✅ |
| 25 | C backend: няма forward declarations — lambda вика fn дефинирана по-късно → implicit decl error | `compiler/codegen/c.brs` (`func-proto` в `hir-to-c`) | ✅ |
| 26 | C backend: `min`/`max` ternary с липсваща затваряща скоба | `compiler/codegen/c.brs` | ✅ |

### 💡 Идеи за подобрения
1. Същински test framework (deftest макрос + test runner) → **17.1 ✅** (`lib/test.brs`; function API, not macros)
2. Error recovery в парсера → **17.5 ✅** (multi-error + skip-form sync)
3. Pattern matching в `let` (destructuring) → ✅ (commit destructuring)
4. Keyword arguments за функции
5. Persistent/immutable data structures → **17.14 ✅** (COW clone/conj/v-assoc/map-assoc; not full HAMT)
6. Автоматично TCO за рекурсивни функции → **17.6 ✅** (self-tail-call → recur в `lower-defn`)
7. Documentation strings за `defn`
8. Истински typeclass/protocol механизъм (не само macros)
9. По-добри compile-time грешки вместо `panic!()`/`unwrap()`
10. Incremental compilation с dependency graph (не само mtime) → **17.13 ✅** (`.deps` sidecar)

---

## Фаза 17: Езиково качество и DX 🔮

> Преглед (2026-07-28): езикът е self-host + stdlib-ready. Следващият лост е
> **надеждност на екосистемата** и **дупки между host и bars-self**.

### 17.0 Преглед — слабости (приоритет)

| # | Област | Проблем | Въздействие |
|---|--------|---------|-------------|
| A | Macros | ~~User `defmacro` + template expansion~~ → **17.2 ✅**; ~~пълен macro interpreter~~ → **17.12 ✅** (list/cons/if/let) | — |
| B | Globals | ~~Top-level `(def x …)` не е истински LLVM global~~ → **17.5 ✅** (real globals + `__bars_init_globals`) | shadowing на global с local остава забранено (документирано) |
| C | HOF | ~~map→bars_map_new~~ → **17.3a ✅**; ~~first-class fns~~ → **17.17–17.18 ✅** (closed + capturing) | — |
| D | Types | ~~Soft string/void warnings~~ → **17.7–17.9 ✅** (str-схеми, accept-any, generalize/instantiate, interleaved solve, env_lookup fix: 294→3) | практически чисто |
| E | Docs | Language guide без destructuring/traits пълнота; DOCTRINE споменава `{}` maps | onboarding drift |
| F | Net | HTTP client без TLS; няма server helper package | prod web ограничен |
| G | Tests | До 17.1 — само soft `assert` macro | ✅ поправено |

**Принцип за API-та:** предпочитай **context map + функции** пред `defmacro`, докато A не е готово.

### 17.1 Test framework ✅

- [x] `lib/test.brs` — `suite` / `section` / `is` / `is-eq` / `is-not` / `is-truthy` / `is-zero`
- [x] `report` / `finish` (exit 1 on fail) / `assert` / `assert!`
- [x] Examples: `test_demo.brs`, `test_fail_demo.brs`
- [x] self-test + stdlib docs

### 17.2 User `defmacro` in self-host ✅

- [x] Collect `(defmacro name [params] body)` into registry; strip from program
- [x] Expand calls: bind params to arg ASTs, expand `` ` `` templates (`~` / `~@`)
- [x] Modules: `collect-names` includes tag 21 so `alias/macro` renames match
- [x] `lib/test` — `(deftest name body)` → `(defn name [ctx] body)`
- [x] Examples: `defmacro_demo`, `defmacro_demo2`, `deftest_demo`
- [x] Full macro interpreter (list/cons/if/let at expand-time) → **17.12**

### 17.3a HOF + docs ✅

- [x] Self-host HIR: `(map f v)` / `(filter p v)` / `(reduce f init v)` → loop desugar
- [x] Lambda args via beta-reduction `(fn [x] …)` → `let` inside the loop
- [x] Unique loop vars (`__miN` …) for nesting safety
- [x] Docs: language guide (destructure + HOF), stdlib HOF section, DOCTRINE maps row
- [x] self-test: `hof_demo`, `hof_lambda`

### 17.3b Docstrings ✅

- [x] Convention: first `defn` body expr is a string → docstring
- [x] Self-host HIR skips it when more body follows
- [x] `bars-self doc` prefers inline docstring over `;;` comments above
- [x] Language guide note

### 17.3c Keyword args ✅

- [x] Built-in `(kwargs :k v …)` → `(vector "k" v …)` in self-host HIR
- [x] Keywords lower to stringlit `":name"` (host-compatible)
- [x] `lib/kw.brs` — `lookup` / `lookup-or` / `has?` / `count-pairs`
- [x] Example `kwargs_demo.brs`
- Explicit pack (not silent rewrite of all calls) so `map-set` + keyword keys stay valid

### 17.4 HTTP server package ✅

- [x] `lib/http_server.brs` — parse-request, response builders, accept-request, reply, serve-once
- [x] Re-export net listen/ok?/close (avoid duplicate require)
- [x] Example `http_server_route.brs` (path routing)
- [ ] TLS / HTTPS — deferred

### 17.5 Next (queued)

- [x] Real top-level `def` globals
  - HIR: `global <name>` decl lines + `__bars_init_globals` (init in source order)
  - LLVM: `@"__g_<name>"` storage; env seeded with `__g__:` markers; load/store intercept
  - C: `static int64_t <name>;` file scope; same marker seeding; wrapper calls init
  - Types: `def` gets polymorphic `'a -> 'a` scheme (no more str vs i64 noise)
  - Rules: no shadowing a global with a local; no global/fn name collisions
  - Example `globals_demo.brs` (LLVM + C suites); self-test 82/82
- [x] Parser error recovery — multi-error + stray closer detection
  - `parse-all` reports every top-level syntax error in one run (was: stop at first)
  - `skip-form` synchronization: skip the broken balanced form, resume after it
  - Stray `]` in list / `)` in vector now hard parse errors at the exact span
    (was: silent tag-99 atom → cryptic `%<unk>` LLVM link error)
- [x] C backend fixes — void `exit` + C reserved-word identifiers
  - `exit` → `bars_exit` emitted as statement (void), `dest = 0` (was: invalid cast of void expr)
  - `c-ident` renames C keywords (`default` → `default_`) — fixes `lib/kw` params
  - C suite now green: `test_demo`, `deftest_demo`, `kwargs_demo` (self-test 80/80)

### 17.6 Auto TCO + str-replace ✅

- [x] Автоматичен TCO за self-recursive `defn` (idea #6)
  - AST pre-pass в началото на `lower-defn` (`compiler/hir.brs`): self-call в tail
    позиция → `recur`; тялото се обвива в `(loop [p1 p1 …] body')`
  - Tail позиции: последен израз в тялото, двата клона на `if`, последен израз
    на `do`/`let`, тела на `match` клони; вложени `loop`/`fn` се пропускат
  - Грешна arity или не-tail self-call → остава нормално извикване
  - Върви след macros/types/ownership → cond/when получават TCO безплатно;
    ownership никога не вижда синтезирания loop
  - Известно ограничение: `(f b a)` swap на голи параметри — sequential recur
    assign (pre-existing за явен loop/recur); mutual recursion не се оптимизира
  - Example `tco_demo.brs` (1M дълбочина, non-tail factorial, match/let/do tails)
- [x] `str-replace` — runtime + stdlib
  - `bars_string_replace` в C runtime (replace all, non-overlapping)
  - LLVM declare + map, C backend map, types env (`slice3`), ownership copy-ops
  - Example `str_replace_demo.brs`; self-test 88/88

### 17.7 Type env precision (по-малко soft-warning шум) ✅

- [x] String builtins с реални str-схеми в `compiler/types.brs`
  - `str-concat`/`str-trim`/`str-replace`/`str-slice`/`str-substring` → `…->str`
  - `str-starts-with?`/`str-ends-with?` → `bool`; `str-index-of`/`str-get`/`str-count` → `i64`
  - `slurp`/`getenv`/`sha256` → `str->str`; `code-char`/`str-from-i64`/`args-get` → `i64->str`
  - Добавени липсващи: `str-count`/`str-trim`/`str-substring`/`str-split`/`str-join`/`char-code`
  - tcp_* остават i64-схеми (idiom `string-or-0` при recv — иначе false positives)
- [x] `println`/`print` accept-any — без constraint върху аргумента
  (`print-any-fn?` special case в `infer_call`; runtime печата всяка стойност)
- [x] Резултат: soft type warnings в examples suite **294 → 155** (−47%);
  test/json/string/crypto demo-та вече са чисти
- [x] Оставащо: shared mono vars → **17.8 ✅** (generalize_prefix + instantiate_ctx);
  остатъчен шум само от global solve в macro-heavy код

### 17.8 HM generalize + instantiate (let-polymorphism за defn) ✅

- [x] Бъгфиксове в dead-code пътеките на `compiler/types.brs`
  - `apply_subst` не рекурсираше в `T_Fun` (params/ret минаваха без subst)
  - `ty_free_vars` не рекурсираше в `T_Fun` → винаги празен → `generalize` quantify-ваше нищо
  - (и двете вече рекурсивни — първи self-recursive defns в compiler source;
    възможно благодарение на 17.6 auto TCO)
- [x] `generalize_prefix` — defn схемите quantify-ват vars извън env prefix
  (snapshot преди параметрите); params/locals не се quantify-ват
- [x] `instantiate_ctx` — свежи vars при всяко lookup/call (резервира ctx counter)
  - Свързан в `infer_expr` (atom lookup) и `infer_call`
- [x] Резултат: soft warnings **155 → 128** (от базова 294: −56%)
  - Известно: остатъчен шум от global solve → **17.9 ✅** (interleaved solve)

### 17.9 Interleaved solve + map API ✅

- [x] **Interleaved solve per top-level form** (`compiler/types.brs`)
  - След всяка форма: `solve_from` + `env_apply_subst_from` → defn схемите
    стават конкретни (greet: str->i64), cross-form pinning е невъзможен
- [x] Accept-any класове builtin-и (runtime-ът е нетипизиран i64):
  - `=`/`!=` (полиморфно сравнение), `count` (vector/str/map length)
  - coll-any със fresh var резултат: `get`/`first`/`last`/`push`/`pop`/`map-get`/`map-set`
  - `map-contains?` → bool
- [x] tcp типове: connect (str,i64)->i64, send (i64,str)->i64, recv (i64,i64)->str
- [x] **Бъгфикс: `env_lookup` first-match** → last-match (лексикално shadowing)
  - Same-named params в различни defns се замърсяваха (or/and bool → max i64);
    това беше коренът на почти целия оставащ шум
- [x] Резултат: soft warnings **128 → 3** (от базова 294: −99%)
  - Оставащият 1 локализиран: kw/lookup-or poly default (истинско HM ограничение)
- [x] Map API: `map-contains?` / `map-keys` / `map-values` (runtime + backend maps)
  - `lib/map` map-has? делегира към map-contains? (вече не греши при стойност 0)
  - Example `map_ops_demo.brs`; self-test 90/90

### 17.10 Sets + first/last в self-host ✅

- [x] Set операции в self-host backend-ите (runtime-ът ги имаше, но не бяха свързани)
  - LLVM declares + maps: `set`/`set-add`/`set-contains?`/`set-count` → `bars_set_*`
  - C backend maps + void-извикване на `set-add` (като `map-set`)
  - HIR: `(set a b c)` → new + set-add на всеки елемент (като `(vector …)`)
- [x] `first`/`last` — `bars_vector_first_i64`/`bars_vector_last_i64` в runtime,
  maps в двата backend-а (преди: link error при директна употреба)
- [x] types env (set-ops; first/last в coll-any), ownership copy-ops
- [x] `examples/set_demo.brs` разширен (литерална форма), `vector.brs` + first/last;
  set_demo в self-test suite

### 17.3 Ecosystem

- [x] HTTP server helper (`lib/http_server`) — 17.4
- [x] Crypto hashes (SHA-256) runtime + package
  - `bars_sha256` in C runtime (single-shot, hex digest; verified vs known vectors)
  - `lib/crypto.brs` — `sha256`; LLVM declare + types env; C backend passthrough
  - Example `crypto_demo.brs` ("" / "abc" / quick-brown-fox); self-test 84/84
- [ ] TLS / HTTPS (OpenSSL or similar) — later (deferred)

### 17.12 Full macro interpreter ✅

- [x] Expand-time eval for non-template `defmacro` bodies (`compiler/macros.brs`)
  - Builtins: `list` / `cons` / `first` / `rest` / `second` / `third` / `count` / `=` / `+` `-` `*` / `not`
  - Predicates: `symbol?` / `list?` / `vector?`
  - Special forms: `if` / `let` / `do` / `quote`; syntax-quote still via `expand-synquote`
  - Special-form heads promoted (symbol `if` → tag 12) so HIR sees real specials
  - Unquote `~` now runs full `macro-eval` (not only symbol lookup)
- [x] Example `defmacro_interp.brs` (`pick` / `my-or` / `thrice` / `when-pos` via list)
- [x] self-test **96/96** (LLVM + C + tooling; Gen2≡Gen3 identity)

### 17.13 Incremental dep-graph ✅

- [x] Sidecar `<output>.deps`: one `path\tmtime` edge per loaded source
- [x] `deps-up-to-date?` — exact set + per-file mtime match (beyond flat max-mtime)
- [x] Written after successful link; `BARS_FORCE` / `BARS_NO_INCREMENTAL` still force rebuild

### 17.14 Persistent / COW data structures ✅

- [x] Runtime: `bars_vector_{clone,conj,assoc,pop_copy}_i64`, `bars_map_{clone,assoc}_i64`
- [x] Builtins: `vector-clone` / `conj` / `v-assoc` / `v-pop` / `map-clone` / `map-assoc`
- [x] Wired in LLVM + C backends, types env, ownership copy-ops
- [x] `lib/persist.brs` thin aliases; example `persist_demo.brs`
- [ ] Full structural sharing (HAMT / RRB trees) — later if needed

### 17.15 gen_types.py sync ✅

- [x] `tools/gen_types.py` revalidated against hand-tuned `compiler/types.brs` (17.7–17.9)
  - types.brs is source of truth; tool checks paren balance and identity-emits
  - `python3 tools/gen_types.py --check` for CI-style validation

### 17.16 `and`/`or` + if truthiness + true/false literals ✅

- [x] Built-in macros `and` / `or` (short-circuit → nested `if` / `let`)
- [x] LLVM branch: `icmp ne i64 %c, 0` (was `trunc … to i1` — even ints like 2 were falsy)
- [x] Reader: `true`/`false`/`nil` → bool/nil tokens (not symbols) so ownership won't UAM
- [x] Ownership: treat true/false/nil names as Copy (legacy safety net)
- [x] Docs: language guide + fix `{}` drift in why-bars / architecture
- [x] Example `andor_demo.brs`

### 17.17 First-class closed functions ✅

- [x] Lambda lifting: closed `(fn [params] body)` → top-level `__lamN`
- [x] HIR `funcref dest name arity` → i64 function pointer (LLVM/C)
- [x] Locals (params / let / loop) win over funcref (no shadowing bugs)
- [x] Free-var analysis excludes builtins + top-level fns
- [x] Example `fcfn_demo.brs`

### 17.18 Capturing closures ✅

- [x] Open lambdas: free locals → env vector; fn is `[__env, params…]`
- [x] Body rewrite: free `y` → `(get __env i)`
- [x] Closure value = vector `[fnptr, env]`; closed use empty env
- [x] Runtime `bars_icall0`…`bars_icall4` unpack bare ptr vs closure
- [x] Examples `closure_demo.brs`, capturing case in `fcfn_demo.brs`

### 17.19 Nested closures + HIR undefined-name diagnostics ✅

- [x] Bottom-up lambda lift (inner `fn` first) so nested capture works
- [x] Compile-time `error: hir: undefined name/function \`…\``
- [x] Soft by default; `BARS_STRICT_HIR=1` returns empty HIR (skip backend)
- [x] Expanded builtin/runtime name allowlist (str-*/map-*/bars_*/args-*)
- [x] Example `nested_closure.brs` → 13

### 17.20 Higher-arity icall + locals tracking ✅

- [x] Runtime `bars_icall5`…`bars_icall8` (closure unpack same as 0–4)
- [x] LLVM/C backends declare + name-map icall5–8
- [x] HIR: cap local icall at 8 args; hard error if local call > 8
- [x] `lower-let-pattern` tracks destructured names as locals (icall/funcref/undef)
- [x] Match arm binds (`hir-locals-add` on pattern fields / binding pats)
- [x] Soft undef still emits the name (no more silent `const 0` rewrite)
- [x] Example `icall_arity.brs` → 21, 150

### 17.21 `if-let` / `when-let` + document control macros ✅

- [x] Built-in `if-let` / `when-let` (single binding, truthy init)
- [x] Document existing `when` / `unless` / `->` / `->>` / `cond` in language guide
- [x] Example `iflet_demo.brs` → 1 2 7 3 4 9 12

### 17.22 `apply` (first-class call with arg vector) ✅

- [x] Runtime `bars_apply(f, args_vec)` → `bars_icall0`…`8` by vector length
- [x] LLVM/C: map `apply` / `bars_apply`; declare `@bars_apply`
- [x] HIR builtin allowlist includes `apply`
- [x] Example `apply_demo.brs` → 42, 42, 103, 21

### 17.23 Multi-arg `apply` + `partial` ✅

- [x] `(apply f a b xs)` — fixed args + rest vector via `bars_apply_join`
- [x] HIR desugar multi-arg `apply` → `(bars_apply_join f (vector a…) xs)`
- [x] Built-in macro `(partial f a…)` → `(fn [x] (apply f a… [x]))`
- [x] Example `partial_demo.brs` → 42, 6, 42, 17, 24

### 17.24 `doseq` / `for` vector iteration macros ✅

- [x] `(doseq [x coll] body…)` → index `loop`/`recur` (side effects, nil)
- [x] `(for [x coll] body…)` → collect last body expr into a vector
- [x] Single binding only; gensyms derived from binding name
- [x] Example `for_demo.brs` → 1 2 3, 10 40 4, 6 7

### 17.25 `dotimes` ✅

- [x] `(dotimes [i n] body…)` → `let` bound n + index `loop`/`recur`
- [x] Example `dotimes_demo.brs` → 0 1 2 3, 0 4 3

### 17.26 Multi-binding `doseq`/`for` + `when-not` ✅

- [x] Nested pairs `[x xs y ys …]` for doseq (cartesian) and for (flattened)
- [x] `when-not` alias of `unless`
- [x] Example `for_multi_demo.brs` → 11 21 12 22, 4 3 8, 99

### 17.27 `while` ✅

- [x] `(while cond body…)` → `loop`/`recur` with dummy binding
- [x] Example `while_demo.brs` → 3 2 1 0, 30 20 10

### 17.28 `case` equality dispatch ✅

- [x] `(case e c1 r1 c2 r2 default?)` → nested `if`/`=` with single scrutinee bind
- [x] Example `case_demo.brs` → 10 20 30 0 200

### 17.29 `case` multi-const groups ✅

- [x] `(case e (1 2 3) r …)` / `[1 2 3]` → `(or (= e 1) (= e 2) …)`
- [x] Example `case_group_demo.brs` → 1 1 2 3 0 42

### 17.30 `if-not` / `complement` + control-macro index ✅

- [x] `(if-not c then else?)` → `(if (not c) then else)`
- [x] `(complement f)` → `(fn [x] (not (f x)))`
- [x] Language guide table of built-in macros
- [x] Example `ifnot_demo.brs` → 1 2 0 1

### 17.31 `identity` + `constantly` ✅

- [x] Runtime `bars_identity` + LLVM/C mapping
- [x] `(constantly v)` → `(let [__cv v] (fn [__cu] __cv))`
- [x] Example `identity_demo.brs` → 42 0 7 7 11

### 17.32 `juxt` ✅

- [x] `(juxt f g …)` → `(fn [x] (vector (f x) (g x) …))`
- [x] Example `juxt_demo.brs` → 10 25 6 3, 42

### 17.33 `comp` function composition ✅

- [x] `(comp f g h)` → `(fn [x] (f (g (h x))))` (rightmost first)
- [x] `(comp f)` → `f`; `(comp)` → identity fn
- [x] Example `comp_demo.brs` → 72 42 9

### 17.34 `fnil` nil-default wrapper ✅

- [x] `(fnil f d…)` → fn that substitutes defaults for 0/nil args (1–3)
- [x] Example `fnil_demo.brs` → 7 42, 30 3 9, 6

### 17.35 `some` / `every?` ✅

- [x] HIR desugar like map/filter (apply-callable, loop/recur)
- [x] `(some pred coll)` → first truthy `(pred x)`, else 0
- [x] `(every? pred coll)` → 1 if all truthy, else 0
- [x] Example `some_every_demo.brs` → 1 0, 1 0 1, 12

### 17.36 `not-any?` / `not-every?` ✅

- [x] Macros → `(if (some …) 0 1)` / `(if (every? …) 0 1)`
- [x] Example `not_any_demo.brs` → 1 0, 0 1 1

### 17.37 `take` / `drop` ✅

- [x] HIR desugar to loop building a new vector
- [x] `(take n coll)` / `(drop n coll)` with `min` clamping
- [x] Example `take_drop_demo.brs` → 3 1 3, 3 3, 5 0

### 17.38 `take-while` / `drop-while` + `min`/`max` ✅

- [x] HIR desugar `take-while` / `drop-while` (pred + vector)
- [x] LLVM/C: inline `min`/`max` via select / ternary
- [x] Example `take_while_demo.brs` → 2 1 2, 3 0, 3, 3 7

### 17.39 `range` ✅

- [x] `(range end)` / `(range start end)` / `(range start end step)`
- [x] Positive and negative step; step 0 → empty vector
- [x] Example `range_demo.brs` → 4 0 3, 4 2 5, 4 6, 3 5 1, 20

---

*План версия: 6.47 | Актуализиран: 2026-07-29*
