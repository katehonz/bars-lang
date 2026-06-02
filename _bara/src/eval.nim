# Tree-walking interpreter for fast REPL evaluation
# Handles common cases without spawning nim c
import strutils, sequtils, tables, algorithm, times, deques
import types, reader, macros, ai_assist

var agentRegistry* = initTable[string, CljVal]()
var agentCounter*: int64 = 0
var atomRegistry* = initTable[string, CljVal]()
var atomCounter*: int64 = 0

type
  Channel* = ref object
    buf: Deque[CljVal]
    capacity: int  # 0 = unbuffered
    closed*: bool

var channelRegistry* = initTable[string, Channel]()
var channelCounter*: int64 = 0

type
  EvalError* = object of CatchableError

  Env* = ref object
    bindings*: Table[string, CljVal]
    parent*: Env

  EvalResult* = object
    ok*: bool
    value*: CljVal
    error*: string
    isDef*: bool
    defName*: string

proc newEnv(parent: Env = nil): Env =
  result = Env()
  result.bindings = initTable[string, CljVal]()
  result.parent = parent

proc envGet(env: Env, name: string): CljVal =
  var e = env
  while e != nil:
    if name in e.bindings:
      return e.bindings[name]
    e = e.parent
  return nil

proc envSet(env: Env, name: string, val: CljVal) =
  env.bindings[name] = val

proc envSetGlobal(env: Env, name: string, val: CljVal) =
  var e = env
  while e.parent != nil:
    e = e.parent
  e.bindings[name] = val

proc cljReprLocal(v: CljVal): string =
  if v.isNil: return "nil"
  case v.kind
  of ckNil: "nil"
  of ckBool:
    if v.boolVal: "true" else: "false"
  of ckInt: $v.intVal
  of ckFloat: $v.floatVal
  of ckString: "\"" & v.strVal & "\""
  of ckKeyword: ":" & v.kwName
  of ckSymbol: v.symName
  of ckList: "(" & v.items.mapIt(cljReprLocal(it)).join(" ") & ")"
  of ckVector: "[" & v.items.mapIt(cljReprLocal(it)).join(" ") & "]"
  of ckMap:
    var parts: seq[string] = @[]
    for i in 0..<v.mapKeys.len:
      parts.add(cljReprLocal(v.mapKeys[i]) & " " & cljReprLocal(v.mapVals[i]))
    "{" & parts.join(", ") & "}"
  of ckSet: "#{" & v.setItems.mapIt(cljReprLocal(it)).join(" ") & "}"
  of ckFn: "#<fn:" & v.fnName & ">"
  of ckAtom: "(atom " & cljReprLocal(v.atomVal) & ")"
  of ckTransient: "#<transient>"
  of ckAgent: "(agent " & cljReprLocal(v.agentVal) & ")"

proc evalAst*(form: CljVal, env: Env): EvalResult

