import unittest, strutils
import ../src/types
import ../src/eval

suite "Eval - Basic Values":
  setup:
    let env = newTopLevelEnv()

  test "eval integer":
    let r = eval("42", env)
    check r.ok
    check r.value.kind == ckInt
    check r.value.intVal == 42

  test "eval string":
    let r = eval("\"hello\"", env)
    check r.ok
    check r.value.kind == ckString
    check r.value.strVal == "hello"

  test "eval bool true":
    let r = eval("true", env)
    check r.ok
    check r.value.kind == ckBool
    check r.value.boolVal == true

  test "eval nil":
    let r = eval("nil", env)
    check r.ok
    check r.value.kind == ckNil

  test "eval keyword":
    let r = eval(":foo", env)
    check r.ok
    check r.value.kind == ckKeyword
    check r.value.kwName == "foo"

suite "Eval - Arithmetic":
  setup:
    let env = newTopLevelEnv()

  test "addition":
    let r = eval("(+ 1 2)", env)
    check r.ok
    check r.value.intVal == 3

  test "subtraction":
    let r = eval("(- 10 3)", env)
    check r.ok
    check r.value.intVal == 7

  test "multiplication":
    let r = eval("(* 3 4)", env)
    check r.ok
    check r.value.intVal == 12

  test "division":
    let r = eval("(/ 10 2)", env)
    check r.ok
    check r.value.intVal == 5

  test "nested arithmetic":
    let r = eval("(+ 1 (* 2 3))", env)
    check r.ok
    check r.value.intVal == 7

  test "multi-arg addition":
    let r = eval("(+ 1 2 3 4)", env)
    check r.ok
    check r.value.intVal == 10

  test "float arithmetic":
    let r = eval("(+ 1.5 2.5)", env)
    check r.ok
    check r.value.kind == ckFloat
    check r.value.floatVal == 4.0

  test "negation":
    let r = eval("(- 5)", env)
    check r.ok
    check r.value.intVal == -5

suite "Eval - Comparison":
  setup:
    let env = newTopLevelEnv()

  test "greater than":
    let r = eval("(> 5 3)", env)
    check r.ok
    check r.value.boolVal == true

  test "less than":
    let r = eval("(< 3 5)", env)
    check r.ok
    check r.value.boolVal == true

  test "greater or equal":
    let r = eval("(>= 5 5)", env)
    check r.ok
    check r.value.boolVal == true

  test "less or equal":
    let r = eval("(<= 3 5)", env)
    check r.ok
    check r.value.boolVal == true

  test "equality":
    let r = eval("(= 42 42)", env)
    check r.ok
    check r.value.boolVal == true

  test "not equal":
    let r = eval("(not= 1 2)", env)
    check r.ok
    check r.value.boolVal == true

suite "Eval - Math Predicates":
  setup:
    let env = newTopLevelEnv()

  test "pos?":
    check eval("(pos? 5)", env).value.boolVal == true
    check eval("(pos? -1)", env).value.boolVal == false

  test "neg?":
    check eval("(neg? -3)", env).value.boolVal == true
    check eval("(neg? 3)", env).value.boolVal == false

  test "even?":
    check eval("(even? 4)", env).value.boolVal == true
    check eval("(even? 3)", env).value.boolVal == false

  test "odd?":
    check eval("(odd? 3)", env).value.boolVal == true
    check eval("(odd? 4)", env).value.boolVal == false

  test "abs":
    check eval("(abs -5)", env).value.intVal == 5
    check eval("(abs 5)", env).value.intVal == 5

  test "mod":
    check eval("(mod 10 3)", env).value.intVal == 1

  test "quot":
    check eval("(quot 10 3)", env).value.intVal == 3

  test "rem":
    check eval("(rem 10 3)", env).value.intVal == 1

  test "min":
    check eval("(min 3 7)", env).value.intVal == 3

  test "max":
    check eval("(max 3 7)", env).value.intVal == 7

