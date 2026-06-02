# Bara Lang → WASM (via Emscripten)

Compile Bara Lang code to WebAssembly using Nim's Emscripten backend.

## Why?

- **Native speed in browser** — no JS interpreter overhead
- **Smaller than JVM** — WASM module is ~100KB vs 50MB+ JVM
- **Secure sandbox** — WASM runs in browser's security model

## Requirements

```bash
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install latest
./emsdk activate latest
source ./emsdk_env.sh
```

## Quick Start

```bash
./build.sh
```

Then open `www/index.html` in a browser.

## How it works

1. `cljnim compile-lib` — generates Nim with exported functions
2. `nim c -d:emscripten` — compiles Nim to WASM + JS glue
3. Browser loads `math.js` (glue) + `math.wasm` (WASM module)
4. JS calls `_wasmSquare(7)` → WASM executes native Bara Lang code

## Future

- WASI target (server-side WASM)
- wasm32-wasi-musl via Zig (no Emscripten needed)
- DOM interop through Emscripten bindings
