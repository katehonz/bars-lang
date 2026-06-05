# Bars — План за Разработка v6.0

> Актуален към: 2026-06-05
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
├── types.brs        # Type inference (TODO)
├── ownership.brs    # Ownership checker (TODO)
├── macros.brs       # Macro expansion (TODO)
├── modules.brs      # Модулна система (TODO)
├── codegen/
│   ├── qbe.brs      # QBE backend ✅ (ще остане като reference)
│   ├── llvm.brs     # LLVM IR backend (TODO — ПРИОРИТЕТ)
│   └── c.brs        # C transpiler (TODO — алтернатива като Nim)
└── selfhost.brs     # Main entry point ✅
```

### Stage 0-4: Вече готово ✅

- [x] Stage 0: String tooling, CLI args, `exit` — preparatory work
- [x] Stage 1: Self-hosted Reader — lexer + parser с tagged S-expression AST (`lib/reader.brs`, 360 реда)
- [x] Stage 2: Self-hosted HIR Lowering — AST → HIR с tail call recognition (`lib/hir.brs`, 182 реда)
- [x] Stage 3: Self-hosted QBE Codegen — HIR → QBE SSA IR (`lib/qbe.brs`, 273 реда)
- [x] Stage 4: Self-hosted Build Pipeline — orchestration (`lib/build.brs`, 60 реда)
- [x] Bootstrap proof: `bars build --backend cranelift selfhost.brs` произвежда binary

### Stage 5: Self-Hosted Type Inference 🔴 ПРИОРИТЕТ

- [ ] **12.5** Пренасяне на Hindley-Milner type inference от Rust в Bars (`lib/types.brs`)
- [ ] **12.6** Unification, generalization, instantiation в Bars
- [ ] **12.7** Type environment + builtin functions в Bars
- [ ] **12.8** Интегриране в компилационния pipeline (преди HIR lowering)

**Защо първо:** Без type checker self-hosted компилаторът не може да валидира входния код. Това е критично за надеждност.

### Stage 6: Self-Hosted Ownership Checker

- [ ] **12.9** Пренасяне на ownership checker от Rust в Bars (`lib/ownership.brs`)
- [ ] **12.10** NLL borrow checking с states (Owned, Borrowed, MutBorrowed, Moved)
- [ ] **12.11** Error reporting: UseAfterMove, AlreadyBorrowed, MoveWhileBorrowed

**Защо:** Ownership е ключовият differentiating feature на Bars спрямо други Lisps. Без него в self-hosted версията, компилаторът не е feature-complete.

### Stage 7: Self-Hosted LLVM Backend 🔴 ПРИОРИТЕТ

- [ ] **12.12** HIR → LLVM IR кодогенерация (`lib/codegen/llvm.brs`)
- [ ] **12.13** Генериране на LLVM IR текст (human-readable `.ll` формат)
- [ ] **12.14** Интеграция: `.brs` → HIR → LLVM IR → `llc` → `.o` → `cc` → binary
- [ ] **12.15** Поддръжка на всички HIR инструкции в LLVM

**Защо LLVM вместо QBE:**
- LLVM е industry standard (Rust, Swift, Clang го ползват)
- Оптимизации на ниво production (O2/O3)
- Поддръжка на много архитектури
- QBE е добър за прототипиране, но не е за production compiler

### Stage 8: Self-Hosted Macro System

- [ ] **12.16** Macro expander в Bars (`lib/macros.brs`)
- [ ] **12.17** Built-in макроси: `when`, `unless`, `cond`, `->`, `->>`
- [ ] **12.18** `defmacro` + syntax-quote/unquote в self-hosted версията

### Stage 9: Self-Hosted Module System

- [ ] **12.19** `require` резолване и namespace mangling (`lib/modules.brs`)
- [ ] **12.20** Мулти-файлова компилация
- [ ] **12.21** Интеграция с пакетната система (Bars.toml dependencies)

### Stage 10: Пълен Bootstrap

- [ ] **12.22** Bars компилаторът (написан на Bars) компилира произволен `.brs` файл до работещ binary
- [ ] **12.23** Компилира себе си успешно (self-compilation test)
- [ ] **12.24** Identity test: Rust и Bars компилатори произвеждат идентичен изход за тестов набор
- [ ] **12.25** Rust компилаторът става само bootstrap tool (като Nim `csources`)

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

- [ ] **13.1** Преместване на компилатора от `lib/` в `compiler/`
- [ ] **13.2** Подобряване на error messages (compiler написан на Bars → може да използва собствените си абстракции)
- [ ] **13.3** Incremental compilation
- [ ] **13.4** Watch mode (`bars watch`)
- [ ] **13.5** C code generation backend (като Nim) — за максимална портабилност

---

## Фаза 14: Езиково Съзряване 🔮

> **Всичко оттук надолу се пише на Bars. Rust bootstrap-ът не се пипа.**

### 14.1 Стандартна Библиотека (разширение)

- [ ] File I/O (async-ready интерфейс, но sync имплементация)
- [ ] JSON парсване/генериране
- [ ] Regex
- [ ] Random числа
- [ ] Time/Date
- [ ] Command-line argument parsing (clap-like)

### 14.2 Tooling

- [ ] Formatter (`bars fmt`) — форматира Bars код
- [ ] Linter (`bars lint`)
- [ ] Documentation generator (`bars doc`) — от docstrings в кода
- [ ] Debugger интеграция (GDB/LLDB)
- [ ] Profiler интеграция

### 14.3 Екосистема

- [ ] Central package registry (като crates.io)
- [ ] `bars publish` команда
- [ ] CI/CD integration
- [ ] Editor support (VSCode, Neovim — tree-sitter граматика)

### 14.4 Езикови Фичъри (еволюция)

- [ ] Trait/Interface система (като Rust traits или Haskell typeclasses)
- [ ] Const generics
- [ ] Async/await (ако екосистемата го изисква — НЕ в core, а като пакет)
- [ ] Compile-time execution (като Nim VM или Rust const fn)
- [ ] WASM target

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

*План версия: 6.0 | Актуализиран: 2026-06-05*
