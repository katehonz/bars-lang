# Фаза 12: Cross-Compilation

## Цел
Компилиране на Bars програми за различни архитектури чрез `--target <triple>`.

## Поддържани target-и (първа итерация)
| Triple | QBE | Cranelift | LLVM | Забележка |
|--------|-----|-----------|------|-----------|
| `x86_64-unknown-linux-gnu` | amd64_sysv | x86_64 | x86_64 | host, работи веднага |
| `aarch64-unknown-linux-gnu` | arm64 | aarch64 | aarch64 | изисква cross gcc |
| `wasm32-unknown-unknown` | — | — | wasm32 | изисква wasm-ld |

## Архитектура

### 1. CLI
- Нов флаг `--target <triple>` за `build` и `run`
- Ако липсва → host target (native)

### 2. Target Triple абстракция
- `src/target.rs` — `TargetTriple` struct с parsing и validation
- Mapping към backend-specific target names

### 3. Backend промени
- **QBE**: `-t <target>` флаг при извикване на `qbe`
- **Cranelift**: `isa::lookup(triple)` вместо `cranelift_native::builder()`
- **LLVM**: `module.set_triple()`, `Target::from_triple()` вместо `initialize_native()`

### 4. C Runtime
- Cross-компилиране на `runtime/bars_runtime.c` за target
- Търсене на `runtime/bars_runtime_<target>.o` или fallback към `bars_runtime.o` ако target == host
- Ако cross runtime липсва → error с инструкции за компилация

### 5. Linker
- Използване на cross linker (`<triple>-gcc` или `<triple>-ld`)
- При `--target wasm32-unknown-unknown` → `wasm-ld` + различен pipeline (няма C runtime)

## Критерий за приемане
```bash
bars build examples/hello.brs --target aarch64-unknown-linux-gnu -o hello_arm64
file hello_arm64
# → ELF 64-bit LSB executable, ARM aarch64
```
