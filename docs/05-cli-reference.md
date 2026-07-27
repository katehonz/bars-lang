# CLI Reference

```
bars <COMMAND> [OPTIONS]
```

## Commands

### `read <FILE>`

Parse a `.brs` file and print the AST.

```bash
bars read examples/hello.brs
```

### `build <FILE>`

Compile a `.brs` file and print to stdout (or write to output file).

```bash
bars build examples/hello.brs
bars build examples/hello.brs --output hello.ssa

# Cranelift AOT backend (emits object file)
bars build --backend cranelift examples/hello.brs --output hello.o

# LLVM backend (requires --features llvm-backend)
bars build --backend llvm examples/hello.brs
```

### `run <FILE>`

Compile, link with the C runtime, and execute the binary.

```bash
bars run examples/math.brs
bars run --backend cranelift examples/math.brs
bars run --backend llvm examples/math.brs
```

This is a full pipeline:
1. Read and parse
2. Expand macros
3. Run ownership checks
4. Lower to HIR
5. Generate code via selected backend
6. Link with `runtime/bars_runtime.o` and `-lgc`
7. Execute the binary
8. Clean up temporary files

### `repl`

Start an interactive REPL using Cranelift JIT compilation.

```bash
bars repl
```

Functions defined with `defn` persist across REPL commands. The REPL compiles each expression to an anonymous function and executes it in memory.

```
bars> (defn square [x] (* x x))
bars> (square 5)
25
bars> (loop [i 0 acc 0] (if (= i 5) acc (recur (+ i 1) (+ acc i))))
10
```

### `check <FILE>`

Run the ownership checker (and optionally type inference) without generating code.

```bash
bars check examples/ownership.brs
# ✅ Ownership checks passed.

bars check --types examples/ownership.brs
# ✅ Type inference passed.
#   main : i64
```

### `lsp`

Start the Bars Language Server Protocol (LSP) server over stdio.

```bash
bars lsp
```

Supported LSP features:
- **Text document sync** — full document synchronization
- **Diagnostics** — parse errors and type errors published automatically
- **Hover** — show inferred type of symbols
- **Completion** — top-level definitions + built-in keywords
- **Go to Definition** — jump to definition of top-level names

Configure your editor to launch `bars lsp` as the language server for `.brs` files.

## Self-hosted compiler (`bars-self`)

Built with `make bars-self`. Day-to-day self-host entry point (Bars-first pipeline).

```bash
./bars-self <input.brs> <output_bin>
./bars-self --target <triple> <input.brs> <output_bin>
./bars-self check <input.brs>
./bars-self watch <input.brs> <output_bin>
./bars-self fmt  <input.brs> [--write]
./bars-self lint <input.brs>
./bars-self doc  <input.brs> [output.md]
```

| Feature | Behavior |
|---------|----------|
| **Incremental** | Skips codegen/link when the binary is newer than all loaded sources (main, requires, `Bars.toml`) |
| **Watch** | Polls every 500ms; recompiles when any loaded source changes (Ctrl+C to stop) |
| **Check** | Parse → modules → macros → types → ownership only (exit 0/1/3/4; no codegen) |
| **Force** | `BARS_FORCE=1` or `BARS_NO_INCREMENTAL=1` always rebuilds |
| **Target** | `--target <triple>` or `BARS_TARGET=<triple>` — cross-compile (see below) |
| **Release** | `BARS_RELEASE=1` → `-O2` at link (unless debug/profile) |
| **Debug** | `BARS_DEBUG=1` → DWARF (`-g -O0`), LLVM `!dbg` / DISubprogram; `gdb ./bin` then `break _bars_main` |
| **Profile** | `BARS_PROFILE=1` → `-pg -g` for gprof; or use `perf record ./bin` |
| **Timings** | `BARS_TIMINGS=1` → per-stage milliseconds (parse, macros, types, ownership, HIR, codegen+link) |
| **fmt** | Pretty-print AST to stdout, or rewrite with `--write` |
| **lint** | Style + defn shape checks; exit `5` if issues found |
| **doc** | Markdown from `defn`/`defmacro` + leading `;;` comments |
| **new** | Scaffold a package (`--bin` for `src/main.brs`) |
| **publish** | Publish package dir into the local registry |
| **install** | Install a registry package into `target/bars-deps` |
| **search** | List / filter the local registry index |

