import runtime
import strutils
import sequtils

# ---- Arithmetic ----

proc cljAdd*(args: seq[CljVal]): CljVal =
  var sum: int64 = 0
  var sumFloat: float64 = 0.0
  var isFloat = false
  for a in args:
    case a.kind
    of ckInt: sum += a.intVal
    of ckFloat:
      sumFloat += a.floatVal
      isFloat = true
    else: raise newException(CatchableError, "+ requires numbers")
  if isFloat:
    cljFloat(sum.float64 + sumFloat)
  else:
    cljInt(sum)

proc cljMul*(args: seq[CljVal]): CljVal =
  var product: int64 = 1
  var productFloat: float64 = 1.0
  var isFloat = false
  for a in args:
    case a.kind
    of ckInt: product *= a.intVal
    of ckFloat:
      productFloat *= a.floatVal
      isFloat = true
    else: raise newException(CatchableError, "* requires numbers")
  if isFloat:
    cljFloat(product.float64 * productFloat)
  else:
    cljInt(product)

proc cljSub*(args: seq[CljVal]): CljVal =
  if args.len == 0: raise newException(CatchableError, "- requires at least 1 argument")
  if args.len == 1:
    case args[0].kind
    of ckInt: return cljInt(-args[0].intVal)
    of ckFloat: return cljFloat(-args[0].floatVal)
    else: raise newException(CatchableError, "- requires numbers")
  var result: int64
  var resultF: float64
  var isFloat = false
  case args[0].kind
  of ckInt: result = args[0].intVal
  of ckFloat:
    resultF = args[0].floatVal
    isFloat = true
  else: raise newException(CatchableError, "- requires numbers")
  for i in 1..<args.len:
    case args[i].kind
    of ckInt:
      if isFloat: resultF -= args[i].intVal.float64
      else: result -= args[i].intVal
    of ckFloat:
      if not isFloat:
        resultF = result.float64 - args[i].floatVal
        isFloat = true
      else:
        resultF -= args[i].floatVal
    else: raise newException(CatchableError, "- requires numbers")
  if isFloat: cljFloat(resultF)
  else: cljInt(result)

proc cljDiv*(args: seq[CljVal]): CljVal =
  if args.len < 2: raise newException(CatchableError, "/ requires at least 2 arguments")
  var result: float64
  case args[0].kind
  of ckInt: result = args[0].intVal.float64
  of ckFloat: result = args[0].floatVal
  else: raise newException(CatchableError, "/ requires numbers")
  for i in 1..<args.len:
    case args[i].kind
    of ckInt:
      if args[i].intVal == 0: raise newException(CatchableError, "Division by zero")
      result /= args[i].intVal.float64
    of ckFloat:
      if args[i].floatVal == 0: raise newException(CatchableError, "Division by zero")
      result /= args[i].floatVal
    else: raise newException(CatchableError, "/ requires numbers")
  cljFloat(result)

proc cljInc*(v: CljVal): CljVal =
  case v.kind
  of ckInt: cljInt(v.intVal + 1)
  of ckFloat: cljFloat(v.floatVal + 1.0)
  else: raise newException(CatchableError, "inc requires a number")

proc cljDec*(v: CljVal): CljVal =
  case v.kind
  of ckInt: cljInt(v.intVal - 1)
  of ckFloat: cljFloat(v.floatVal - 1.0)
  else: raise newException(CatchableError, "dec requires a number")

proc cljMod*(a, b: CljVal): CljVal =
  if a.kind == ckInt and b.kind == ckInt:
    cljInt(a.intVal mod b.intVal)
  else:
    raise newException(CatchableError, "mod requires integers")

proc cljRem*(a, b: CljVal): CljVal =
  if a.kind == ckInt and b.kind == ckInt:
    cljInt(a.intVal rem b.intVal)
  else:
    raise newException(CatchableError, "rem requires integers")

# ---- Comparison ----