suite "Eval - Special Forms":
  setup:
    let env = newTopLevelEnv()

  test "def":
    let r = eval("(def x 42)", env)
    check r.ok
    check r.isDef
    check r.defName == "x"

  test "defn and call":
    discard eval("(defn square [x] (* x x))", env)
    let r = eval("(square 5)", env)
    check r.ok
    check r.value.intVal == 25

  test "let":
    let r = eval("(let [a 10 b 20] (+ a b))", env)
    check r.ok
    check r.value.intVal == 30

  test "if true":
    let r = eval("(if true 1 2)", env)
    check r.ok
    check r.value.intVal == 1

  test "if false":
    let r = eval("(if false 1 2)", env)
    check r.ok
    check r.value.intVal == 2

  test "if nil is falsy":
    let r = eval("(if nil 1 2)", env)
    check r.ok
    check r.value.intVal == 2

  test "if without else":
    let r = eval("(if false 1)", env)
    check r.ok
    check r.value.kind == ckNil

  test "when":
    let r = eval("(when true 42)", env)
    check r.ok
    check r.value.intVal == 42

  test "when false":
    let r = eval("(when false 42)", env)
    check r.ok
    check r.value.kind == ckNil

  test "do":
    let r = eval("(do 1 2 3)", env)
    check r.ok
    check r.value.intVal == 3

  test "do empty":
    let r = eval("(do)", env)
    check r.ok
    check r.value.kind == ckNil

  test "fn and call":
    let r = eval("((fn [x] (+ x 1)) 5)", env)
    check r.ok
    check r.value.intVal == 6

  test "variadic fn":
    let r = eval("((fn [x & rest] (count rest)) 1 2 3 4)", env)
    check r.ok
    check r.value.intVal == 3

  test "quote":
    let r = eval("(quote (1 2 3))", env)
    check r.ok
    check r.value.kind == ckList
    check r.value.items.len == 3

suite "Eval - Collections":
  setup:
    let env = newTopLevelEnv()

  test "vector literal":
    let r = eval("[1 2 3]", env)
    check r.ok
    check r.value.kind == ckVector
    check r.value.items.len == 3

  test "list constructor":
    let r = eval("(list 1 2 3)", env)
    check r.ok
    check r.value.kind == ckList
    check r.value.items.len == 3

  test "vector constructor":
    let r = eval("(vector 1 2 3)", env)
    check r.ok
    check r.value.kind == ckVector
    check r.value.items.len == 3

  test "map literal":
    let r = eval("{:a 1 :b 2}", env)
    check r.ok
    check r.value.kind == ckMap
    check r.value.mapKeys.len == 2

  test "count":
    let r = eval("(count [1 2 3])", env)
    check r.ok
    check r.value.intVal == 3

  test "first":
    let r = eval("(first [10 20 30])", env)
    check r.ok
    check r.value.intVal == 10

  test "last":
    let r = eval("(last [10 20 30])", env)
    check r.ok
    check r.value.intVal == 30

  test "nth":
    let r = eval("(nth [10 20 30] 1)", env)
    check r.ok
    check r.value.intVal == 20

  test "rest":
    let r = eval("(rest [1 2 3])", env)
    check r.ok
    check r.value.items.len == 2

  test "conj vector":
    let r = eval("(conj [1 2] 3)", env)
    check r.ok
    check r.value.kind == ckVector
    check r.value.items.len == 3

  test "cons":
    let r = eval("(cons 0 [1 2])", env)
    check r.ok
    check r.value.items.len == 3
    check r.value.items[0].intVal == 0

  test "concat":
    let r = eval("(concat [1 2] [3 4])", env)
    check r.ok
    check r.value.items.len == 4

  test "reverse":
    let r = eval("(reverse [1 2 3])", env)
    check r.ok
    check r.value.items[0].intVal == 3
    check r.value.items[2].intVal == 1

  test "vec":
    let r = eval("(vec (list 1 2 3))", env)
    check r.ok
    check r.value.kind == ckVector
    check r.value.items.len == 3

  test "distinct":
    let r = eval("(distinct [1 2 2 3 3 3])", env)
    check r.ok
    check r.value.items.len == 3

  test "empty?":
    check eval("(empty? [])", env).value.boolVal == true
    check eval("(empty? [1])", env).value.boolVal == false

