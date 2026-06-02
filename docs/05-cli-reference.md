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

Compile a `.brs` file to QBE IR and print to stdout.

```bash
bars build examples/hello.brs
bars build examples/hello.brs --output hello.ssa
```

### `run <FILE>`

Compile, link with the C runtime, and execute the binary.

```bash
bars run examples/math.brs
```

This is a full pipeline:
1. Read and parse
2. Expand macros
3. Run ownership checks
4. Generate QBE IR
5. Run `qbe` to produce assembler
6. Run `cc` to compile and link with `runtime/bars_runtime.o` and `-lgc`
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

Run the ownership checker without generating code.

```bash
bars check examples/ownership.brs
# ✅ Ownership checks passed.
```

## Options

Global options (if any) are parsed by `clap`. Use `--help` for full usage.

```bash
bars --help
```
