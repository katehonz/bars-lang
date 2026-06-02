# C-friendly wrappers around Bara Lang-generated code
# Exports plain C types (int, char*) instead of CljVal

import cljnim_runtime

# Import the generated Bara Lang functions
include build/math

proc c_square*(x: cint): cint {.exportc, dynlib.} =
  let r = square(cljInt(x.int64))
  return r.intVal.cint

proc c_factorial*(n: cint): cint {.exportc, dynlib.} =
  let r = factorial(cljInt(n.int64))
  return r.intVal.cint

proc c_add*(a, b: cint): cint {.exportc, dynlib.} =
  let r = add(cljInt(a.int64), cljInt(b.int64))
  return r.intVal.cint

proc c_greet*(name: cstring): cstring {.exportc, dynlib.} =
  let r = greet(cljString($name))
  return r.strVal.cstring