proc cljNumEq*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljBool(true)
  for i in 1..<args.len:
    let a = args[i-1]
    let b = args[i]
    if a.kind == ckInt and b.kind == ckInt:
      if a.intVal != b.intVal: return cljBool(false)
    elif a.kind == ckFloat and b.kind == ckFloat:
      if a.floatVal != b.floatVal: return cljBool(false)
    elif a.kind == ckInt and b.kind == ckFloat:
      if a.intVal.float64 != b.floatVal: return cljBool(false)
    elif a.kind == ckFloat and b.kind == ckInt:
      if a.floatVal != b.intVal.float64: return cljBool(false)
    else:
      return cljBool(false)
  cljBool(true)

proc cljLt*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljBool(true)
  for i in 1..<args.len:
    let a = args[i-1]
    let b = args[i]
    if a.kind == ckInt and b.kind == ckInt:
      if a.intVal >= b.intVal: return cljBool(false)
    elif a.kind == ckFloat and b.kind == ckFloat:
      if a.floatVal >= b.floatVal: return cljBool(false)
    else:
      return cljBool(false)
  cljBool(true)

proc cljGt*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljBool(true)
  for i in 1..<args.len:
    let a = args[i-1]
    let b = args[i]
    if a.kind == ckInt and b.kind == ckInt:
      if a.intVal <= b.intVal: return cljBool(false)
    elif a.kind == ckFloat and b.kind == ckFloat:
      if a.floatVal <= b.floatVal: return cljBool(false)
    else:
      return cljBool(false)
  cljBool(true)

proc cljLe*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljBool(true)
  for i in 1..<args.len:
    let a = args[i-1]
    let b = args[i]
    if a.kind == ckInt and b.kind == ckInt:
      if a.intVal > b.intVal: return cljBool(false)
    else:
      return cljBool(false)
  cljBool(true)

proc cljGe*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljBool(true)
  for i in 1..<args.len:
    let a = args[i-1]
    let b = args[i]
    if a.kind == ckInt and b.kind == ckInt:
      if a.intVal < b.intVal: return cljBool(false)
    else:
      return cljBool(false)
  cljBool(true)

# ---- Predicates ----

proc cljZero*(v: CljVal): CljVal =
  case v.kind
  of ckInt: cljBool(v.intVal == 0)
  of ckFloat: cljBool(v.floatVal == 0.0)
  else: cljBool(false)

proc cljPos*(v: CljVal): CljVal =
  case v.kind
  of ckInt: cljBool(v.intVal > 0)
  of ckFloat: cljBool(v.floatVal > 0.0)
  else: raise newException(CatchableError, "pos? requires a number")

proc cljNeg*(v: CljVal): CljVal =
  case v.kind
  of ckInt: cljBool(v.intVal < 0)
  of ckFloat: cljBool(v.floatVal < 0.0)
  else: raise newException(CatchableError, "neg? requires a number")

proc cljEven*(v: CljVal): CljVal =
  if v.kind == ckInt: cljBool(v.intVal mod 2 == 0)
  else: raise newException(CatchableError, "even? requires an integer")

proc cljOdd*(v: CljVal): CljVal =
  if v.kind == ckInt: cljBool(v.intVal mod 2 != 0)
  else: raise newException(CatchableError, "odd? requires an integer")

# ---- Collection operations ----

proc cljFirst*(v: CljVal): CljVal =
  if v.isNil: return cljNil()
  case v.kind
  of ckList:
    if v.listItems.len == 0: cljNil()
    else: v.listItems[0]
  of ckVector:
    if v.listItems.len == 0: cljNil()
    else: v.listItems[0]
  else: cljNil()

proc cljRest*(v: CljVal): CljVal =
  if v.isNil: return cljList(@[])
  case v.kind
  of ckList:
    if v.listItems.len <= 1: cljList(@[])
    else: cljList(v.listItems[1..^1])
  of ckVector:
    if v.listItems.len <= 1: cljList(@[])
    else: cljList(v.listItems[1..^1])
  else: cljList(@[])

proc cljNext*(v: CljVal): CljVal =
  let r = cljRest(v)
  if r.kind == ckList and r.listItems.len == 0:
    return cljNil()
  r