proc evalList(items: seq[CljVal], env: Env): EvalResult =
  if items.len == 0:
    return EvalResult(ok: true, value: cljList(@[]))

  let head = items[0]

  # Special forms
  if head.kind == ckSymbol:
    case head.symName
    of "def":
      if items.len < 3:
        return EvalResult(ok: false, error: "def requires name and value")
      let name = items[1]
      if name.kind != ckSymbol:
        return EvalResult(ok: false, error: "def name must be a symbol")
      let valRes = evalAst(items[2], env)
      if not valRes.ok: return valRes
      envSetGlobal(env, name.symName, valRes.value)
      return EvalResult(ok: true, value: valRes.value, isDef: true, defName: name.symName)

    of "defn":
      if items.len < 4:
        return EvalResult(ok: false, error: "defn requires name, params, and body")
      let name = items[1]
      if name.kind != ckSymbol:
        return EvalResult(ok: false, error: "defn name must be a symbol")
      let params = items[2]
      let body = items[3..^1]
      let fnVal = cljList(@[cljSymbol("fn"), params] & body)
      envSetGlobal(env, name.symName, fnVal)
      return EvalResult(ok: true, value: fnVal, isDef: true, defName: name.symName)

    of "fn":
      if items.len < 3:
        return EvalResult(ok: false, error: "fn requires params and body")
      return EvalResult(ok: true, value: cljList(items))

    of "let":
      if items.len < 3:
        return EvalResult(ok: false, error: "let requires bindings and body")
      let bindings = items[1]
      if bindings.kind != ckVector:
        return EvalResult(ok: false, error: "let bindings must be a vector")
      let letEnv = newEnv(env)
      var i = 0
      while i < bindings.items.len:
        if i + 1 >= bindings.items.len:
          return EvalResult(ok: false, error: "let bindings must be in pairs")
        let bName = bindings.items[i]
        let bVal = bindings.items[i+1]
        if bName.kind != ckSymbol:
          return EvalResult(ok: false, error: "let binding name must be a symbol")
        let valRes = evalAst(bVal, letEnv)
        if not valRes.ok: return valRes
        envSet(letEnv, bName.symName, valRes.value)
        i += 2
      var lastVal: CljVal = cljNil()
      for bi in 2..<items.len:
        let bodyRes = evalAst(items[bi], letEnv)
        if not bodyRes.ok: return bodyRes
        lastVal = bodyRes.value
      return EvalResult(ok: true, value: lastVal)

    of "if":
      if items.len < 3:
        return EvalResult(ok: false, error: "if requires condition and then")
      let condRes = evalAst(items[1], env)
      if not condRes.ok: return condRes
      let isTruthy = not (condRes.value.kind == ckNil or
        (condRes.value.kind == ckBool and not condRes.value.boolVal))
      if isTruthy:
        return evalAst(items[2], env)
      elif items.len >= 4:
        return evalAst(items[3], env)
      else:
        return EvalResult(ok: true, value: cljNil())

    of "do":
      var lastVal: CljVal = cljNil()
      for i in 1..<items.len:
        let res = evalAst(items[i], env)
        if not res.ok: return res
        lastVal = res.value
      return EvalResult(ok: true, value: lastVal)

    of "quote":
      if items.len < 2:
        return EvalResult(ok: false, error: "quote requires an argument")
      return EvalResult(ok: true, value: items[1])

    of "when":
      if items.len < 3:
        return EvalResult(ok: false, error: "when requires condition and body")
      let condRes = evalAst(items[1], env)
      if not condRes.ok: return condRes
      let isTruthy = not (condRes.value.kind == ckNil or
        (condRes.value.kind == ckBool and not condRes.value.boolVal))
      if isTruthy:
        var lastVal: CljVal = cljNil()
        for i in 2..<items.len:
          let res = evalAst(items[i], env)
          if not res.ok: return res
          lastVal = res.value
        return EvalResult(ok: true, value: lastVal)
      return EvalResult(ok: true, value: cljNil())

    of "cond":
      var i = 1
      while i + 1 < items.len:
        let condRes = evalAst(items[i], env)
        if not condRes.ok: return condRes
        let isTruthy = not (condRes.value.kind == ckNil or
          (condRes.value.kind == ckBool and not condRes.value.boolVal))
        if isTruthy:
          return evalAst(items[i+1], env)
        i += 2
      return EvalResult(ok: true, value: cljNil())

    of "not":
      if items.len < 2:
        return EvalResult(ok: false, error: "not requires an argument")
      let argRes = evalAst(items[1], env)
      if not argRes.ok: return argRes
      let isFalsy = argRes.value.kind == ckNil or
        (argRes.value.kind == ckBool and not argRes.value.boolVal)
      return EvalResult(ok: true, value: cljBool(isFalsy))

    of "and":
      var lastVal: CljVal = cljBool(true)
      for i in 1..<items.len:
        let res = evalAst(items[i], env)
        if not res.ok: return res
        let isFalsy = res.value.kind == ckNil or
          (res.value.kind == ckBool and not res.value.boolVal)
        if isFalsy:
          return EvalResult(ok: true, value: res.value)
        lastVal = res.value
      return EvalResult(ok: true, value: lastVal)

    of "or":
      for i in 1..<items.len:
        let res = evalAst(items[i], env)
        if not res.ok: return res
        let isTruthy = not (res.value.kind == ckNil or
          (res.value.kind == ckBool and not res.value.boolVal))
        if isTruthy:
          return EvalResult(ok: true, value: res.value)
      return EvalResult(ok: true, value: cljNil())

    of "macroexpand":
      if items.len < 2:
        return EvalResult(ok: false, error: "macroexpand requires an expression")
      let argRes = evalAst(items[1], env)
      if not argRes.ok: return argRes
      return EvalResult(ok: true, value: macroexpand(argRes.value))

    of "macroexpand-1":
      if items.len < 2:
        return EvalResult(ok: false, error: "macroexpand-1 requires an expression")
      let argRes = evalAst(items[1], env)
      if not argRes.ok: return argRes
      return EvalResult(ok: true, value: macroexpand1(argRes.value))

    of "ai/debug", "ai.debug":
      if items.len < 2:
        return EvalResult(ok: false, error: "ai/debug requires an expression")
      if not ai_assist.hasAiConfig():
        return EvalResult(ok: false, error: "No AI API key configured.")
      var exprStr = cljReprLocal(items[1])
      var evalRes: EvalResult
      try:
        evalRes = evalAst(items[1], env)
      except CatchableError as e:
        return EvalResult(ok: false, error: "ai/debug: evaluation failed: " & e.msg)
      let resultStr = if evalRes.ok:
        if evalRes.value.kind == ckString: evalRes.value.strVal else: cljReprLocal(evalRes.value)
      else:
        "Error: " & evalRes.error
      let aiRes = ai_assist.debugCode(exprStr, resultStr)
      if not aiRes.ok:
        return EvalResult(ok: false, error: aiRes.suggestion)
      return EvalResult(ok: true, value: cljString(aiRes.suggestion))

    else:
      discard

  # Function call: evaluate head and all args
  let headRes = evalAst(head, env)
  if not headRes.ok: return headRes

  var args: seq[CljVal] = @[]
  for i in 1..<items.len:
    let argRes = evalAst(items[i], env)
    if not argRes.ok: return argRes
    args.add(argRes.value)

  let fnVal = headRes.value

  # Check if it's a lambda (fn form stored as list)
  if fnVal.kind == ckList and fnVal.items.len >= 3 and
     fnVal.items[0].kind == ckSymbol and fnVal.items[0].symName == "fn":
    let params = fnVal.items[1]
    let body = fnVal.items[2..^1]
    if params.kind != ckVector:
      return EvalResult(ok: false, error: "fn params must be a vector")
    let callEnv = newEnv(env)
    for pi in 0..<params.items.len:
      if params.items[pi].kind == ckSymbol:
        let pName = params.items[pi].symName
        if pName == "&":
          # variadic
          if pi + 1 < params.items.len:
            let restName = params.items[pi+1].symName
            envSet(callEnv, restName, cljList(args[pi..^1]))
          break
        elif pi < args.len:
          envSet(callEnv, pName, args[pi])
    var lastVal: CljVal = cljNil()
    for bi in 0..<body.len:
      let bodyRes = evalAst(body[bi], callEnv)
      if not bodyRes.ok: return bodyRes
      lastVal = bodyRes.value
    return EvalResult(ok: true, value: lastVal)

  # Built-in functions
  proc evalBuiltin(name: string, args: seq[CljVal]): EvalResult =
    template numArgs(n: int) =
      if args.len != n:
        return EvalResult(ok: false, error: name & " requires " & $n & " args")
    template atLeast(n: int) =
      if args.len < n:
        return EvalResult(ok: false, error: name & " requires at least " & $n & " args")

    case name
    of "+":
      atLeast(1)
      var sum: int64 = 0
      var hasFloat = false
      var fsum: float64 = 0.0
      for a in args:
        if a.kind == ckFloat:
          hasFloat = true
          fsum += a.floatVal
        elif a.kind == ckInt:
          if hasFloat: fsum += a.floatVal.float64
          else: sum += a.intVal
        else:
          return EvalResult(ok: false, error: "+ requires numbers")
      if hasFloat:
        return EvalResult(ok: true, value: cljFloat(fsum + sum.float64))
      return EvalResult(ok: true, value: cljInt(sum))

    of "-":
      atLeast(1)
      if args.len == 1:
        if args[0].kind == ckInt: return EvalResult(ok: true, value: cljInt(-args[0].intVal))
        if args[0].kind == ckFloat: return EvalResult(ok: true, value: cljFloat(-args[0].floatVal))
        return EvalResult(ok: false, error: "- requires numbers")
      var sum: float64
      if args[0].kind == ckInt: sum = args[0].intVal.float64
      elif args[0].kind == ckFloat: sum = args[0].floatVal
      else: return EvalResult(ok: false, error: "- requires numbers")
      for i in 1..<args.len:
        if args[i].kind == ckInt: sum -= args[i].intVal.float64
        elif args[i].kind == ckFloat: sum -= args[i].floatVal
        else: return EvalResult(ok: false, error: "- requires numbers")
      if sum == sum.int64.float64 and args[0].kind == ckInt:
        var allInt = true
        for i in 1..<args.len:
          if args[i].kind != ckInt: allInt = false
        if allInt: return EvalResult(ok: true, value: cljInt(sum.int64))
      return EvalResult(ok: true, value: cljFloat(sum))

    of "*":
      atLeast(1)
      var product: int64 = 1
      var hasFloat = false
      var fproduct: float64 = 1.0
      for a in args:
        if a.kind == ckFloat:
          hasFloat = true
          fproduct *= a.floatVal
        elif a.kind == ckInt:
          if hasFloat: fproduct *= a.floatVal.float64
          else: product *= a.intVal
        else:
          return EvalResult(ok: false, error: "* requires numbers")
      if hasFloat:
        return EvalResult(ok: true, value: cljFloat(fproduct * product.float64))
      return EvalResult(ok: true, value: cljInt(product))

    of "/":
      numArgs(2)
      if args[0].kind == ckInt and args[1].kind == ckInt:
        if args[1].intVal == 0:
          return EvalResult(ok: false, error: "Division by zero")
        return EvalResult(ok: true, value: cljInt(args[0].intVal div args[1].intVal))
      var a, b: float64
      if args[0].kind == ckInt: a = args[0].intVal.float64
      elif args[0].kind == ckFloat: a = args[0].floatVal
      else: return EvalResult(ok: false, error: "/ requires numbers")
      if args[1].kind == ckInt: b = args[1].intVal.float64
      elif args[1].kind == ckFloat: b = args[1].floatVal
      else: return EvalResult(ok: false, error: "/ requires numbers")
      if b == 0: return EvalResult(ok: false, error: "Division by zero")
      return EvalResult(ok: true, value: cljFloat(a / b))

    of "=":
      proc evalEqual(a, b: CljVal): bool =
        if a.isNil and b.isNil: return true
        if a.isNil or b.isNil: return false
        if a.kind == ckInt and b.kind == ckFloat:
          return a.intVal.float64 == b.floatVal
        if a.kind == ckFloat and b.kind == ckInt:
          return a.floatVal == b.intVal.float64
        if a.kind != b.kind: return false
        case a.kind
        of ckNil: true
        of ckBool: a.boolVal == b.boolVal
        of ckInt: a.intVal == b.intVal
        of ckFloat: a.floatVal == b.floatVal
        of ckString: a.strVal == b.strVal
        of ckKeyword: a.kwName == b.kwName
        of ckSymbol: a.symName == b.symName
        of ckList, ckVector:
          if a.items.len != b.items.len: return false
          for i in 0..<a.items.len:
            if not evalEqual(a.items[i], b.items[i]): return false
          true
        of ckMap:
          if a.mapKeys.len != b.mapKeys.len: return false
          for ai in 0..<a.mapKeys.len:
            var found = false
            for bi in 0..<b.mapKeys.len:
              if evalEqual(a.mapKeys[ai], b.mapKeys[bi]) and
                 evalEqual(a.mapVals[ai], b.mapVals[bi]):
                found = true
                break
            if not found: return false
          true
        of ckSet:
          if a.setItems.len != b.setItems.len: return false
          for ai in a.setItems:
            var found = false
            for bi in b.setItems:
              if evalEqual(ai, bi):
                found = true
                break
            if not found: return false
          true
        else: false
      numArgs(2)
      return EvalResult(ok: true, value: cljBool(evalEqual(args[0], args[1])))

    of "not=":
      numArgs(2)
      let eqRes = evalBuiltin("=", args)
      if not eqRes.ok: return eqRes
      return EvalResult(ok: true, value: cljBool(not eqRes.value.boolVal))

    of ">":
      numArgs(2)
      if args[0].kind == ckInt and args[1].kind == ckInt:
        return EvalResult(ok: true, value: cljBool(args[0].intVal > args[1].intVal))
      var a, b: float64
      if args[0].kind == ckInt: a = args[0].intVal.float64
      elif args[0].kind == ckFloat: a = args[0].floatVal
      else: return EvalResult(ok: false, error: "> requires numbers")
      if args[1].kind == ckInt: b = args[1].intVal.float64
      elif args[1].kind == ckFloat: b = args[1].floatVal
      else: return EvalResult(ok: false, error: "> requires numbers")
      return EvalResult(ok: true, value: cljBool(a > b))

    of "<":
      numArgs(2)
      if args[0].kind == ckInt and args[1].kind == ckInt:
        return EvalResult(ok: true, value: cljBool(args[0].intVal < args[1].intVal))
      var a, b: float64
      if args[0].kind == ckInt: a = args[0].intVal.float64
      elif args[0].kind == ckFloat: a = args[0].floatVal
      else: return EvalResult(ok: false, error: "< requires numbers")
      if args[1].kind == ckInt: b = args[1].intVal.float64
      elif args[1].kind == ckFloat: b = args[1].floatVal
      else: return EvalResult(ok: false, error: "< requires numbers")
      return EvalResult(ok: true, value: cljBool(a < b))

    of ">=":
      numArgs(2)
      if args[0].kind == ckInt and args[1].kind == ckInt:
        return EvalResult(ok: true, value: cljBool(args[0].intVal >= args[1].intVal))
      var a, b: float64
      if args[0].kind == ckInt: a = args[0].intVal.float64
      elif args[0].kind == ckFloat: a = args[0].floatVal
      else: return EvalResult(ok: false, error: ">= requires numbers")
      if args[1].kind == ckInt: b = args[1].intVal.float64
      elif args[1].kind == ckFloat: b = args[1].floatVal
      else: return EvalResult(ok: false, error: ">= requires numbers")
      return EvalResult(ok: true, value: cljBool(a >= b))

    of "<=":
      numArgs(2)
      if args[0].kind == ckInt and args[1].kind == ckInt:
        return EvalResult(ok: true, value: cljBool(args[0].intVal <= args[1].intVal))
      var a, b: float64
      if args[0].kind == ckInt: a = args[0].intVal.float64
      elif args[0].kind == ckFloat: a = args[0].floatVal
      else: return EvalResult(ok: false, error: "<= requires numbers")
      if args[1].kind == ckInt: b = args[1].intVal.float64
      elif args[1].kind == ckFloat: b = args[1].floatVal
      else: return EvalResult(ok: false, error: "<= requires numbers")
      return EvalResult(ok: true, value: cljBool(a <= b))

    of "println":
      var parts: seq[string] = @[]
      for a in args:
        if a.kind == ckNil: parts.add("nil")
        elif a.kind == ckString: parts.add(a.strVal)
        elif a.kind == ckBool: parts.add(if a.boolVal: "true" else: "false")
        else: parts.add(cljReprLocal(a))
      echo parts.join(" ")
      return EvalResult(ok: true, value: cljNil())

    of "prn":
      var parts: seq[string] = @[]
      for a in args:
        parts.add(cljReprLocal(a))
      echo parts.join(" ")
      return EvalResult(ok: true, value: cljNil())

    of "str":
      atLeast(1)
      var s = ""
      for a in args:
        if a.kind == ckNil: s.add("nil")
        elif a.kind == ckString: s.add(a.strVal)
        elif a.kind == ckBool: s.add(if a.boolVal: "true" else: "false")
        elif a.kind == ckInt: s.add($a.intVal)
        elif a.kind == ckFloat: s.add($a.floatVal)
        else: s.add(cljReprLocal(a))
      return EvalResult(ok: true, value: cljString(s))

    of "pr-str":
      atLeast(0)
      var parts: seq[string] = @[]
      for a in args:
        parts.add(cljReprLocal(a))
      return EvalResult(ok: true, value: cljString(parts.join(" ")))

    of "inc":
      numArgs(1)
      if args[0].kind == ckInt:
        return EvalResult(ok: true, value: cljInt(args[0].intVal + 1))
      if args[0].kind == ckFloat:
        return EvalResult(ok: true, value: cljFloat(args[0].floatVal + 1.0))
      return EvalResult(ok: false, error: "inc requires a number")

    of "dec":
      numArgs(1)
      if args[0].kind == ckInt:
        return EvalResult(ok: true, value: cljInt(args[0].intVal - 1))
      if args[0].kind == ckFloat:
        return EvalResult(ok: true, value: cljFloat(args[0].floatVal - 1.0))
      return EvalResult(ok: false, error: "dec requires a number")

    of "zero?":
      numArgs(1)
      if args[0].kind == ckInt:
        return EvalResult(ok: true, value: cljBool(args[0].intVal == 0))
      if args[0].kind == ckFloat:
        return EvalResult(ok: true, value: cljBool(args[0].floatVal == 0.0))
      return EvalResult(ok: false, error: "zero? requires a number")

    of "pos?":
      numArgs(1)
      if args[0].kind == ckInt:
        return EvalResult(ok: true, value: cljBool(args[0].intVal > 0))
      if args[0].kind == ckFloat:
        return EvalResult(ok: true, value: cljBool(args[0].floatVal > 0.0))
      return EvalResult(ok: false, error: "pos? requires a number")

    of "neg?":
      numArgs(1)
      if args[0].kind == ckInt:
        return EvalResult(ok: true, value: cljBool(args[0].intVal < 0))
      if args[0].kind == ckFloat:
        return EvalResult(ok: true, value: cljBool(args[0].floatVal < 0.0))
      return EvalResult(ok: false, error: "neg? requires a number")

    of "even?":
      numArgs(1)
      if args[0].kind == ckInt:
        return EvalResult(ok: true, value: cljBool(args[0].intVal mod 2 == 0))
      return EvalResult(ok: false, error: "even? requires an integer")

    of "odd?":
      numArgs(1)
      if args[0].kind == ckInt:
        return EvalResult(ok: true, value: cljBool(args[0].intVal mod 2 != 0))
      return EvalResult(ok: false, error: "odd? requires an integer")

    of "count":
      numArgs(1)
      if args[0].kind in {ckList, ckVector}:
        return EvalResult(ok: true, value: cljInt(args[0].items.len.int64))
      if args[0].kind == ckString:
        return EvalResult(ok: true, value: cljInt(args[0].strVal.len.int64))
      if args[0].kind == ckNil:
        return EvalResult(ok: true, value: cljInt(0))
      return EvalResult(ok: false, error: "count requires a collection")

    of "first":
      numArgs(1)
      if args[0].kind in {ckList, ckVector}:
        if args[0].items.len == 0:
          return EvalResult(ok: true, value: cljNil())
        return EvalResult(ok: true, value: args[0].items[0])
      if args[0].kind == ckNil:
        return EvalResult(ok: true, value: cljNil())
      return EvalResult(ok: false, error: "first requires a collection")

    of "rest":
      numArgs(1)
      if args[0].kind in {ckList, ckVector}:
        if args[0].items.len <= 1:
          return EvalResult(ok: true, value: cljList(@[]))
        return EvalResult(ok: true, value: cljList(args[0].items[1..^1]))
      if args[0].kind == ckNil:
        return EvalResult(ok: true, value: cljList(@[]))
      return EvalResult(ok: false, error: "rest requires a collection")

    of "last":
      numArgs(1)
      if args[0].kind in {ckList, ckVector}:
        if args[0].items.len == 0:
          return EvalResult(ok: true, value: cljNil())
        return EvalResult(ok: true, value: args[0].items[^1])
      return EvalResult(ok: false, error: "last requires a collection")

    of "nth":
      numArgs(2)
      if args[0].kind in {ckList, ckVector} and args[1].kind == ckInt:
        let idx = args[1].intVal.int
        if idx < 0 or idx >= args[0].items.len:
          return EvalResult(ok: false, error: "nth: index out of bounds")
        return EvalResult(ok: true, value: args[0].items[idx])
      return EvalResult(ok: false, error: "nth requires a collection and integer index")

    of "conj":
      atLeast(2)
      let coll = args[0]
      let items = args[1..^1]
      if coll.kind == ckList:
        var newItems: seq[CljVal] = @[]
        for item in items:
          newItems.add(item)
        newItems.add(coll.items)
        return EvalResult(ok: true, value: cljList(newItems))
      if coll.kind == ckVector:
        var newItems = coll.items
        for item in items:
          newItems.add(item)
        return EvalResult(ok: true, value: cljVector(newItems))
      return EvalResult(ok: false, error: "conj requires a collection")

    of "cons":
      numArgs(2)
      let item = args[0]
      let coll = args[1]
      if coll.kind in {ckList, ckVector}:
        var newItems = @[item]
        newItems.add(coll.items)
        return EvalResult(ok: true, value: cljList(newItems))
      return EvalResult(ok: false, error: "cons requires a collection")

    of "concat":
      var res: seq[CljVal] = @[]
      for a in args:
        if a.kind in {ckList, ckVector}:
          res.add(a.items)
      return EvalResult(ok: true, value: cljList(res))

    of "reverse":
      numArgs(1)
      if args[0].kind in {ckList, ckVector}:
        var newItems: seq[CljVal] = @[]
        for i in countdown(args[0].items.len - 1, 0):
          newItems.add(args[0].items[i])
        return EvalResult(ok: true, value: cljList(newItems))
      return EvalResult(ok: false, error: "reverse requires a collection")

    of "vec":
      numArgs(1)
      if args[0].kind == ckList:
        return EvalResult(ok: true, value: cljVector(args[0].items))
      if args[0].kind == ckVector:
        return EvalResult(ok: true, value: args[0])
      return EvalResult(ok: false, error: "vec requires a list")

    of "list":
      return EvalResult(ok: true, value: cljList(args))

    of "vector":
      return EvalResult(ok: true, value: cljVector(args))

    of "map":
      # (map f coll)
      numArgs(2)
      let fn = args[0]
      let coll = args[1]
      if coll.kind in {ckList, ckVector}:
        var res: seq[CljVal] = @[]
        for item in coll.items:
          let callItems = @[fn, item]
          let callRes = evalList(callItems, env)
          if not callRes.ok: return callRes
          res.add(callRes.value)
        return EvalResult(ok: true, value: cljList(res))
      return EvalResult(ok: false, error: "map requires a function and collection")

    of "filter":
      numArgs(2)
      let fn = args[0]
      let coll = args[1]
      if coll.kind in {ckList, ckVector}:
        var res: seq[CljVal] = @[]
        for item in coll.items:
          let callItems = @[fn, item]
          let callRes = evalList(callItems, env)
          if not callRes.ok: return callRes
          let isTruthy = not (callRes.value.kind == ckNil or
            (callRes.value.kind == ckBool and not callRes.value.boolVal))
          if isTruthy:
            res.add(item)
        return EvalResult(ok: true, value: cljList(res))
      return EvalResult(ok: false, error: "filter requires a function and collection")

    of "reduce":
      atLeast(2)
      let fn = args[0]
      var acc: CljVal
      var coll: CljVal
      if args.len == 3:
        acc = args[1]
        coll = args[2]
      else:
        coll = args[1]
        if coll.kind in {ckList, ckVector}:
          if coll.items.len == 0:
            return EvalResult(ok: false, error: "reduce of empty collection with no initial value")
          acc = coll.items[0]
          var res = acc
          for i in 1..<coll.items.len:
            let callItems = @[fn, res, coll.items[i]]
            let callRes = evalList(callItems, env)
            if not callRes.ok: return callRes
            res = callRes.value
          return EvalResult(ok: true, value: res)
        return EvalResult(ok: true, value: cljNil())
      if coll.kind in {ckList, ckVector}:
        var res = acc
        for item in coll.items:
          let callItems = @[fn, res, item]
          let callRes = evalList(callItems, env)
          if not callRes.ok: return callRes
          res = callRes.value
        return EvalResult(ok: true, value: res)
      return EvalResult(ok: false, error: "reduce requires a function and collection")

    of "apply":
      atLeast(2)
      let fn = args[0]
      let lastColl = args[^1]
      var allArgs: seq[CljVal] = @[]
      for i in 1..<args.len - 1:
        allArgs.add(args[i])
      if lastColl.kind in {ckList, ckVector}:
        allArgs.add(lastColl.items)
      var callItems = @[fn]
      callItems.add(allArgs)
      return evalList(callItems, env)

    of "identity":
      numArgs(1)
      return EvalResult(ok: true, value: args[0])

    of "get":
      atLeast(2)
      let m = args[0]
      let key = args[1]
      let default = if args.len >= 3: args[2] else: cljNil()
      if m.kind == ckMap:
        for i in 0..<m.mapKeys.len:
          let eqRes = evalBuiltin("=", @[m.mapKeys[i], key])
          if eqRes.ok and eqRes.value.kind == ckBool and eqRes.value.boolVal:
            return EvalResult(ok: true, value: m.mapVals[i])
        return EvalResult(ok: true, value: default)
      if m.kind == ckVector and key.kind == ckInt:
        let idx = key.intVal.int
        if idx >= 0 and idx < m.items.len:
          return EvalResult(ok: true, value: m.items[idx])
        return EvalResult(ok: true, value: default)
      if m.kind == ckNil:
        return EvalResult(ok: true, value: default)
      return EvalResult(ok: false, error: "get requires a map or vector")

    of "assoc":
      atLeast(3)
      let m = args[0]
      if m.kind == ckMap:
        var newKeys = m.mapKeys
        var newVals = m.mapVals
        var i = 1
        while i + 1 < args.len:
          let key = args[i]
          let val = args[i+1]
          var found = false
          for j in 0..<newKeys.len:
            let eqRes = evalBuiltin("=", @[newKeys[j], key])
            if eqRes.ok and eqRes.value.kind == ckBool and eqRes.value.boolVal:
              newVals[j] = val
              found = true
              break
          if not found:
            newKeys.add(key)
            newVals.add(val)
          i += 2
        return EvalResult(ok: true, value: cljMap(newKeys, newVals))
      return EvalResult(ok: false, error: "assoc requires a map")

    of "dissoc":
      atLeast(2)
      let m = args[0]
      if m.kind == ckMap:
        var newKeys: seq[CljVal] = @[]
        var newVals: seq[CljVal] = @[]
        for i in 0..<m.mapKeys.len:
          var shouldRemove = false
          for j in 1..<args.len:
            let eqRes = evalBuiltin("=", @[m.mapKeys[i], args[j]])
            if eqRes.ok and eqRes.value.kind == ckBool and eqRes.value.boolVal:
              shouldRemove = true
              break
          if not shouldRemove:
            newKeys.add(m.mapKeys[i])
            newVals.add(m.mapVals[i])
        return EvalResult(ok: true, value: cljMap(newKeys, newVals))
      return EvalResult(ok: false, error: "dissoc requires a map")

    of "keys":
      numArgs(1)
      if args[0].kind == ckMap:
        return EvalResult(ok: true, value: cljList(args[0].mapKeys))
      return EvalResult(ok: false, error: "keys requires a map")

    of "vals":
      numArgs(1)
      if args[0].kind == ckMap:
        return EvalResult(ok: true, value: cljList(args[0].mapVals))
      return EvalResult(ok: false, error: "vals requires a map")

    of "contains?":
      numArgs(2)
      let coll = args[0]
      let key = args[1]
      if coll.kind == ckMap:
        for i in 0..<coll.mapKeys.len:
          let eqRes = evalBuiltin("=", @[coll.mapKeys[i], key])
          if eqRes.ok and eqRes.value.kind == ckBool and eqRes.value.boolVal:
            return EvalResult(ok: true, value: cljBool(true))
        return EvalResult(ok: true, value: cljBool(false))
      if coll.kind in {ckList, ckVector}:
        for item in coll.items:
          let eqRes = evalBuiltin("=", @[item, key])
          if eqRes.ok and eqRes.value.kind == ckBool and eqRes.value.boolVal:
            return EvalResult(ok: true, value: cljBool(true))
        return EvalResult(ok: true, value: cljBool(false))
      return EvalResult(ok: false, error: "contains? requires a collection")

    of "merge":
      var resultKeys: seq[CljVal] = @[]
      var resultVals: seq[CljVal] = @[]
      for a in args:
        if a.kind == ckMap:
          for i in 0..<a.mapKeys.len:
            var found = false
            for j in 0..<resultKeys.len:
              let eqRes = evalBuiltin("=", @[resultKeys[j], a.mapKeys[i]])
              if eqRes.ok and eqRes.value.kind == ckBool and eqRes.value.boolVal:
                resultVals[j] = a.mapVals[i]
                found = true
                break
            if not found:
              resultKeys.add(a.mapKeys[i])
              resultVals.add(a.mapVals[i])
        elif a.kind != ckNil:
          discard
      return EvalResult(ok: true, value: cljMap(resultKeys, resultVals))

    of "empty?":
      numArgs(1)
      if args[0].kind in {ckList, ckVector}:
        return EvalResult(ok: true, value: cljBool(args[0].items.len == 0))
      if args[0].kind == ckMap:
        return EvalResult(ok: true, value: cljBool(args[0].mapKeys.len == 0))
      if args[0].kind == ckString:
        return EvalResult(ok: true, value: cljBool(args[0].strVal.len == 0))
      if args[0].kind == ckNil:
        return EvalResult(ok: true, value: cljBool(true))
      return EvalResult(ok: false, error: "empty? requires a collection")

    of "nil?":
      numArgs(1)
      return EvalResult(ok: true, value: cljBool(args[0].kind == ckNil))

    of "true?":
      numArgs(1)
      return EvalResult(ok: true, value: cljBool(args[0].kind == ckBool and args[0].boolVal))

    of "false?":
      numArgs(1)
      return EvalResult(ok: true, value: cljBool(args[0].kind == ckBool and not args[0].boolVal))

    of "type":
      numArgs(1)
      let typeName = case args[0].kind
        of ckNil: "nil"
        of ckBool: "boolean"
        of ckInt: "integer"
        of ckFloat: "float"
        of ckString: "string"
        of ckKeyword: "keyword"
        of ckSymbol: "symbol"
        of ckList: "list"
        of ckVector: "vector"
        of ckMap: "map"
        of ckSet: "set"
        of ckFn: "fn"
        of ckAtom: "atom"
        of ckTransient: "transient"
        of ckAgent: "agent"
      return EvalResult(ok: true, value: cljKeyword(typeName))

    of "abs":
      numArgs(1)
      if args[0].kind == ckInt:
        return EvalResult(ok: true, value: cljInt(abs(args[0].intVal)))
      if args[0].kind == ckFloat:
        return EvalResult(ok: true, value: cljFloat(abs(args[0].floatVal)))
      return EvalResult(ok: false, error: "abs requires a number")

    of "mod":
      numArgs(2)
      if args[0].kind == ckInt and args[1].kind == ckInt:
        return EvalResult(ok: true, value: cljInt(args[0].intVal mod args[1].intVal))
      return EvalResult(ok: false, error: "mod requires integers")

    of "quot":
      numArgs(2)
      if args[0].kind == ckInt and args[1].kind == ckInt:
        if args[1].intVal == 0:
          return EvalResult(ok: false, error: "Division by zero")
        return EvalResult(ok: true, value: cljInt(args[0].intVal div args[1].intVal))
      return EvalResult(ok: false, error: "quot requires integers")

    of "rem":
      numArgs(2)
      if args[0].kind == ckInt and args[1].kind == ckInt:
        if args[1].intVal == 0:
          return EvalResult(ok: false, error: "Division by zero")
        return EvalResult(ok: true, value: cljInt(args[0].intVal - (args[0].intVal div args[1].intVal) * args[1].intVal))
      return EvalResult(ok: false, error: "rem requires integers")

    of "min":
      numArgs(2)
      if args[0].kind == ckInt and args[1].kind == ckInt:
        return EvalResult(ok: true, value: cljInt(min(args[0].intVal, args[1].intVal)))
      return EvalResult(ok: false, error: "min requires integers")

    of "max":
      numArgs(2)
      if args[0].kind == ckInt and args[1].kind == ckInt:
        return EvalResult(ok: true, value: cljInt(max(args[0].intVal, args[1].intVal)))
      return EvalResult(ok: false, error: "max requires integers")

    of "range":
      if args.len == 0:
        return EvalResult(ok: false, error: "range requires at least 1 arg")
      if args.len == 1 and args[0].kind == ckInt:
        var items: seq[CljVal] = @[]
        for i in 0..<args[0].intVal:
          items.add(cljInt(i))
        return EvalResult(ok: true, value: cljList(items))
      if args.len == 2 and args[0].kind == ckInt and args[1].kind == ckInt:
        var items: seq[CljVal] = @[]
        for i in args[0].intVal..<args[1].intVal:
          items.add(cljInt(i))
        return EvalResult(ok: true, value: cljList(items))
      if args.len == 3 and args[0].kind == ckInt and args[1].kind == ckInt and args[2].kind == ckInt:
        var items: seq[CljVal] = @[]
        var i = args[0].intVal
        let step = args[2].intVal
        let endVal = args[1].intVal
        if step > 0:
          while i < endVal:
            items.add(cljInt(i))
            i += step
        elif step < 0:
          while i > endVal:
            items.add(cljInt(i))
            i += step
        return EvalResult(ok: true, value: cljList(items))
      return EvalResult(ok: false, error: "range requires integers")

    of "take":
      numArgs(2)
      if args[0].kind == ckInt and args[1].kind in {ckList, ckVector}:
        let n = min(args[0].intVal.int, args[1].items.len)
        return EvalResult(ok: true, value: cljList(args[1].items[0..<n]))
      return EvalResult(ok: false, error: "take requires an integer and collection")

    of "drop":
      numArgs(2)
      if args[0].kind == ckInt and args[1].kind in {ckList, ckVector}:
        let n = min(args[0].intVal.int, args[1].items.len)
        return EvalResult(ok: true, value: cljList(args[1].items[n..^1]))
      return EvalResult(ok: false, error: "drop requires an integer and collection")

    of "sort":
      numArgs(1)
      if args[0].kind in {ckList, ckVector}:
        var items = args[0].items
        sort(items, proc(a, b: CljVal): int =
          if a.kind == ckInt and b.kind == ckInt:
            result = cmp(a.intVal, b.intVal)
          elif a.kind == ckFloat and b.kind == ckFloat:
            result = cmp(a.floatVal, b.floatVal)
          else:
            result = 0
        )
        return EvalResult(ok: true, value: cljList(items))
      return EvalResult(ok: false, error: "sort requires a collection")

    of "distinct":
      numArgs(1)
      if args[0].kind in {ckList, ckVector}:
        var res: seq[CljVal] = @[]
        for item in args[0].items:
          var isDup = false
          for existing in res:
            let eqRes = evalBuiltin("=", @[existing, item])
            if eqRes.ok and eqRes.value.kind == ckBool and eqRes.value.boolVal:
              isDup = true
              break
          if not isDup:
            res.add(item)
        return EvalResult(ok: true, value: cljList(res))
      return EvalResult(ok: false, error: "distinct requires a collection")

    of "slurp":
      numArgs(1)
      if args[0].kind == ckString:
        try:
          let content = readFile(args[0].strVal)
          return EvalResult(ok: true, value: cljString(content))
        except:
          return EvalResult(ok: false, error: "slurp: cannot read file: " & args[0].strVal)
      return EvalResult(ok: false, error: "slurp requires a string path")

    of "spit":
      numArgs(2)
      if args[0].kind == ckString and args[1].kind == ckString:
        try:
          writeFile(args[0].strVal, args[1].strVal)
          return EvalResult(ok: true, value: cljNil())
        except:
          return EvalResult(ok: false, error: "spit: cannot write file: " & args[0].strVal)
      return EvalResult(ok: false, error: "spit requires two string args")

    of "read-line":
      try:
        let line = stdin.readLine()
        return EvalResult(ok: true, value: cljString(line))
      except:
        return EvalResult(ok: false, error: "read-line: EOF")

    of "print":
      var parts: seq[string] = @[]
      for a in args:
        if a.kind == ckNil: parts.add("nil")
        elif a.kind == ckString: parts.add(a.strVal)
        elif a.kind == ckBool: parts.add(if a.boolVal: "true" else: "false")
        else: parts.add(cljReprLocal(a))
      stdout.write(parts.join(" "))
      return EvalResult(ok: true, value: cljNil())

    of "instance?":
      numArgs(2)
      if args[0].kind == ckKeyword and args[1].kind != ckNil:
        let typeName = case args[1].kind
          of ckBool: "boolean"
          of ckInt: "integer"
          of ckFloat: "float"
          of ckString: "string"
          of ckKeyword: "keyword"
          of ckSymbol: "symbol"
          of ckList: "list"
          of ckVector: "vector"
          of ckMap: "map"
          of ckSet: "set"
          of ckFn: "fn"
          of ckAtom: "atom"
          of ckTransient: "transient"
          of ckAgent: "agent"
          of ckNil: "nil"
        return EvalResult(ok: true, value: cljBool(args[0].kwName == typeName))
      return EvalResult(ok: true, value: cljBool(false))

    of "meta":
      numArgs(1)
      return EvalResult(ok: true, value: cljNil())

    of "with-meta":
      numArgs(2)
      return EvalResult(ok: true, value: args[0])

    of "deref":
      numArgs(1)
      if args[0].kind == ckString and agentRegistry.hasKey(args[0].strVal):
        return EvalResult(ok: true, value: agentRegistry[args[0].strVal])
      if args[0].kind == ckString and atomRegistry.hasKey(args[0].strVal):
        return EvalResult(ok: true, value: atomRegistry[args[0].strVal])
      return EvalResult(ok: true, value: args[0])

    of "atom":
      numArgs(1)
      atomCounter += 1
      let id = "atom_" & $atomCounter
      atomRegistry[id] = args[0]
      return EvalResult(ok: true, value: cljString(id))

    of "reset!":
      numArgs(2)
      if args[0].kind != ckString or not atomRegistry.hasKey(args[0].strVal):
        return EvalResult(ok: false, error: "reset! requires an atom")
      atomRegistry[args[0].strVal] = args[1]
      return EvalResult(ok: true, value: args[1])

    of "swap!":
      atLeast(2)
      if args[0].kind != ckString or not atomRegistry.hasKey(args[0].strVal):
        return EvalResult(ok: false, error: "swap! requires an atom")
      let fn = args[1]
      let currentVal = atomRegistry[args[0].strVal]
      var callItems = @[fn, currentVal]
      if args.len > 2:
        for extra in args[2..^1]:
          callItems.add(extra)
      let callRes = evalList(callItems, env)
      if not callRes.ok: return callRes
      atomRegistry[args[0].strVal] = callRes.value
      return EvalResult(ok: true, value: callRes.value)

    of "agent":
      numArgs(1)
      agentCounter += 1
      let id = "agent_" & $agentCounter
      agentRegistry[id] = args[0]
      return EvalResult(ok: true, value: cljString(id))

    of "send":
      atLeast(2)
      let agentId = args[0]
      if agentId.kind != ckString or not agentRegistry.hasKey(agentId.strVal):
        return EvalResult(ok: false, error: "send requires an agent")
      let fn = args[1]
      let fnArgs = if args.len > 2: args[2..^1] else: @[]
      let currentVal = agentRegistry[agentId.strVal]
      var callItems = @[fn, currentVal]
      callItems.add(fnArgs)
      let callRes = evalList(callItems, env)
      if not callRes.ok: return callRes
      agentRegistry[agentId.strVal] = callRes.value
      return EvalResult(ok: true, value: callRes.value)

    of "await":
      numArgs(1)
      return EvalResult(ok: true, value: cljNil())

    of "shutdown-agents":
      return EvalResult(ok: true, value: cljNil())

    of "chan":
      channelCounter += 1
      let id = "chan_" & $channelCounter
      let cap = if args.len > 0 and args[0].kind == ckInt: args[0].intVal.int else: 0
      let ch = Channel(buf: initDeque[CljVal](), capacity: cap, closed: false)
      channelRegistry[id] = ch
      return EvalResult(ok: true, value: cljString(id))

    of "put!", ">!":
      numArgs(2)
      if args[0].kind != ckString or not channelRegistry.hasKey(args[0].strVal):
        return EvalResult(ok: false, error: "put!/<! requires a channel")
      let ch = channelRegistry[args[0].strVal]
      if ch.closed:
        return EvalResult(ok: false, error: "Channel is closed")
      if ch.capacity > 0 and ch.buf.len >= ch.capacity:
        return EvalResult(ok: false, error: "Channel buffer full")
      ch.buf.addLast(args[1])
      return EvalResult(ok: true, value: cljBool(true))

    of "take!", "<!":
      numArgs(1)
      if args[0].kind != ckString or not channelRegistry.hasKey(args[0].strVal):
        return EvalResult(ok: false, error: "take!/<! requires a channel")
      let ch = channelRegistry[args[0].strVal]
      if ch.buf.len == 0:
        if ch.closed:
          return EvalResult(ok: true, value: cljNil())
        return EvalResult(ok: true, value: cljNil())
      return EvalResult(ok: true, value: ch.buf.popFirst())

    of "close!":
      numArgs(1)
      if args[0].kind != ckString or not channelRegistry.hasKey(args[0].strVal):
        return EvalResult(ok: false, error: "close! requires a channel")
      let ch = channelRegistry[args[0].strVal]
      ch.closed = true
      return EvalResult(ok: true, value: cljNil())

    of "go":
      # In synchronous interpreter, go just evaluates the body
      var lastVal: CljVal = cljNil()
      for i in 1..<items.len:
        let res = evalAst(items[i], env)
        if not res.ok: return res
        lastVal = res.value
      return EvalResult(ok: true, value: lastVal)

    of "ai/generate", "ai.generate":
      atLeast(1)
      let description = if args[0].kind == ckString: args[0].strVal else: cljReprLocal(args[0])
      if not ai_assist.hasAiConfig():
        return EvalResult(ok: false, error: "No AI API key configured. Set DEEPSEEK_API_KEY, OPENAI_API_KEY, or MIMO_API_KEY.")
      let aiRes = ai_assist.generateCode(description)
      if not aiRes.ok:
        return EvalResult(ok: false, error: aiRes.suggestion)
      return EvalResult(ok: true, value: cljString(aiRes.suggestion))

    of "ai/optimize", "ai.optimize":
      numArgs(1)
      let code = if args[0].kind == ckString: args[0].strVal else: cljReprLocal(args[0])
      if not ai_assist.hasAiConfig():
        return EvalResult(ok: false, error: "No AI API key configured.")
      let aiRes = ai_assist.optimizeCode(code)
      if not aiRes.ok:
        return EvalResult(ok: false, error: aiRes.suggestion)
      return EvalResult(ok: true, value: cljString(aiRes.suggestion))

    else:
      return EvalResult(ok: false, error: "Unknown function: " & name & " (use compile mode for full runtime)")

  # Try to call as builtin
  if fnVal.kind == ckSymbol:
    let builtinRes = evalBuiltin(fnVal.symName, args)
    if builtinRes.ok or builtinRes.error.startsWith("Unknown function"):
      return builtinRes
    return builtinRes

  return EvalResult(ok: false, error: "Cannot call: " & cljReprLocal(fnVal))

