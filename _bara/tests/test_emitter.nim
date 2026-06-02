import unittest, strutils
import ../src/types
import ../src/reader
import ../src/emitter

suite "Emitter - Basic Values":
  test "emit nil":
    let v = cljNil()
    let code = emitExpr(v)
    check code == "cljNil()"

  test "emit bool true":
    let v = cljBool(true)
    let code = emitExpr(v)
    check code == "cljBool(true)"

  test "emit bool false":
    let v = cljBool(false)
    let code = emitExpr(v)
    check code == "cljBool(false)"

  test "emit int":
    let v = cljInt(42)
    let code = emitExpr(v)
    check code == "cljInt(42)"

  test "emit float":
    let v = cljFloat(3.14)
    let code = emitExpr(v)
    check code == "cljFloat(3.14)"

  test "emit string":
    let v = cljString("hello")
    let code = emitExpr(v)
    check code == "cljString(\"hello\")"

  test "emit keyword":
    let v = cljKeyword("foo")
    let code = emitExpr(v)
    check code == "cljKeyword(\"foo\")"

  test "emit symbol":
    registerGlobal("x")
    let v = cljSymbol("x")
    let code = emitExpr(v)
    check code == "clj_x"

  test "emit mangled symbol":
    registerGlobal("my-var")
    let v = cljSymbol("my-var")
    let code = emitExpr(v)
    check code == "clj_my_var"

  test "emit vector":
    let v = cljVector(@[cljInt(1), cljInt(2)])
    let code = emitExpr(v)
    check "cljVector" in code

  test "emit empty list":
    let v = read("()")
    let code = emitExpr(v)
    check "cljList" in code

suite "Emitter - Special Forms":
  test "emit println":
    let v = read("(println 1)")
    let code = emitExpr(v)
    check "cljPrintln" in code

  test "emit def":
    let v = read("(def x 42)")
    let code = emitExpr(v)
    check "let clj_x" in code

  test "emit defn":
    let v = read("(defn square [x] (* x x))")
    let code = emitExpr(v)
    check "proc clj_square" in code

  test "emit if":
    let v = read("(if true 1 2)")
    let code = emitExpr(v)
    check "if" in code

  test "emit when":
    let v = read("(when true 1)")
    let code = emitExpr(v)
    check "if" in code

  test "emit let":
    let v = read("(let [a 1] a)")
    let code = emitExpr(v)
    check "let" in code

  test "emit cond":
    let v = read("(cond true 1 false 2)")
    let code = emitExpr(v)
    check "if" in code

  test "emit fn":
    let v = read("(fn [x] x)")
    let code = emitExpr(v)
    check "proc" in code

  test "emit do":
    let v = read("(do 1 2)")
    let code = emitExpr(v)
    check "cljInt(1)" in code
    check "cljInt(2)" in code

  test "emit loop":
    let v = read("(loop [i 0] i)")
    let code = emitExpr(v)
    check "while true" in code

  test "emit recur":
    let v = read("(loop [i 5] (if (= i 0) i (recur (- i 1))))")
    let code = emitExpr(v)
    check "while true" in code
    check "continue" in code

  test "emit loop with break":
    let v = read("(loop [acc 1 i 5] (if (= i 0) acc (recur (* acc i) (- i 1))))")
    let code = emitExpr(v)
    check "while true" in code
    check "continue" in code
    check "break" in code

suite "Emitter - Operators":
  test "emit addition":
    let v = read("(+ 1 2)")
    let code = emitExpr(v)
    check "cljAdd" in code

  test "emit subtraction":
    let v = read("(- 5 3)")
    let code = emitExpr(v)
    check "cljSub" in code

  test "emit multiplication":
    let v = read("(* 2 3)")
    let code = emitExpr(v)
    check "cljMul" in code

  test "emit equality":
    let v = read("(= 1 1)")
    let code = emitExpr(v)
    check "cljMultiEqual" in code

  test "emit not=":
    let v = read("(not= 1 2)")
    let code = emitExpr(v)
    check "cljNot" in code

  test "emit not":
    let v = read("(not true)")
    let code = emitExpr(v)
    check "cljNot" in code

suite "Emitter - Program":
  test "emitProgram with defs and main":
    let forms = readAll("(def x 42) (println x)")
    let code = emitProgram(forms)
    check "let clj_x" in code
    check "when isMainModule" in code

  test "emitProgram multiple defs":
    let forms = readAll("(def a 1) (def b 2)")
    let code = emitProgram(forms)
    check "let clj_a" in code
    check "let clj_b" in code

suite "Emitter - Map Literals":
  test "emit empty map":
    let v = cljMap(@[], @[])
    let code = emitExpr(v)
    check "cljMap" in code

  test "emit map with entries":
    let v = cljMapFromPairs(@[
      (cljKeyword("a"), cljInt(1)),
      (cljKeyword("b"), cljInt(2))
    ])
    let code = emitExpr(v)
    check "cljMap" in code

suite "Emitter - Higher-order":
  test "emit map with symbol fn":
    let v = read("(map inc [1 2 3])")
    let code = emitExpr(v)
    check "cljMap" in code
    check "cljFn" in code

  test "emit filter with inline fn":
    let v = read("(filter (fn [x] (> x 2)) [1 2 3])")
    let code = emitExpr(v)
    check "cljFilter" in code
    check "cljFn" in code

  test "emit reduce":
    let v = read("(reduce + 0 [1 2 3])")
    let code = emitExpr(v)
    check "cljReduce" in code

suite "Emitter - Try/Catch/Finally":
  test "emit try with catch":
    let v = read("(try (/ 1 0) (catch Exception e (println e)))")
    let code = emitExpr(v)
    check "try:" in code
    check "except" in code
    check "getCurrentExceptionMsg" in code

  test "emit try with specific exception type":
    let v = read("(try (/ 1 0) (catch ValueError e (println e)))")
    let code = emitExpr(v)
    check "except ValueError" in code

  test "emit try with finally":
    let v = read("(try (/ 1 0) (finally (println \"cleanup\")))")
    let code = emitExpr(v)
    check "try:" in code
    check "finally:" in code

  test "emit throw":
    let v = read("(throw \"something went wrong\")")
    let code = emitExpr(v)
    check "raise" in code
    check "CatchableError" in code