proc cljLast*(v: CljVal): CljVal =
  if v.isNil: return cljNil()
  case v.kind
  of ckList:
    if v.listItems.len == 0: cljNil()
    else: v.listItems[^1]
  of ckVector:
    if v.listItems.len == 0: cljNil()
    else: v.listItems[^1]
  else: cljNil()

proc cljNth*(v: CljVal, n: int): CljVal =
  case v.kind
  of ckList:
    if n < 0 or n >= v.listItems.len:
      raise newException(IndexDefect, "nth: index out of range")
    v.listItems[n]
  of ckVector:
    if n < 0 or n >= v.listItems.len:
      raise newException(IndexDefect, "nth: index out of range")
    v.listItems[n]
  else:
    raise newException(CatchableError, "nth requires a collection")

proc cljCount*(v: CljVal): int =
  if v.isNil: return 0
  case v.kind
  of ckList: v.listItems.len
  of ckVector: v.listItems.len
  of ckString: v.strVal.len
  else: 0

proc cljConj*(coll: CljVal, item: CljVal): CljVal =
  if coll.isNil:
    return cljList(@[item])
  case coll.kind
  of ckList:
    var newItems = @[item]
    newItems.add(coll.listItems)
    cljList(newItems)
  of ckVector:
    var newItems = coll.listItems
    newItems.add(item)
    cljVector(newItems)
  else:
    cljList(@[item])

proc cljCons*(item: CljVal, coll: CljVal): CljVal =
  if coll.isNil or (coll.kind == ckList and coll.listItems.len == 0):
    return cljList(@[item])
  case coll.kind
  of ckList:
    var newItems = @[item]
    newItems.add(coll.listItems)
    cljList(newItems)
  of ckVector:
    var newItems = @[item]
    newItems.add(coll.listItems)
    cljList(newItems)
  else:
    cljList(@[item])

proc cljSeq*(v: CljVal): CljVal =
  if v.isNil: return cljNil()
  case v.kind
  of ckList:
    if v.listItems.len == 0: cljNil()
    else: v
  of ckVector:
    if v.listItems.len == 0: cljNil()
    else: cljList(v.listItems)
  of ckString:
    if v.strVal.len == 0: cljNil()
    else:
      var chars: seq[CljVal] = @[]
      for c in v.strVal:
        chars.add(cljString($c))
      cljList(chars)
  else: cljNil()

proc cljVec*(v: CljVal): CljVal =
  if v.isNil: return cljVector(@[])
  case v.kind
  of ckList: cljVector(v.listItems)
  of ckVector: v
  else: cljVector(@[v])

proc cljEmpty*(v: CljVal): CljVal =
  cljBool(cljCount(v) == 0)

# ---- Higher-order functions ----

proc cljMap*(f: proc(args: seq[CljVal]): CljVal, coll: seq[CljVal]): seq[CljVal] =
  result = @[]
  for item in coll:
    result.add(f(@[item]))

proc cljFilter*(f: proc(args: seq[CljVal]): CljVal, coll: seq[CljVal]): seq[CljVal] =
  result = @[]
  for item in coll:
    let r = f(@[item])
    if r.kind == ckBool and r.boolVal:
      result.add(item)

proc cljReduce*(f: proc(args: seq[CljVal]): CljVal, init: CljVal, coll: seq[CljVal]): CljVal =
  result = init
  for item in coll:
    result = f(@[result, item])

proc cljMapv*(f: proc(args: seq[CljVal]): CljVal, coll: seq[CljVal]): CljVal =
  cljList(cljMap(f, coll))

proc cljSome*(f: proc(args: seq[CljVal]): CljVal, coll: seq[CljVal]): CljVal =
  for item in coll:
    let r = f(@[item])
    if r.kind != ckBool or r.boolVal:
      return r
  cljNil()

proc cljEvery*(f: proc(args: seq[CljVal]): CljVal, coll: seq[CljVal]): CljVal =
  for item in coll:
    let r = f(@[item])
    if r.kind == ckBool and not r.boolVal:
      return cljBool(false)
  cljBool(true)

proc cljNot*(v: CljVal): CljVal =
  if v.kind == ckBool and not v.boolVal:
    cljBool(true)
  else:
    cljBool(false)