suite "Eval - Higher-order":
  setup:
    let env = newTopLevelEnv()

  test "map inc":
    let r = eval("(map inc [1 2 3])", env)
    check r.ok
    check r.value.items.len == 3
    check r.value.items[0].intVal == 2
    check r.value.items[2].intVal == 4

  test "filter":
    let r = eval("(filter (fn [x] (> x 2)) [1 2 3 4 5])", env)
    check r.ok
    check r.value.items.len == 3

  test "reduce":
    let r = eval("(reduce + 0 [1 2 3 4 5])", env)
    check r.ok
    check r.value.intVal == 15

  test "apply":
    let r = eval("(apply + [1 2 3])", env)
    check r.ok
    check r.value.intVal == 6

suite "Eval - String/Primitives":
  setup:
    let env = newTopLevelEnv()

  test "str concatenation":
    let r = eval("(str \"hello\" \" \" \"world\")", env)
    check r.ok
    check r.value.strVal == "hello world"

  test "println":
    let r = eval("(println \"test\")", env)
    check r.ok
    check r.value.kind == ckNil

  test "inc":
    let r = eval("(inc 41)", env)
    check r.ok
    check r.value.intVal == 42

  test "dec":
    let r = eval("(dec 43)", env)
    check r.ok
    check r.value.intVal == 42

  test "zero?":
    let r = eval("(zero? 0)", env)
    check r.ok
    check r.value.boolVal == true

  test "nil?":
    let r = eval("(nil? nil)", env)
    check r.ok
    check r.value.boolVal == true

  test "not":
    let r = eval("(not false)", env)
    check r.ok
    check r.value.boolVal == true

  test "type":
    let r = eval("(type 42)", env)
    check r.ok
    check r.value.kind == ckKeyword
    check r.value.kwName == "integer"

  test "true?":
    check eval("(true? true)", env).value.boolVal == true
    check eval("(true? false)", env).value.boolVal == false

  test "false?":
    check eval("(false? false)", env).value.boolVal == true
    check eval("(false? true)", env).value.boolVal == false

  test "instance?":
    check eval("(instance? :integer 42)", env).value.boolVal == true
    check eval("(instance? :string 42)", env).value.boolVal == false

suite "Eval - Map Operations":
  setup:
    let env = newTopLevelEnv()

  test "get from map":
    let r = eval("(get {:a 1 :b 2} :a)", env)
    check r.ok
    check r.value.intVal == 1

  test "get with default":
    let r = eval("(get {:a 1} :z 99)", env)
    check r.ok
    check r.value.intVal == 99

  test "assoc":
    let r = eval("(assoc {:a 1} :b 2)", env)
    check r.ok
    check r.value.mapKeys.len == 2

  test "dissoc":
    let r = eval("(dissoc {:a 1 :b 2} :a)", env)
    check r.ok
    check r.value.mapKeys.len == 1

  test "merge":
    let r = eval("(merge {:a 1} {:b 2})", env)
    check r.ok
    check r.value.mapKeys.len == 2

  test "keys":
    let r = eval("(keys {:a 1 :b 2})", env)
    check r.ok
    check r.value.items.len == 2

  test "vals":
    let r = eval("(vals {:a 1 :b 2})", env)
    check r.ok
    check r.value.items.len == 2

  test "contains?":
    let r = eval("(contains? {:a 1} :a)", env)
    check r.ok
    check r.value.boolVal == true

suite "Eval - Range/Take/Drop":
  setup:
    let env = newTopLevelEnv()

  test "range 5":
    let r = eval("(range 5)", env)
    check r.ok
    check r.value.items.len == 5
    check r.value.items[0].intVal == 0
    check r.value.items[4].intVal == 4

  test "range 1 to 5":
    let r = eval("(range 1 5)", env)
    check r.ok
    check r.value.items.len == 4
    check r.value.items[0].intVal == 1

  test "take":
    let r = eval("(take 3 [1 2 3 4 5])", env)
    check r.ok
    check r.value.items.len == 3

  test "drop":
    let r = eval("(drop 2 [1 2 3 4 5])", env)
    check r.ok
    check r.value.items.len == 3
    check r.value.items[0].intVal == 3

