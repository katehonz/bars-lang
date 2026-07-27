# Cross-Compilation (self-hosted)

> Bars-first: implemented in `compiler/target.brs` + `compiler/build.brs`.  
> Host (Rust) also has partial `--target` via `bootstrap/src/target.rs`.

## Цел

Компилиране на Bars програми за различни архитектури чрез:

```bash
./bars-self --target <triple> <in.brs> <out>
# or
BARS_TARGET=<triple> ./bars-self <in.brs> <out>
```

## Поддържани target-и

| Triple | Backend | Runtime / linker | Забележка |
|--------|---------|------------------|-----------|
| `x86_64-unknown-linux-gnu` | LLVM (default) | `runtime/bars_runtime.o` + `clang` | host |
| `aarch64-unknown-linux-gnu` | LLVM | `runtime/bars_runtime_aarch64_unknown_linux_gnu.o` + `aarch64-linux-gnu-gcc` | cross |
| `wasm32-unknown-unknown` | WASM/WAT | no C runtime | same as `BARS_BACKEND_WASM=1` |

C backend (`BARS_BACKEND_C=1`) uses the same runtime `.o` and cross-cc for aarch64.

## Архитектура (self-host)

1. **Target resolve** — CLI `--target` or `BARS_TARGET`, else host default  
2. **LLVM IR** — `target triple = "<triple>"` in `compiler/codegen/llvm.brs`  
3. **Runtime** — `runtime/bars_runtime.o` (host) or `runtime/bars_runtime_<triple_underscored>.o`  
4. **Link**  
   - host: `clang … file.ll runtime.o -lgc -lm -o out`  
   - aarch64: `clang --target=aarch64-linux-gnu -c file.ll -o file.o` then  
     `aarch64-linux-gnu-gcc file.o runtime_aarch64.o -lgc -lm -o out`  
   - wasm: WAT emitter + optional wat2wasm / wasm-tools  

## Build cross runtime

```bash
make runtime-aarch64
# equivalent:
# aarch64-linux-gnu-gcc -O2 -c runtime/bars_runtime.c \
#   -o runtime/bars_runtime_aarch64_unknown_linux_gnu.o
```

## Acceptance

```bash
make runtime-aarch64
./bars-self --target aarch64-unknown-linux-gnu examples/math.brs /tmp/math_arm
file /tmp/math_arm
# → ELF 64-bit LSB pie executable, ARM aarch64
```

## Host detection

Default triple comes from `uname -m` (`x86_64` / `amd64` / `aarch64` / `arm64` → `*-unknown-linux-gnu`).

## Auto-build runtime

If the runtime `.o` for a target is missing and `runtime/bars_runtime.c` exists, the compiler runs:

- host: `cc -O2 -c runtime/bars_runtime.c -o runtime/bars_runtime.o`
- cross: `<cross-gcc> -O2 -c … -o runtime/bars_runtime_<triple>.o`  
  (or `clang --target=…` if no `*-gcc` is found)

## Future

- More triples (riscv64, musl) when runtime + cross-cc available  