proc cljApply*(f: proc(args: seq[CljVal]): CljVal, args: seq[CljVal]): CljVal =
  f(args)

proc cljComp*(fns: seq[proc(args: seq[CljVal]): CljVal]): proc(args: seq[CljVal]): CljVal =
  proc(args: seq[CljVal]): CljVal =
    result = args
    for i in countdown(fns.len - 1, 0):
      result = fns[i](@[result])

proc cljPartial*(f: proc(args: seq[CljVal]): CljVal, partialArgs: seq[CljVal]): proc(args: seq[CljVal]): CljVal =
  proc(args: seq[CljVal]): CljVal =
    var allArgs = partialArgs
    allArgs.add(args)
    f(allArgs)

# ---- I/O ----

proc cljPrintln*(args: seq[CljVal]): CljVal =
  var parts: seq[string] = @[]
  for a in args:
    parts.add(cljStr(a))
  echo parts.join(" ")
  cljNil()

proc cljPrn*(args: seq[CljVal]): CljVal =
  var parts: seq[string] = @[]
  for a in args:
    parts.add(cljRepr(a))
  echo parts.join(" ")
  cljNil()

proc cljStr*(args: seq[CljVal]): CljVal =
  var s = ""
  for a in args:
    s.add(cljStr(a))
  cljString(s)

proc cljPrStr*(args: seq[CljVal]): CljVal =
  var parts: seq[string] = @[]
  for a in args:
    parts.add(cljRepr(a))
  cljString(parts.join(" "))

# ---- Misc ----

proc cljIdentity*(args: seq[CljVal]): CljVal =
  if args.len == 0: cljNil()
  else: args[0]

proc cljConstantly*(v: CljVal): proc(args: seq[CljVal]): CljVal =
  proc(args: seq[CljVal]): CljVal = v

proc cljType*(v: CljVal): CljVal =
  if v.isNil: return cljKeyword("nil")
  case v.kind
  of ckBool: cljKeyword("boolean")
  of ckInt: cljKeyword("integer")
  of ckFloat: cljKeyword("float")
  of ckString: cljKeyword("string")
  of ckKeyword: cljKeyword("keyword")
  of ckSymbol: cljKeyword("symbol")
  of ckList: cljKeyword("list")
  of ckVector: cljKeyword("vector")
  of ckMap: cljKeyword("map")
  of ckSet: cljKeyword("set")
  of ckFn: cljKeyword("function")
  of ckAtom: cljKeyword("atom")
  of ckTransient: cljKeyword("transient")
  of ckAgent: cljKeyword("agent")

proc cljMinMax*(args: seq[CljVal], isMin: bool): CljVal =
  if args.len == 0: raise newException(CatchableError, "min/max requires at least 1 argument")
  result = args[0]
  for i in 1..<args.len:
    let a = args[i]
    if a.kind == ckInt and result.kind == ckInt:
      if isMin:
        if a.intVal < result.intVal: result = a
      else:
        if a.intVal > result.intVal: result = a
    elif a.kind == ckFloat and result.kind == ckFloat:
      if isMin:
        if a.floatVal < result.floatVal: result = a
      else:
        if a.floatVal > result.floatVal: result = a
    elif a.kind == ckInt and result.kind == ckFloat:
      let af = a.intVal.float64
      if isMin:
        if af < result.floatVal: result = a
      else:
        if af > result.floatVal: result = a
    elif a.kind == ckFloat and result.kind == ckInt:
      let rf = result.intVal.float64
      if isMin:
        if a.floatVal < rf: result = a
      else:
        if a.floatVal > rf: result = a

proc cljAbs*(v: CljVal): CljVal =
  case v.kind
  of ckInt: cljInt(abs(v.intVal))
  of ckFloat: cljFloat(abs(v.floatVal))
  else: raise newException(CatchableError, "abs requires a number")

proc cljQuot*(a, b: CljVal): CljVal =
  if a.kind == ckInt and b.kind == ckInt:
    cljInt(a.intVal div b.intVal)
  else:
    raise newException(CatchableError, "quot requires integers")