suite "Eval - Boolean Logic":
  setup:
    let env = newTopLevelEnv()

  test "and true":
    let r = eval("(and true true)", env)
    check r.ok
    check r.value.boolVal == true

  test "and false":
    let r = eval("(and true false)", env)
    check r.ok
    check r.value.boolVal == false

  test "or true":
    let r = eval("(or false true)", env)
    check r.ok
    check r.value.boolVal == true

  test "or false":
    let r = eval("(or false false)", env)
    check r.ok
    check r.value.kind == ckNil

  test "cond":
    let r = eval("(cond false 1 true 2 false 3)", env)
    check r.ok
    check r.value.intVal == 2

suite "Eval - Atoms":
  setup:
    let env = newTopLevelEnv()

  test "atom and deref":
    discard eval("(def a (atom 0))", env)
    let r = eval("(deref a)", env)
    check r.ok
    check r.value.intVal == 0

  test "swap! updates atom value":
    discard eval("(def a (atom 0))", env)
    let r = eval("(swap! a inc)", env)
    check r.ok
    check r.value.intVal == 1
    let r2 = eval("(deref a)", env)
    check r2.value.intVal == 1

  test "swap! with extra args":
    discard eval("(def a (atom 10))", env)
    let r = eval("(swap! a + 5)", env)
    check r.ok
    check r.value.intVal == 15

  test "reset! sets atom value":
    discard eval("(def a (atom 0))", env)
    let r = eval("(reset! a 42)", env)
    check r.ok
    check r.value.intVal == 42
    let r2 = eval("(deref a)", env)
    check r2.value.intVal == 42

suite "Eval - Agents":
  setup:
    let env = newTopLevelEnv()

  test "agent and deref":
    discard eval("(def ag (agent 10))", env)
    let r = eval("(deref ag)", env)
    check r.ok
    check r.value.intVal == 10

  test "send":
    discard eval("(def ag (agent 10))", env)
    let r = eval("(send ag inc)", env)
    check r.ok
    check eval("(deref ag)", env).value.intVal == 11

  test "await returns nil":
    discard eval("(def ag (agent 10))", env)
    let r = eval("(await ag)", env)
    check r.ok
    check r.value.kind == ckNil

suite "Eval - Channels":
  setup:
    let env = newTopLevelEnv()

  test "chan create returns string id":
    let r = eval("(chan)", env)
    check r.ok
    check r.value.kind == ckString

  test "chan put and take":
    discard eval("(def ch (chan))", env)
    let putR = eval("(>! ch 42)", env)
    check putR.ok
    let takeR = eval("(<! ch)", env)
    check takeR.ok
    check takeR.value.intVal == 42

  test "chan close":
    discard eval("(def ch (chan))", env)
    let r = eval("(close! ch)", env)
    check r.ok

suite "Eval - AI Functions (test doesn't require API keys)":
  setup:
    let env = newTopLevelEnv()

  test "ai/generate returns string or error":
    let r = eval("(ai/generate \"reverse a list\")", env)
    if r.ok:
      check r.value.kind == ckString
    else:
      check("API key" in r.error or "AI request failed" in r.error or "SSL" in r.error)

  test "ai/optimize returns string or error":
    let r = eval("(ai/optimize \"(reduce + nums)\")", env)
    if r.ok:
      check r.value.kind == ckString
    else:
      check("API key" in r.error or "AI request failed" in r.error or "SSL" in r.error)

  test "ai/debug returns string or error":
    let r = eval("(ai/debug (+ 1 2))", env)
    if r.ok:
      check r.value.kind == ckString
    else:
      check("API key" in r.error or "AI request failed" in r.error or "SSL" in r.error)
