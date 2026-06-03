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
