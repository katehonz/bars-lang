# Bara Lang → Native Shared Library

Compile Bara Lang code to a C shared library (`.so` / `.dll` / `.dylib`).

## Why?

- **Embed Bara Lang in Python/Rust/Go/C** via FFI
- **Tiny binaries** — no JVM overhead
- **True C ABI** — call Bara Lang functions from any language

## Quick Start

```bash
./build.sh
```

This generates:
- `build/libmath.so` — shared library
- `build/math.h` — C header
- `build/math.nim` — intermediate Nim source

## Test from C

```bash
cd test_client
make
./test_client
```

Expected output:
```
square(5) = 25
add(10, 20) = 30
cube(3) = 27
factorial(5) = 120
```

## How it works

1. `cljnim compile-lib` — generates Nim with exported `proc name*(...)`
2. `nim c --app:lib --header` — compiles Nim to `.so` + `.h`
3. C client links against the `.so` and calls functions

## Limitations

- Functions use `CljVal` (Nim ref object) — client must call Nim runtime helpers
- `NimMain()` must be called before using the library