proc evalAst*(form: CljVal, env: Env): EvalResult =
  if form.isNil:
    return EvalResult(ok: true, value: cljNil())

  case form.kind
  of ckNil:
    return EvalResult(ok: true, value: cljNil())
  of ckBool, ckInt, ckFloat, ckString, ckKeyword:
    return EvalResult(ok: true, value: form)
  of ckSymbol:
    if form.symName == "nil":
      return EvalResult(ok: true, value: cljNil())
    if form.symName == "true":
      return EvalResult(ok: true, value: cljBool(true))
    if form.symName == "false":
      return EvalResult(ok: true, value: cljBool(false))
    let val = envGet(env, form.symName)
    if val != nil:
      return EvalResult(ok: true, value: val)
    # Return symbol as-is (may be a builtin function name)
    return EvalResult(ok: true, value: form)
  of ckVector:
    var items: seq[CljVal] = @[]
    for item in form.items:
      let res = evalAst(item, env)
      if not res.ok: return res
      items.add(res.value)
    return EvalResult(ok: true, value: cljVector(items))
  of ckMap:
    var keys: seq[CljVal] = @[]
    var vals: seq[CljVal] = @[]
    for i in 0..<form.mapKeys.len:
      let kRes = evalAst(form.mapKeys[i], env)
      if not kRes.ok: return kRes
      let vRes = evalAst(form.mapVals[i], env)
      if not vRes.ok: return vRes
      keys.add(kRes.value)
      vals.add(vRes.value)
    return EvalResult(ok: true, value: cljMap(keys, vals))
  of ckList:
    return evalList(form.items, env)
  of ckSet:
    var items: seq[CljVal] = @[]
    for item in form.setItems:
      let res = evalAst(item, env)
      if not res.ok: return res
      items.add(res.value)
    return EvalResult(ok: true, value: cljSet(items))
  of ckFn:
    return EvalResult(ok: true, value: form)
  of ckAtom:
    return EvalResult(ok: true, value: form)
  of ckTransient:
    return EvalResult(ok: true, value: form)
  of ckAgent:
    return EvalResult(ok: true, value: form)

proc eval*(formStr: string, env: Env): EvalResult =
  let parsed = reader.read(formStr)
  return evalAst(parsed, env)

proc evalAll*(formsStr: string, env: Env): seq[EvalResult] =
  let forms = reader.readAll(formsStr)
  for form in forms:
    result.add(evalAst(form, env))

proc newTopLevelEnv*(): Env =
  result = newEnv()
