# WASM-friendly wrappers around Bara Lang-generated code
# Uses Emscripten FFI: cint → JS number, cstring → JS string

import cljnim_runtime

include build/math

proc wasmSquare*(x: cint): cint {.exportc.} =
  let r = square(cljInt(x.int64))
  return r.intVal.cint

proc wasmFactorial*(n: cint): cint {.exportc.} =
  let r = factorial(cljInt(n.int64))
  return r.intVal.cint
