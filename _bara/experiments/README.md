# Bara Lang Experiments

Unconventional compilation targets that JVM Clojure cannot do.

## Projects

| Experiment | Status | Description |
|---|---|---|
| `web-target/` | ✅ Working | Clojure → Nim → JavaScript for browsers |
| `native-lib/` | ✅ Working | Clojure → Nim → C shared library (.so) |
| `wasm-target/` | 🏗️ Skeleton | Clojure → Nim → WASM via Emscripten |

## web-target — Bara Lang in the Browser

```bash
cd web-target
./build.sh
node -e "require('./build/math.js'); console.log(jsSquare(7))"
# → 49
```

**Unique:** No JVM, no JavaScript source code — pure Bara Lang compiled to JS.

## native-lib — Bara Lang as a C Library

```bash
cd native-lib
./build.sh
cd test_client && make && LD_LIBRARY_PATH=../build ./test_client
# → c_square(7) = 49
# → c_factorial(5) = 120
```

**Unique:** Call Bara Lang functions from Python, Rust, Go, C via FFI.

## wasm-target — Bara Lang at Native Speed in Browser

```bash
cd wasm-target
# Install Emscripten first, then:
./build.sh
# Open www/index.html in browser
```

**Unique:** Bara Lang running as WebAssembly — faster than ClojureScript, smaller than JVM.

## Architecture

All experiments share the same pipeline:

```
Bara Lang Source (.clj)
       ↓
   cljnim compile-lib
       ↓
   Nim Source (.nim) with exported procs
       ↓
   Target-specific wrapper
       ↓
   nim c --target=...
       ↓
   JS / .so / .wasm
```

## Adding a New Experiment

1. Create a folder: `experiments/my-target/`
2. Write Clojure example in `examples/`
3. Write Nim wrapper in `my_wrappers.nim`
4. Write `build.sh` using `cljnim compile-lib`
5. Add row to the table above
