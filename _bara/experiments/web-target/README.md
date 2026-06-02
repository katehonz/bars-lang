# Bara Lang → JavaScript

Compile Bara Lang code to JavaScript via Nim's JS backend.

## Why?

- **No JVM** — Bara Lang in the browser without 50MB runtime
- **No JavaScript** — write Bara Lang, get JS
- **Smaller than ClojureScript** — no Google Closure compiler needed

## Quick Start

```bash
./build.sh
```

Then open `www/index.html` in a browser.

## How it works

1. `cljnim compile-lib` — generates Nim with exported functions
2. `js_wrappers.nim` — thin wrappers that convert CljVal ↔ JS types
3. `nim js` — compiles Nim to JavaScript
4. Browser loads `math.js` and calls `jsSquare(7)`, `jsFactorial(5)`, etc.

## Limitations

- Full `cljnim_runtime.nim` uses C FFI (threads, processes) — not JS-compatible
- For now, only numeric and string functions work
- Persistent data structures need JS-specific runtime

## Future

- Full JS runtime for HAMT vectors/maps
- DOM interop: `(dom/getElementById "app")`
- npm package output
