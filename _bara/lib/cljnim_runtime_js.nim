# Minimal Bara Lang runtime for JavaScript target
# No C FFI, no threads, no processes — just plain Nim/JS

type
  CljKind* = enum
    ckNil, ckBool, ckInt, ckFloat, ckString, ckKeyword, ckSymbol,
    ckList, ckVector, ckMap, ckSet, ckFn, ckAtom, ckTransient, ckAgent

  CljVal* = object
    case kind*: CljKind
    of ckNil: discard
    of ckBool: boolVal*: bool
    of ckInt: intVal*: int64
    of ckFloat: floatVal*: float64
    of ckString: strVal*: string
    of ckKeyword: kwName*: string
    of ckSymbol: symName*: string
    of ckList, ckVector: items*: seq[CljVal]
    of ckMap:
      mapKeys*: seq[CljVal]
      mapVals*: seq[CljVal]
    of ckSet: setItems*: seq[CljVal]
    of ckFn: fnBody*: seq[CljVal]
    of ckAtom: atomVal*: CljVal
    of ckTransient: transVec*: seq[CljVal]
    of ckAgent: agentVal*: CljVal

proc cljNil*(): CljVal = CljVal(kind: ckNil)
proc cljBool*(v: bool): CljVal = CljVal(kind: ckBool, boolVal: v)
proc cljInt*(v: int64): CljVal = CljVal(kind: ckInt, intVal: v)
proc cljFloat*(v: float64): CljVal = CljVal(kind: ckFloat, floatVal: v)
proc cljString*(v: string): CljVal = CljVal(kind: ckString, strVal: v)
proc cljKeyword*(v: string): CljVal = CljVal(kind: ckKeyword, kwName: v)
proc cljSymbol*(v: string): CljVal = CljVal(kind: ckSymbol, symName: v)
proc cljList*(items: seq[CljVal]): CljVal = CljVal(kind: ckList, items: items)
proc cljVector*(items: seq[CljVal]): CljVal = CljVal(kind: ckVector, items: items)
proc cljMap*(keys: seq[CljVal], vals: seq[CljVal]): CljVal =
  CljVal(kind: ckMap, mapKeys: keys, mapVals: vals)

# ---- Arithmetic ----
proc cljAdd*(args: seq[CljVal]): CljVal =
  var sum: int64 = 0
  var hasFloat = false
  var fsum: float64 = 0.0
  for a in args:
    if a.kind == ckInt: sum += a.intVal
    elif a.kind == ckFloat: hasFloat = true; fsum += a.floatVal
  if hasFloat: return cljFloat(fsum + sum.float64)
  return cljInt(sum)

proc cljMul*(args: seq[CljVal]): CljVal =
  var product: int64 = 1
  var hasFloat = false
  var fprod: float64 = 1.0
  for a in args:
    if a.kind == ckInt: product *= a.intVal
    elif a.kind == ckFloat: hasFloat = true; fprod *= a.floatVal
  if hasFloat: return cljFloat(fprod * product.float64)
  return cljInt(product)

proc cljSub*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljInt(0)
  var sum = args[0].intVal.float64
  for i in 1..<args.len:
    sum -= args[i].intVal.float64
  return cljInt(sum.int64)

# ---- String ops ----
proc cljStrConcat*(args: seq[CljVal]): CljVal =
  var s = ""
  for a in args:
    case a.kind
    of ckString: s.add(a.strVal)
    of ckInt: s.add($a.intVal)
    of ckFloat: s.add($a.floatVal)
    of ckBool: s.add($a.boolVal)
    of ckKeyword: s.add(":" & a.kwName)
    of ckNil: s.add("nil")
    else: discard
  return cljString(s)

# ---- Predicates ----
proc cljIsTruthy*(v: CljVal): bool =
  if v.kind == ckNil: return false
  if v.kind == ckBool: return v.boolVal
  return true

proc cljNumEq*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljBool(true)
  for i in 1..<args.len:
    let a = args[i-1]
    let b = args[i]
    var eq = false
    if a.kind == ckInt and b.kind == ckInt: eq = a.intVal == b.intVal
    elif a.kind == ckFloat and b.kind == ckFloat: eq = a.floatVal == b.floatVal
    elif a.kind == ckInt and b.kind == ckFloat: eq = a.intVal.float64 == b.floatVal
    elif a.kind == ckFloat and b.kind == ckInt: eq = a.floatVal == b.intVal.float64
    else: return cljBool(false)
    if not eq: return cljBool(false)
  return cljBool(true)

# ---- Equality ----
proc cljEq*(a, b: CljVal): bool =
  if a.kind != b.kind: return false
  case a.kind
  of ckNil: return true
  of ckBool: return a.boolVal == b.boolVal
  of ckInt: return a.intVal == b.intVal
  of ckFloat: return a.floatVal == b.floatVal
  of ckString: return a.strVal == b.strVal
  of ckKeyword: return a.kwName == b.kwName
  of ckSymbol: return a.symName == b.symName
  else: return false
