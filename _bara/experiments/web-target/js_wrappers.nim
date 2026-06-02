# JS-friendly wrappers around Bara Lang-generated code
# These expose plain JS types (number, string) instead of CljVal

import cljnim_runtime_js

# Import the generated Bara Lang functions
include build/math

proc jsSquare*(x: int): int {.exportc.} =
  let r = square(cljInt(x.int64))
  return r.intVal.int

proc jsFactorial*(n: int): int {.exportc.} =
  let r = factorial(cljInt(n.int64))
  return r.intVal.int

proc jsGreet*(name: cstring): cstring {.exportc.} =
  let r = greet(cljString($name))
  return r.strVal.cstring