### Local registry

```bash
export BARS_REGISTRY=~/.bars/registry   # default if unset
./bars-self new mylib
./bars-self publish mylib
./bars-self search my
./bars-self install mylib 0.1.0
```

In `Bars.toml`:

```toml
[dependencies]
mylib = { version = "0.1.0" }   # from local registry
# still supported:
# other = { path = "../other" }
# remote = { git = "https://…", branch = "main" }
```

Other env flags: `BARS_SKIP_TYPECHECK`, `BARS_SKIP_OWNERSHIP`, `BARS_STRICT_TYPES`,
`BARS_BACKEND_C=1` (C backend), `BARS_BACKEND_WASM=1` (WAT/WASM with PC control-flow),
`BARS_TARGET`, `BARS_DEBUG=1`, `BARS_PROFILE=1`, `BARS_TIMINGS=1`, `BARS_RELEASE=1`.

### Check (no codegen)

```bash
./bars-self check examples/math.brs
# note: check ok: `examples/math.brs`
# exit 0 ok | 1 parse | 3 types (strict) | 4 ownership
```

### Cross-compilation

| Triple | Requirements | Output |
|--------|--------------|--------|
| host (`uname -m`) | `runtime/bars_runtime.o` | native ELF |
| `aarch64-unknown-linux-gnu` | `aarch64-linux-gnu-gcc` (auto-builds runtime `.o` if missing) | ARM64 ELF |
| `wasm32-unknown-unknown` | optional `wasm-tools` / `wat2wasm` | `.wat` / `.wasm` |

```bash
# aarch64 (cross) — runtime .o auto-built when missing
./bars-self --target aarch64-unknown-linux-gnu examples/math.brs /tmp/math_arm
# or: BARS_TARGET=aarch64-unknown-linux-gnu ./bars-self examples/math.brs /tmp/math_arm
file /tmp/math_arm
# → ELF 64-bit LSB pie executable, ARM aarch64

# optimized host binary
BARS_RELEASE=1 ./bars-self examples/math.brs /tmp/m

# wasm via target (same as BARS_BACKEND_WASM=1)
BARS_TARGET=wasm32-unknown-unknown ./bars-self examples/wasm_fact.brs /tmp/f
wasmtime --invoke main /tmp/f.wasm

# Debugger (GDB/LLDB)
BARS_DEBUG=1 ./bars-self examples/math.brs /tmp/m
gdb /tmp/m
# (gdb) break _bars_main
# (gdb) break factorial
# (gdb) run

# Compile-stage timings
BARS_TIMINGS=1 BARS_FORCE=1 ./bars-self examples/math.brs /tmp/m

# gprof
BARS_PROFILE=1 ./bars-self examples/math.brs /tmp/m
/tmp/m
gprof /tmp/m gmon.out

BARS_BACKEND_WASM=1 ./bars-self examples/wasm_fact.brs /tmp/f
# → /tmp/f.wat (+ /tmp/f.wasm if wasm-tools/wat2wasm available)
wasmtime --invoke main /tmp/f.wasm        # → 120

BARS_BACKEND_WASM=1 ./bars-self examples/wasm_print.brs /tmp/p
wasmtime --invoke main /tmp/p.wasm        # → 7\n120  (WASI fd_write)
```

WASM `println` prints i64 decimals via WASI preview1 `fd_write` (no Boehm GC / full runtime).

## Options

Global options (if any) are parsed by `clap`. Use `--help` for full usage.

```bash
bars --help
```

### Backend Selection

| Backend | Command | Notes |
|---------|---------|-------|
| **QBE** (default) | `bars run file.brs` | Fast AOT compilation |
| **Cranelift** | `bars run --backend cranelift file.brs` | Fast AOT or JIT (REPL) |
| **LLVM** | `bars run --backend llvm file.brs` | Requires `--features llvm-backend` |

### Release Builds

```bash
bars build --release examples/hello.brs
bars run --release --backend llvm examples/hello.brs
```
