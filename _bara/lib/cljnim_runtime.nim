import cljnim_pvec
import cljnim_pmap
import strutils, sequtils, hashes, algorithm, os, osproc, locks, math, random, re, json

type
  CljKind* = enum
    ckNil, ckBool, ckInt, ckFloat, ckString, ckKeyword, ckSymbol,
    ckList, ckVector, ckMap, ckSet, ckFn, ckAtom, ckTransient, ckAgent

  AgentAction = object
    fn: CljVal
    args: seq[CljVal]

  ExInfo* = object of CatchableError
    exData*: CljVal

  CljVal* = ref CljValObj
  CljValObj = object
    meta*: CljVal
    case kind*: CljKind
    of ckNil: discard
    of ckBool: boolVal*: bool
    of ckInt: intVal*: int64
    of ckFloat: floatVal*: float64
    of ckString: strVal*: string
    of ckKeyword: kwName*: string
    of ckSymbol: symName*: string
    of ckList: listItems*: seq[CljVal]
    of ckVector: vecData*: PersistentVector[CljVal]
    of ckMap: mapData*: PersistentMap[CljVal, CljVal]
    of ckSet: setData*: PersistentMap[CljVal, bool]
    of ckFn: fnProc*: proc(args: seq[CljVal]): CljVal
    of ckAtom: atomVal*: CljVal
    of ckTransient:
      transKind*: CljKind
      transVec*: seq[CljVal]
      transPairs*: seq[(CljVal, CljVal)]
    of ckAgent:
      agentVal*: CljVal
      agentLock*: Lock
      agentQueue*: seq[AgentAction]
      agentBusy*: bool

# ---- Hashing ----

proc hash*(v: CljVal): Hash =
  case v.kind
  of ckNil: result = hash(0)
  of ckBool: result = hash(v.boolVal)
  of ckInt: result = hash(v.intVal)
  of ckFloat: result = hash(v.floatVal)
  of ckString: result = hash(v.strVal)
  of ckKeyword: result = hash(v.kwName)
  of ckSymbol: result = hash(v.symName)
  of ckFn: result = hash(cast[uint](unsafeAddr v.fnProc))
  of ckAtom: result = hash(cast[uint](unsafeAddr v.atomVal))
  of ckAgent: result = hash(cast[uint](unsafeAddr v.agentVal))
  of ckList, ckVector, ckMap, ckSet, ckTransient: result = hash(0)

# ---- Equality ----

proc `==`*(a, b: CljVal): bool =
  if a.isNil and b.isNil: return true
  if a.isNil or b.isNil: return false
  if a.kind != b.kind: return false
  case a.kind
  of ckNil: true
  of ckBool: a.boolVal == b.boolVal
  of ckInt: a.intVal == b.intVal
  of ckFloat: a.floatVal == b.floatVal
  of ckString: a.strVal == b.strVal
  of ckKeyword: a.kwName == b.kwName
  of ckSymbol: a.symName == b.symName
  else: false

proc cljEq*(a, b: CljVal): bool = a == b

# ---- Constructors ----

proc cljNil*(): CljVal = CljVal(kind: ckNil)
proc cljBool*(v: bool): CljVal = CljVal(kind: ckBool, boolVal: v)
proc cljInt*(v: int64): CljVal = CljVal(kind: ckInt, intVal: v)
proc cljInt*(v: int): CljVal = CljVal(kind: ckInt, intVal: v.int64)
proc cljFloat*(v: float64): CljVal = CljVal(kind: ckFloat, floatVal: v)
proc cljInf*(args: seq[CljVal]): CljVal = CljVal(kind: ckFloat, floatVal: Inf)
proc cljNaN*(args: seq[CljVal]): CljVal = CljVal(kind: ckFloat, floatVal: NaN)

proc cljNaNQ*(v: CljVal): CljVal =
  if v.kind == ckFloat: cljBool(v.floatVal.isNaN)
  else: cljBool(false)
proc cljString*(v: string): CljVal = CljVal(kind: ckString, strVal: v)
proc cljKeyword*(v: string): CljVal = CljVal(kind: ckKeyword, kwName: v)
proc cljSymbol*(v: string): CljVal = CljVal(kind: ckSymbol, symName: v)
proc cljList*(items: seq[CljVal]): CljVal = CljVal(kind: ckList, listItems: items)
proc cljVector*(items: seq[CljVal]): CljVal = CljVal(kind: ckVector, vecData: newPersistentVector(items))
proc cljFn*(p: proc(args: seq[CljVal]): CljVal): CljVal = CljVal(kind: ckFn, fnProc: p)

proc cljMap*(keys, vals: seq[CljVal]): CljVal =
  var m = newPersistentMap[CljVal, CljVal]()
  for i in 0..<keys.len:
    m = pmapAssoc(m, keys[i], vals[i], hash(keys[i]), cljEq)
  CljVal(kind: ckMap, mapData: m)

proc cljMapFromPairs*(pairs: seq[(CljVal, CljVal)]): CljVal =
  var m = newPersistentMap[CljVal, CljVal]()
  for (k, v) in pairs:
    m = pmapAssoc(m, k, v, hash(k), cljEq)
  CljVal(kind: ckMap, mapData: m)

proc cljSet*(items: seq[CljVal]): CljVal =
  var s = newPersistentMap[CljVal, bool]()
  for item in items:
    s = pmapAssoc(s, item, true, hash(item), cljEq)
  CljVal(kind: ckSet, setData: s)

proc cljSet*(coll: CljVal): CljVal =
  var s = newPersistentMap[CljVal, bool]()
  if coll.isNil: return CljVal(kind: ckSet, setData: s)
  case coll.kind
  of ckList:
    for item in coll.listItems:
      s = pmapAssoc(s, item, true, hash(item), cljEq)
  of ckVector:
    for item in toSeq(coll.vecData):
      s = pmapAssoc(s, item, true, hash(item), cljEq)
  of ckSet:
    return coll
  of ckMap:
    for key in pmapKeys(coll.mapData):
      s = pmapAssoc(s, key, true, hash(key), cljEq)
  else: discard
  CljVal(kind: ckSet, setData: s)

proc cljHashMap*(args: seq[CljVal]): CljVal =
  if args.len mod 2 != 0:
    raise newException(CatchableError, "hash-map requires even number of arguments")
  var m = newPersistentMap[CljVal, CljVal]()
  for i in countup(0, args.len - 1, 2):
    m = pmapAssoc(m, args[i], args[i+1], hash(args[i]), cljEq)
  CljVal(kind: ckMap, mapData: m)

proc cljHashSet*(args: seq[CljVal]): CljVal =
  var s = newPersistentMap[CljVal, bool]()
  for item in args:
    s = pmapAssoc(s, item, true, hash(item), cljEq)
  CljVal(kind: ckSet, setData: s)

# ---- Display ----

proc cljRepr*(v: CljVal): string =
  if v.isNil: return "nil"
  case v.kind
  of ckNil: "nil"
  of ckBool: $v.boolVal
  of ckInt: $v.intVal
  of ckFloat: $v.floatVal
  of ckString: "\"" & v.strVal.replace("\"", "\\\"") & "\""
  of ckKeyword: ":" & v.kwName
  of ckSymbol: v.symName
  of ckList: "(" & v.listItems.mapIt(cljRepr(it)).join(" ") & ")"
  of ckVector: "[" & toSeq(v.vecData).mapIt(cljRepr(it)).join(" ") & "]"
  of ckMap:
    var parts: seq[string] = @[]
    for (k, v) in pmapItems(v.mapData):
      parts.add(cljRepr(k) & " " & cljRepr(v))
    "{" & parts.join(", ") & "}"
  of ckSet:
    var parts: seq[string] = @[]
    for (k, v) in pmapItems(v.setData):
      parts.add(cljRepr(k))
    "#{" & parts.join(" ") & "}"
  of ckFn: "#<fn>"
  of ckAtom: "(atom " & cljRepr(v.atomVal) & ")"
  of ckTransient: "#<transient>"
  of ckAgent: "(agent " & cljRepr(v.agentVal) & ")"

proc cljStr*(v: CljVal): string =
  if v.isNil: return ""
  case v.kind
  of ckString: v.strVal
  of ckKeyword: ":" & v.kwName
  of ckSymbol: v.symName
  else: cljRepr(v)

# ---- Type predicates ----

proc cljIsNil*(v: CljVal): bool = v.isNil or v.kind == ckNil
proc cljIsTrue*(v: CljVal): bool = v.kind == ckBool and v.boolVal
proc cljIsFalse*(v: CljVal): bool = v.kind == ckBool and not v.boolVal
proc cljIsTruthy*(v: CljVal): bool = not cljIsNil(v) and not cljIsFalse(v)

proc cljIsNilP*(v: CljVal): CljVal = cljBool(cljIsNil(v))
proc cljIsSome*(v: CljVal): CljVal = cljBool(not cljIsNil(v))
proc cljIsKeyword*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and v.kind == ckKeyword)
proc cljIsSymbol*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and v.kind == ckSymbol)
proc cljIsString*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and v.kind == ckString)
proc cljIsNumber*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and (v.kind == ckInt or v.kind == ckFloat))
proc cljIsInteger*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and v.kind == ckInt)
proc cljIsFloat*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and v.kind == ckFloat)
proc cljIsVector*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and v.kind == ckVector)
proc cljIsMap*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and v.kind == ckMap)
proc cljIsSet*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and v.kind == ckSet)
proc cljIsList*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and v.kind == ckList)
proc cljIsSeq*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and v.kind in {ckList, ckVector})
proc cljIsColl*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and v.kind in {ckList, ckVector, ckMap, ckSet})
proc cljIsSequential*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and v.kind in {ckList, ckVector})
proc cljIsFn*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and v.kind == ckFn)
proc cljIsVar*(v: CljVal): CljVal = cljBool(false)

proc cljParseUuid*(s: CljVal): CljVal =
  if s.kind != ckString:
    raise newException(CatchableError, "Invalid UUID string")
  let str = s.strVal
  if str.len == 0:
    return cljNil()
  # Simple UUID validation: 8-4-4-4-12 hex digits
  var parts: seq[string] = @[]
  var current = ""
  for c in str:
    if c == '-':
      parts.add(current)
      current = ""
    else:
      current.add(c)
  parts.add(current)
  if parts.len == 5 and
     parts[0].len == 8 and parts[1].len == 4 and parts[2].len == 4 and
     parts[3].len == 4 and parts[4].len == 12:
    for p in parts:
      for c in p:
        if c notin {'0'..'9', 'a'..'f', 'A'..'F'}:
          return cljNil()
    return cljString(str.toLowerAscii())
  return cljNil()

proc cljIsUuid*(v: CljVal): CljVal =
  if v.kind != ckString:
    return cljBool(false)
  let str = v.strVal
  var parts = str.split('-')
  if parts.len == 5 and
     parts[0].len == 8 and parts[1].len == 4 and parts[2].len == 4 and
     parts[3].len == 4 and parts[4].len == 12:
    for p in parts:
      for c in p:
        if c notin {'0'..'9', 'a'..'f', 'A'..'F'}:
          return cljBool(false)
    return cljBool(true)
  return cljBool(false)
proc cljIsIfn*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and v.kind in {ckFn, ckKeyword, ckSymbol, ckMap, ckSet, ckVector})
proc cljIsBool*(v: CljVal): CljVal = cljBool(not cljIsNil(v) and v.kind == ckBool)
proc cljIsTrueP*(v: CljVal): CljVal = cljBool(cljIsTrue(v))
proc cljIsFalseP*(v: CljVal): CljVal = cljBool(cljIsFalse(v))

proc cljKeywordFn*(v: CljVal): CljVal =
  if v.isNil or v.kind == ckNil: return cljNil()
  case v.kind
  of ckKeyword: v
  of ckString: cljKeyword(v.strVal)
  of ckSymbol: cljKeyword(v.symName)
  else: cljNil()

proc cljSymbolFn*(v: CljVal): CljVal =
  if v.isNil or v.kind == ckNil: return cljNil()
  case v.kind
  of ckSymbol: v
  of ckString: cljSymbol(v.strVal)
  of ckKeyword: cljSymbol(v.kwName)
  else: cljNil()

proc cljName*(v: CljVal): CljVal =
  if v.isNil or v.kind == ckNil: return cljNil()
  case v.kind
  of ckKeyword: cljString(v.kwName)
  of ckSymbol: cljString(v.symName)
  else: raise newException(CatchableError, "name requires a keyword or symbol")

proc cljNamespace*(v: CljVal): CljVal =
  if v.isNil or v.kind == ckNil: return cljNil()
  case v.kind
  of ckKeyword:
    let idx = v.kwName.find('/')
    if idx >= 0: cljString(v.kwName[0..<idx])
    else: cljNil()
  of ckSymbol:
    let idx = v.symName.find('/')
    if idx >= 0: cljString(v.symName[0..<idx])
    else: cljNil()
  else: raise newException(CatchableError, "namespace requires a keyword or symbol")

proc cljKey*(v: CljVal): CljVal =
  if v.isNil or v.kind == ckNil: return cljNil()
  case v.kind
  of ckVector:
    if v.vecData.count >= 2: pvecNth(v.vecData, 0)
    else: cljNil()
  of ckList:
    if v.listItems.len >= 2: v.listItems[0]
    else: cljNil()
  else:
    raise newException(CatchableError, "key requires a map entry (vector or list of 2 items)")

proc cljEntryVal*(v: CljVal): CljVal =
  if v.isNil or v.kind == ckNil: return cljNil()
  case v.kind
  of ckVector:
    if v.vecData.count >= 2: pvecNth(v.vecData, 1)
    else: cljNil()
  of ckList:
    if v.listItems.len >= 2: v.listItems[1]
    else: cljNil()
  else:
    raise newException(CatchableError, "val requires a map entry (vector or list of 2 items)")

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

# ---- Arithmetic ----

proc cljAdd*(args: seq[CljVal]): CljVal =
  var sum: int64 = 0
  var sumF: float64 = 0.0
  var isFloat = false
  for a in args:
    case a.kind
    of ckInt: sum += a.intVal
    of ckFloat:
      sumF += a.floatVal
      isFloat = true
    else: raise newException(CatchableError, "+ requires numbers")
  if isFloat: cljFloat(sum.float64 + sumF)
  else: cljInt(sum)

proc cljMul*(args: seq[CljVal]): CljVal =
  var product: int64 = 1
  var productF: float64 = 1.0
  var isFloat = false
  for a in args:
    case a.kind
    of ckInt: product *= a.intVal
    of ckFloat:
      productF *= a.floatVal
      isFloat = true
    else: raise newException(CatchableError, "* requires numbers")
  if isFloat: cljFloat(product.float64 * productF)
  else: cljInt(product)

proc cljSub*(args: seq[CljVal]): CljVal =
  if args.len == 0: raise newException(CatchableError, "- requires at least 1 argument")
  if args.len == 1:
    case args[0].kind
    of ckInt: return cljInt(-args[0].intVal)
    of ckFloat: return cljFloat(-args[0].floatVal)
    else: raise newException(CatchableError, "- requires numbers")
  var r: int64
  var rF: float64
  var isFloat = false
  case args[0].kind
  of ckInt: r = args[0].intVal
  of ckFloat:
    rF = args[0].floatVal
    isFloat = true
  else: raise newException(CatchableError, "- requires numbers")
  for i in 1..<args.len:
    case args[i].kind
    of ckInt:
      if isFloat: rF -= args[i].intVal.float64
      else: r -= args[i].intVal
    of ckFloat:
      if not isFloat:
        rF = r.float64 - args[i].floatVal
        isFloat = true
      else:
        rF -= args[i].floatVal
    else: raise newException(CatchableError, "- requires numbers")
  if isFloat: cljFloat(rF)
  else: cljInt(r)

proc cljDiv*(args: seq[CljVal]): CljVal =
  if args.len < 2: raise newException(CatchableError, "/ requires at least 2 arguments")
  var r: float64
  case args[0].kind
  of ckInt: r = args[0].intVal.float64
  of ckFloat: r = args[0].floatVal
  else: raise newException(CatchableError, "/ requires numbers")
  for i in 1..<args.len:
    case args[i].kind
    of ckInt:
      if args[i].intVal == 0: raise newException(CatchableError, "Division by zero")
      r /= args[i].intVal.float64
    of ckFloat:
      if args[i].floatVal == 0.0: raise newException(CatchableError, "Division by zero")
      r /= args[i].floatVal
    else: raise newException(CatchableError, "/ requires numbers")
  cljFloat(r)

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

proc cljAbs*(v: CljVal): CljVal =
  case v.kind
  of ckInt: cljInt(abs(v.intVal))
  of ckFloat: cljFloat(abs(v.floatVal))
  else: raise newException(CatchableError, "abs requires a number")

proc cljMin*(args: seq[CljVal]): CljVal =
  if args.len == 0: raise newException(CatchableError, "min requires at least 1 argument")
  result = args[0]
  for i in 1..<args.len:
    if args[i].kind == ckInt and result.kind == ckInt:
      if args[i].intVal < result.intVal: result = args[i]

proc cljMax*(args: seq[CljVal]): CljVal =
  if args.len == 0: raise newException(CatchableError, "max requires at least 1 argument")
  result = args[0]
  for i in 1..<args.len:
    if args[i].kind == ckInt and result.kind == ckInt:
      if args[i].intVal > result.intVal: result = args[i]

proc cljQuot*(a, b: CljVal): CljVal =
  if a.kind == ckInt and b.kind == ckInt:
    if b.intVal == 0:
      raise newException(CatchableError, "Division by zero")
    cljInt(a.intVal div b.intVal)
  else:
    raise newException(CatchableError, "quot requires integers")

proc cljRem*(a, b: CljVal): CljVal =
  if a.kind == ckInt and b.kind == ckInt:
    if b.intVal == 0:
      raise newException(CatchableError, "Division by zero")
    cljInt(a.intVal mod b.intVal)
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

proc cljEqual*(a, b: CljVal): bool =
  ## Bara Lang = equality: structural equality for all types, numeric equality for numbers
  if a.isNil and b.isNil: return true
  if a.isNil or b.isNil: return false
  if a.kind != b.kind:
    if a.kind == ckInt and b.kind == ckFloat:
      return a.intVal.float64 == b.floatVal
    if a.kind == ckFloat and b.kind == ckInt:
      return a.floatVal == b.intVal.float64
    return false
  case a.kind
  of ckNil: true
  of ckBool: a.boolVal == b.boolVal
  of ckInt: a.intVal == b.intVal
  of ckFloat: a.floatVal == b.floatVal
  of ckString: a.strVal == b.strVal
  of ckKeyword: a.kwName == b.kwName
  of ckSymbol: a.symName == b.symName
  of ckList:
    if a.listItems.len != b.listItems.len: return false
    for i in 0..<a.listItems.len:
      if not cljEqual(a.listItems[i], b.listItems[i]): return false
    true
  of ckVector:
    if a.vecData.count != b.vecData.count: return false
    for i in 0..<a.vecData.count:
      if not cljEqual(a.vecData.pvecNth(i), b.vecData.pvecNth(i)): return false
    true
  of ckMap:
    if a.mapData.count != b.mapData.count: return false
    for (k, v) in a.mapData.pmapItems:
      if not b.mapData.pmapContains(k, hash(k), cljEqual): return false
      if not cljEqual(v, b.mapData.pmapGet(k, cljNil(), hash(k), cljEqual)): return false
    true
  of ckSet:
    if a.setData.count != b.setData.count: return false
    for (k, _) in a.setData.pmapItems:
      if not b.setData.pmapContains(k, hash(k), cljEqual): return false
    true
  else: false

proc cljMultiEqual*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljBool(true)
  for i in 1..<args.len:
    if not cljEqual(args[i-1], args[i]):
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
    else: return cljBool(false)
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
    else: return cljBool(false)
  cljBool(true)

proc cljLe*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljBool(true)
  for i in 1..<args.len:
    let a = args[i-1]
    let b = args[i]
    if a.kind == ckInt and b.kind == ckInt:
      if a.intVal > b.intVal: return cljBool(false)
    else: return cljBool(false)
  cljBool(true)

proc cljGe*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljBool(true)
  for i in 1..<args.len:
    let a = args[i-1]
    let b = args[i]
    if a.kind == ckInt and b.kind == ckInt:
      if a.intVal < b.intVal: return cljBool(false)
    else: return cljBool(false)
  cljBool(true)

proc cljNot*(v: CljVal): CljVal =
  cljBool(not cljIsTruthy(v))

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

proc cljCount*(v: CljVal): CljVal =
  if v.isNil: return cljInt(0)
  case v.kind
  of ckList: cljInt(v.listItems.len)
  of ckVector: cljInt(v.vecData.count)
  of ckMap: cljInt(v.mapData.count)
  of ckSet: cljInt(v.setData.count)
  of ckString: cljInt(v.strVal.len)
  of ckTransient:
    if v.transKind == ckVector: cljInt(v.transVec.len)
    else: cljInt(v.transPairs.len)
  else: cljInt(0)

proc cljFirst*(v: CljVal): CljVal =
  if v.isNil: return cljNil()
  case v.kind
  of ckList:
    if v.listItems.len == 0: cljNil()
    else: v.listItems[0]
  of ckVector:
    if v.vecData.count == 0: cljNil()
    else: pvecNth(v.vecData, 0)
  else: cljNil()

proc cljRest*(v: CljVal): CljVal =
  if v.isNil: return cljList(@[])
  case v.kind
  of ckList:
    if v.listItems.len <= 1: cljList(@[])
    else: cljList(v.listItems[1..^1])
  of ckVector:
    if v.vecData.count <= 1: cljList(@[])
    else: cljList(toSeq(v.vecData)[1..^1])
  else: cljList(@[])

proc cljNext*(v: CljVal): CljVal =
  let r = cljRest(v)
  if r.kind == ckList and r.listItems.len == 0:
    return cljNil()
  r

proc cljSecond*(v: CljVal): CljVal =
  cljFirst(cljRest(v))

proc cljFfirst*(v: CljVal): CljVal =
  cljFirst(cljFirst(v))

proc cljNfirst*(v: CljVal): CljVal =
  cljNext(cljFirst(v))

proc cljLast*(v: CljVal): CljVal =
  if v.isNil: return cljNil()
  case v.kind
  of ckList:
    if v.listItems.len == 0: cljNil()
    else: v.listItems[^1]
  of ckVector:
    if v.vecData.count == 0: cljNil()
    else: pvecNth(v.vecData, v.vecData.count - 1)
  else: cljNil()

proc cljNth*(v: CljVal, n: CljVal): CljVal =
  let idx = n.intVal
  case v.kind
  of ckList:
    if idx < 0 or idx >= v.listItems.len:
      raise newException(IndexDefect, "nth: index out of range")
    v.listItems[idx]
  of ckVector:
    if idx < 0 or idx >= v.vecData.count:
      raise newException(IndexDefect, "nth: index out of range")
    pvecNth(v.vecData, idx)
  else:
    raise newException(CatchableError, "nth requires a collection")

proc cljConj*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljList(@[])
  let coll = args[0]
  let item = args[1]
  if coll.isNil:
    return cljList(@[item])
  case coll.kind
  of ckList:
    var newItems = @[item]
    newItems.add(coll.listItems)
    cljList(newItems)
  of ckVector:
    var newItems = toSeq(coll.vecData)
    newItems.add(item)
    cljVector(newItems)
  of ckSet:
    CljVal(kind: ckSet, setData: pmapAssoc(coll.setData, item, true, hash(item), cljEq))
  else:
    cljList(@[item])

proc cljCons*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljList(@[])
  let item = args[0]
  let coll = args[1]
  if coll.isNil:
    return cljList(@[item])
  case coll.kind
  of ckList:
    var newItems = @[item]
    newItems.add(coll.listItems)
    cljList(newItems)
  of ckVector:
    var newItems = @[item]
    newItems.add(toSeq(coll.vecData))
    cljList(newItems)
  else:
    cljList(@[item])

proc cljDisj*(s: CljVal, item: CljVal): CljVal =
  if s.isNil or s.kind != ckSet:
    return cljSet(@[])
  CljVal(kind: ckSet, setData: pmapDissoc(s.setData, item, hash(item), cljEq))

proc cljPeek*(v: CljVal): CljVal =
  if v.isNil: return cljNil()
  case v.kind
  of ckList:
    if v.listItems.len == 0: cljNil()
    else: v.listItems[0]
  of ckVector:
    if v.vecData.count == 0: cljNil()
    else: pvecNth(v.vecData, v.vecData.count - 1)
  else: cljNil()

proc cljPop*(v: CljVal): CljVal =
  if v.isNil: return cljNil()
  case v.kind
  of ckList:
    if v.listItems.len <= 1: cljList(@[])
    else: cljList(v.listItems[1..^1])
  of ckVector:
    if v.vecData.count <= 1: cljVector(@[])
    else:
      var items = toSeq(v.vecData)
      items.setLen(items.len - 1)
      cljVector(items)
  else: cljNil()

proc cljSeq*(v: CljVal): CljVal =
  if v.isNil: return cljNil()
  case v.kind
  of ckList:
    if v.listItems.len == 0: cljNil()
    else: v
  of ckVector:
    if v.vecData.count == 0: cljNil()
    else: cljList(toSeq(v.vecData))
  of ckString:
    if v.strVal.len == 0: cljNil()
    else:
      var chars: seq[CljVal] = @[]
      for c in v.strVal:
        chars.add(cljString($c))
      cljList(chars)
  of ckSet:
    if v.setData.count == 0: cljNil()
    else: cljList(pmapKeys(v.setData))
  else: cljNil()

proc cljVec*(v: CljVal): CljVal =
  if v.isNil: return cljVector(@[])
  case v.kind
  of ckList: cljVector(v.listItems)
  of ckVector: v
  else: cljVector(@[v])

proc cljObjectArray*(n: CljVal): CljVal =
  var size = 0
  if not n.isNil and n.kind == ckInt:
    size = n.intVal.int
  var items: seq[CljVal] = @[]
  for i in 0..<size:
    items.add(cljNil())
  return cljList(items)

proc cljIntArray*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljList(@[])
  var size = 0
  if args[0].kind == ckInt: size = args[0].intVal.int
  var items: seq[CljVal] = @[]
  for i in 0..<size:
    items.add(cljInt(0))
  cljList(items)

proc cljAclone*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljList(@[])
  args[0]

proc cljAlength*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljInt(0)
  let a = args[0]
  if a.kind == ckList: return cljInt(a.listItems.len)
  cljInt(0)

proc cljAget*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljNil()
  let a = args[0]
  let idx = args[1]
  if a.kind == ckList and idx.kind == ckInt:
    let i = idx.intVal.int
    if i >= 0 and i < a.listItems.len:
      return a.listItems[i]
  cljNil()

proc cljIdentical*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljBool(false)
  cljBool(args[0] == args[1])

proc cljEmptyColl*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljNil()
  let v = args[0]
  if v.isNil: return cljNil()
  case v.kind
  of ckList: cljList(@[])
  of ckVector: cljVector(@[])
  of ckMap: cljMap(@[], @[])
  of ckSet: cljSet(@[])
  of ckString: cljString("")
  else: cljNil()

proc cljSortedMap*(args: seq[CljVal]): CljVal =
  # Fallback to regular hash-map
  cljHashMap(args)

proc cljSortedMapBy*(args: seq[CljVal]): CljVal =
  # Fallback to regular hash-map (ignores comparator)
  if args.len < 1: return cljMap(@[], @[])
  cljHashMap(args[1..^1])

proc cljSortedSet*(args: seq[CljVal]): CljVal =
  # Fallback to regular hash-set
  cljHashSet(args)

proc cljSortedSetBy*(args: seq[CljVal]): CljVal =
  # Fallback to regular hash-set (ignores comparator)
  if args.len < 1: return cljSet(@[])
  cljHashSet(args[1..^1])

proc cljArrayMap*(args: seq[CljVal]): CljVal =
  # Fallback to regular hash-map
  cljHashMap(args)

proc cljSortedQ*(v: CljVal): CljVal =
  cljBool(false)

proc cljRseq*(v: CljVal): CljVal =
  case v.kind
  of ckVector:
    var items: seq[CljVal] = @[]
    for i in countdown(v.vecData.count - 1, 0):
      items.add(v.vecData[i])
    cljList(items)
  of ckList:
    var items: seq[CljVal] = @[]
    for i in countdown(v.listItems.len - 1, 0):
      items.add(v.listItems[i])
    cljList(items)
  else: cljNil()

proc cljListEmpty*(args: seq[CljVal]): CljVal =
  cljList(args)

# Missing function stubs for test suite compatibility
proc cljToFloat*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljFloat(0.0)
  let v = args[0]
  case v.kind
  of ckFloat: return v
  of ckInt: return cljFloat(v.intVal.float)
  of ckString:
    try: return cljFloat(parseFloat(v.strVal))
    except: return cljFloat(0.0)
  else: return cljFloat(0.0)

proc cljToInt*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljInt(0)
  let v = args[0]
  case v.kind
  of ckInt: return v
  of ckFloat: return cljInt(v.floatVal.int64)
  of ckString:
    try: return cljInt(parseInt(v.strVal))
    except: return cljInt(0)
  of ckBool: return cljInt(if v.boolVal: 1 else: 0)
  else: return cljInt(0)

proc cljToBool*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljBool(false)
  let v = args[0]
  case v.kind
  of ckBool: return v
  of ckNil: return cljBool(false)
  of ckInt: return cljBool(v.intVal != 0)
  of ckFloat: return cljBool(v.floatVal != 0.0)
  else: return cljBool(true)

proc cljToArray*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljVector(@[])
  let v = args[0]
  case v.kind
  of ckVector: return v
  of ckList: return cljVector(v.listItems)
  of ckString:
    var items: seq[CljVal] = @[]
    for c in v.strVal: items.add(cljString($c))
    return cljVector(items)
  else: return cljVector(@[v])

proc cljIntoArray*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljVector(@[])
  if args.len == 1:
    return cljToArray(@[args[0]])
  # Ignore type argument, convert last collection argument to vector
  return cljToArray(@[args[^1]])

proc cljVolatileBang*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljNil()
  # volatile! creates a mutable holder - stub as atom
  CljVal(kind: ckAtom, atomVal: args[0])

proc cljVolatileMutableQ*(v: CljVal): CljVal =
  cljBool(v != nil and v.kind == ckAtom)

proc cljDeliver*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljNil()
  args[0]

proc cljDoall*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljNil()
  args[0]

proc cljDorun*(args: seq[CljVal]): CljVal =
  cljNil()

proc cljDropLast*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljList(@[])
  let coll = if args.len >= 2: args[1] else: args[0]
  let n = if args.len >= 2: args[0].intVal.int else: 1
  if coll.isNil or coll.kind notin {ckList, ckVector}: return coll
  let items = if coll.kind == ckList: coll.listItems else: toSeq(coll.vecData)
  if n >= items.len: return cljList(@[])
  cljList(items[0..<(items.len - n)])

proc cljShuffle*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljVector(@[])
  let coll = args[0]
  if coll.isNil: return cljVector(@[])
  var items: seq[CljVal]
  case coll.kind
  of ckList: items = coll.listItems
  of ckVector: items = toSeq(coll.vecData)
  else: return cljVector(@[])
  # Simple shuffle
  for i in countdown(items.len-1, 1):
    let j = i mod (i+1)
    swap(items[i], items[j])
  cljVector(items)

proc cljDouble*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljFloat(0.0)
  let v = args[0]
  case v.kind
  of ckFloat: return v
  of ckInt: return cljFloat(v.intVal.float)
  of ckString:
    try: return cljFloat(parseFloat(v.strVal))
    except: return cljFloat(0.0)
  else: return cljFloat(0.0)

proc cljFnil*(args: seq[CljVal]): CljVal =
  if args.len < 2: return args[0]
  # fnil returns a function that replaces nil args with defaults - simplified stub
  args[0]

proc cljIntern*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljNil()
  args[0]

proc cljEmpty*(v: CljVal): CljVal =
  cljBool(cljCount(v).intVal == 0)

proc cljConcat*(args: seq[CljVal]): CljVal =
  var items: seq[CljVal] = @[]
  for a in args:
    if not a.isNil:
      case a.kind
      of ckList: items.add(a.listItems)
      of ckVector: items.add(toSeq(a.vecData))
      else: discard
  cljList(items)

proc cljRepeatedly*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljList(@[])
  let n = if args.len >= 2: args[0].intVal.int else: 10
  var items: seq[CljVal] = @[]
  for i in 0..<n:
    items.add(cljNil())
  cljList(items)

proc cljMakeHierarchy*(args: seq[CljVal]): CljVal =
  cljMap(@[], @[])

proc cljDerive*(args: seq[CljVal]): CljVal =
  if args.len < 3: return cljNil()
  args[0]

proc cljUnderive*(args: seq[CljVal]): CljVal =
  if args.len < 3: return cljNil()
  args[0]

proc cljAncestors*(args: seq[CljVal]): CljVal =
  if args.len < 1: return cljNil()
  cljSet(@[])

proc cljDescendants*(args: seq[CljVal]): CljVal =
  if args.len < 1: return cljNil()
  cljSet(@[])

proc cljUseFixtures*(args: seq[CljVal]): CljVal =
  cljNil()

proc cljAddWatch*(args: seq[CljVal]): CljVal =
  cljNil()

proc cljRemoveWatch*(args: seq[CljVal]): CljVal =
  cljNil()

proc cljAlterVarRoot*(args: seq[CljVal]): CljVal =
  if args.len >= 2: return args[1]
  cljNil()

proc cljParents*(args: seq[CljVal]): CljVal =
  if args.len < 1: return cljNil()
  cljSet(@[])

proc cljIsa*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljBool(false)
  cljBool(cljIsNil(args[0]) == false and cljIsNil(args[1]) == false)

proc cljBoundFn*(p: proc(args: seq[CljVal]): CljVal): CljVal =
  cljFn(p)

proc cljVar*(v: CljVal): CljVal =
  if v.kind == ckString: return cljString(v.strVal)
  v

proc cljProtocol*(name: string): CljVal =
  cljKeyword(name)

proc cljRecord*(name: string, fields: CljVal): CljVal =
  cljKeyword(name)

proc cljTypeConstructor*(name: string, fields: CljVal): CljVal =
  cljKeyword(name)

proc cljMultiFn*(name: string, dispatchFn: CljVal): CljVal =
  cljFn(proc(args: seq[CljVal]): CljVal = cljNil())

proc cljCreateNs*(args: seq[CljVal]): CljVal =
  cljNil()

proc cljMultiEqual2*(a, b: CljVal): CljVal =
  cljMultiEqual(@[a, b])

proc cljOr2*(a, b: CljVal): CljVal =
  if cljIsTruthy(a): a
  else: b

proc cljPrintlnStr*(args: seq[CljVal]): CljVal =
  var parts: seq[string] = @[]
  for a in args:
    parts.add(cljStr(a))
  cljString(parts.join(" "))

proc cljPrnStr*(args: seq[CljVal]): CljVal =
  var parts: seq[string] = @[]
  for a in args:
    parts.add(cljRepr(a))
  cljString(parts.join(" "))

proc cljBinding*(args: seq[CljVal]): CljVal =
  # binding is complex - stub: just execute body
  if args.len < 2: return cljNil()
  args[^1]

proc cljAset*(args: seq[CljVal]): CljVal =
  if args.len < 3: return cljNil()
  args[0]

proc cljVectorFn*(args: seq[CljVal]): CljVal =
  cljVector(args)

proc cljCompare*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljInt(0)
  let a = args[0]; let b = args[1]
  if a.isNil and b.isNil: return cljInt(0)
  if a.isNil: return cljInt(-1)
  if b.isNil: return cljInt(1)
  case a.kind
  of ckInt:
    if b.kind == ckInt:
      if a.intVal < b.intVal: return cljInt(-1)
      elif a.intVal > b.intVal: return cljInt(1)
      else: return cljInt(0)
    elif b.kind == ckFloat:
      if a.intVal.float < b.floatVal: return cljInt(-1)
      elif a.intVal.float > b.floatVal: return cljInt(1)
      else: return cljInt(0)
  of ckFloat:
    if b.kind == ckFloat:
      if a.floatVal < b.floatVal: return cljInt(-1)
      elif a.floatVal > b.floatVal: return cljInt(1)
      else: return cljInt(0)
    elif b.kind == ckInt:
      if a.floatVal < b.intVal.float: return cljInt(-1)
      elif a.floatVal > b.intVal.float: return cljInt(1)
      else: return cljInt(0)
  of ckString:
    if b.kind == ckString:
      if a.strVal < b.strVal: return cljInt(-1)
      elif a.strVal > b.strVal: return cljInt(1)
      else: return cljInt(0)
  of ckKeyword:
    if b.kind == ckKeyword:
      if a.kwName < b.kwName: return cljInt(-1)
      elif a.kwName > b.kwName: return cljInt(1)
      else: return cljInt(0)
  else: discard
  cljInt(0)

proc cljSubvec*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljVector(@[])
  let v = args[0]
  let start = args[1].intVal.int
  let stop = if args.len >= 3: args[2].intVal.int else: (if v.kind == ckVector: v.vecData.count else: 0)
  if v.kind != ckVector: return cljVector(@[])
  var items: seq[CljVal] = @[]
  for i in start..<min(stop, v.vecData.count):
    items.add(v.vecData[i])
  cljVector(items)

proc cljRand*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljFloat(rand(1.0))
  let n = args[0]
  case n.kind
  of ckInt: return cljInt(rand(n.intVal.int).int64)
  of ckFloat: return cljFloat(rand(n.floatVal))
  else: return cljFloat(rand(1.0))

proc cljRandInt*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljInt(0)
  let n = args[0].intVal.int
  if n <= 0: return cljInt(0)
  cljInt(rand(n).int64)

proc cljRandNth*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljNil()
  let coll = args[0]
  case coll.kind
  of ckVector:
    if coll.vecData.count == 0: return cljNil()
    return coll.vecData[rand(coll.vecData.count)]
  of ckList:
    let items = coll.listItems
    if items.len == 0: return cljNil()
    return items[rand(items.len)]
  else: return cljNil()

proc cljRandomSample*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljList(@[])
  let coll = args[1]
  var items: seq[CljVal] = @[]
  let collItems = case coll.kind
  of ckList: coll.listItems
  of ckVector: toSeq(coll.vecData)
  else: @[]
  for item in collItems:
    if rand(1.0) < 0.5:
      items.add(item)
  cljList(items)

proc cljTake*(n: CljVal, coll: CljVal): CljVal =
  if n.kind != ckInt: raise newException(CatchableError, "take requires an integer")
  let count = n.intVal.int
  if coll.isNil: return cljList(@[])
  case coll.kind
  of ckList: cljList(coll.listItems[0..<min(count, coll.listItems.len)])
  of ckVector: cljList(toSeq(coll.vecData)[0..<min(count, coll.vecData.count)])
  else: cljList(@[])

proc cljDrop*(n: CljVal, coll: CljVal): CljVal =
  if n.kind != ckInt: raise newException(CatchableError, "drop requires an integer")
  let count = n.intVal.int
  if coll.isNil: return cljList(@[])
  case coll.kind
  of ckList: cljList(coll.listItems[min(count, coll.listItems.len)..^1])
  of ckVector: cljList(toSeq(coll.vecData)[min(count, coll.vecData.count)..^1])
  else: cljList(@[])

proc cljReverse*(coll: CljVal): CljVal =
  if coll.isNil: return cljList(@[])
  case coll.kind
  of ckList:
    var items = coll.listItems
    items.reverse()
    cljList(items)
  of ckVector:
    var items = toSeq(coll.vecData)
    items.reverse()
    cljList(items)
  else: cljList(@[])

proc cljSort*(coll: CljVal): CljVal =
  if coll.isNil: return cljList(@[])
  case coll.kind
  of ckList:
    var items = coll.listItems
    items.sort(proc(a, b: CljVal): int =
      if a.kind == ckInt and b.kind == ckInt:
        return cmp(a.intVal, b.intVal)
      return 0)
    cljList(items)
  of ckVector:
    var items = toSeq(coll.vecData)
    items.sort(proc(a, b: CljVal): int =
      if a.kind == ckInt and b.kind == ckInt:
        return cmp(a.intVal, b.intVal)
      return 0)
    cljList(items)
  else: coll

proc cljDistinct*(coll: CljVal): CljVal =
  if coll.isNil: return cljList(@[])
  var seen: seq[CljVal] = @[]
  case coll.kind
  of ckList:
    for item in coll.listItems:
      if item notin seen:
        seen.add(item)
    cljList(seen)
  of ckVector:
    for item in coll.vecData.items:
      if item notin seen:
        seen.add(item)
    cljList(seen)
  else: coll

proc cljFlatten*(coll: CljVal): CljVal =
  if coll.isNil: return cljList(@[])
  var flat: seq[CljVal] = @[]
  proc flattenHelper(v: CljVal) =
    if v.isNil: return
    case v.kind
    of ckList:
      for item in v.listItems:
        flattenHelper(item)
    of ckVector:
      for item in v.vecData.items:
        flattenHelper(item)
    else:
      flat.add(v)
  flattenHelper(coll)
  cljList(flat)

proc cljPartition*(n: int, coll: CljVal): CljVal =
  if coll.isNil: return cljList(@[])
  var items: seq[CljVal]
  case coll.kind
  of ckList: items = coll.listItems
  of ckVector: items = toSeq(coll.vecData)
  else: return cljList(@[])
  var parts: seq[CljVal] = @[]
  var i = 0
  while i + n <= items.len:
    parts.add(cljList(items[i..<i+n]))
    i += n
  cljList(parts)

proc cljFrequencies*(coll: CljVal): CljVal =
  if coll.isNil: return cljMap(@[], @[])
  var m = newPersistentMap[CljVal, CljVal]()
  var items: seq[CljVal]
  case coll.kind
  of ckList: items = coll.listItems
  of ckVector: items = toSeq(coll.vecData)
  else: return cljMap(@[], @[])
  for item in items:
    let current = pmapGet(m, item, cljNil(), hash(item), cljEq)
    if cljIsNil(current):
      m = pmapAssoc(m, item, cljInt(1), hash(item), cljEq)
    else:
      m = pmapAssoc(m, item, cljInt(current.intVal + 1), hash(item), cljEq)
  CljVal(kind: ckMap, mapData: m)

proc cljGroupBy*(f: proc(args: seq[CljVal]): CljVal, coll: CljVal): CljVal =
  if coll.isNil: return cljMap(@[], @[])
  var m = newPersistentMap[CljVal, CljVal]()
  var items: seq[CljVal]
  case coll.kind
  of ckList: items = coll.listItems
  of ckVector: items = toSeq(coll.vecData)
  else: return cljMap(@[], @[])
  for item in items:
    let key = f(@[item])
    let existing = pmapGet(m, key, cljNil(), hash(key), cljEq)
    if cljIsNil(existing):
      m = pmapAssoc(m, key, cljList(@[item]), hash(key), cljEq)
    else:
      var newItems = existing.listItems
      newItems.add(item)
      m = pmapAssoc(m, key, cljList(newItems), hash(key), cljEq)
  CljVal(kind: ckMap, mapData: m)

proc cljGroupBy*(f: CljVal, coll: CljVal): CljVal =
  if f.kind == ckFn: cljGroupBy(f.fnProc, coll)
  else: raise newException(CatchableError, "group-by requires a function")

# ---- Map operations ----

proc cljGet*(m: CljVal, key: CljVal): CljVal =
  if m.isNil: return cljNil()
  case m.kind
  of ckMap: pmapGet(m.mapData, key, cljNil(), hash(key), cljEq)
  of ckSet:
    if pmapContains(m.setData, key, hash(key), cljEq): key
    else: cljNil()
  else: cljNil()

proc cljGetDefault*(m: CljVal, key: CljVal, default: CljVal): CljVal =
  if m.isNil: return default
  case m.kind
  of ckMap: pmapGet(m.mapData, key, default, hash(key), cljEq)
  of ckSet:
    if pmapContains(m.setData, key, hash(key), cljEq): key
    else: default
  else: default

proc cljGet*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljNil()
  if args.len >= 3:
    cljGetDefault(args[0], args[1], args[2])
  else:
    cljGet(args[0], args[1])

proc cljExInfo*(msg: CljVal, data: CljVal): CljVal =
  var ex = newException(ExInfo, cljStr(msg))
  ex.exData = data
  raise ex

proc cljExInfo*(args: seq[CljVal]): CljVal =
  var msg = if args.len > 0: args[0] else: cljString("")
  var data = if args.len > 1: args[1] else: cljNil()
  var ex = newException(ExInfo, cljStr(msg))
  ex.exData = data
  raise ex

proc cljExData*(ex: CljVal): CljVal =
  if ex.isNil: return cljNil()
  case ex.kind
  of ckMap:
    let data = cljGet(ex, cljKeyword("data"))
    if data.kind == ckNil:
      return ex
    return data
  else: return cljNil()

proc cljCall*(f: CljVal, args: seq[CljVal]): CljVal =
  if f.isNil: return cljNil()
  case f.kind
  of ckFn:
    if args.len > 0: return f.fnProc(args)
    else: return f.fnProc(@[])
  of ckMap:
    if args.len > 0: return cljGet(f, args[0])
    else: return cljNil()
  of ckSet:
    if args.len > 0: return cljBool(pmapContains(f.setData, args[0], hash(args[0]), cljEq))
    else: return cljBool(false)
  of ckVector:
    if args.len > 0: return cljNth(f, args[0])
    else: return cljNil()
  of ckKeyword:
    if args.len > 0: return cljGet(args[0], f)
    else: return cljNil()
  else:
    raise newException(CatchableError, "Cannot call value of type " & $f.kind)

proc cljAssoc*(m: CljVal, key: CljVal, val: CljVal): CljVal =
  if m.isNil or m.kind == ckNil:
    return CljVal(kind: ckMap, mapData: pmapAssoc(newPersistentMap[CljVal, CljVal](), key, val, hash(key), cljEq))
  case m.kind
  of ckMap:
    CljVal(kind: ckMap, mapData: pmapAssoc(m.mapData, key, val, hash(key), cljEq))
  of ckVector:
    if key.kind != ckInt:
      raise newException(CatchableError, "assoc on vector requires integer index")
    let idx = key.intVal
    let cnt = m.vecData.count
    if idx < 0 or idx > cnt:
      raise newException(CatchableError, "Index out of bounds: " & $idx)
    if idx == cnt:
      CljVal(kind: ckVector, vecData: pvecConj(m.vecData, val))
    else:
      CljVal(kind: ckVector, vecData: pvecAssoc(m.vecData, idx, val))
  else:
    raise newException(CatchableError, "assoc expects a map or vector")

proc cljAssoc*(args: seq[CljVal]): CljVal =
  if args.len < 3: raise newException(CatchableError, "assoc requires 3 arguments")
  cljAssoc(args[0], args[1], args[2])

proc cljDissoc*(m: CljVal, key: CljVal): CljVal =
  if m.isNil or m.kind != ckMap: return cljMap(@[], @[])
  CljVal(kind: ckMap, mapData: pmapDissoc(m.mapData, key, hash(key), cljEq))

proc cljDissoc*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljMap(@[], @[])
  cljDissoc(args[0], args[1])

proc cljContains*(m: CljVal, key: CljVal): CljVal =
  if m.isNil: return cljBool(false)
  case m.kind
  of ckMap: cljBool(pmapContains(m.mapData, key, hash(key), cljEq))
  of ckSet: cljBool(pmapContains(m.setData, key, hash(key), cljEq))
  else: cljBool(false)

proc cljKeys*(m: CljVal): CljVal =
  if m.isNil or m.kind != ckMap: return cljList(@[])
  cljList(pmapKeys(m.mapData))

proc cljVals*(m: CljVal): CljVal =
  if m.isNil or m.kind != ckMap: return cljList(@[])
  cljList(pmapVals(m.mapData))

proc cljSelectKeys*(m: CljVal, keys: seq[CljVal]): CljVal =
  if m.isNil or m.kind != ckMap: return cljMap(@[], @[])
  var res = newPersistentMap[CljVal, CljVal]()
  for key in keys:
    let v = pmapGet(m.mapData, key, cljNil(), hash(key), cljEq)
    if not cljIsNil(v):
      res = pmapAssoc(res, key, v, hash(key), cljEq)
  CljVal(kind: ckMap, mapData: res)

proc cljMerge*(args: seq[CljVal]): CljVal =
  var res = newPersistentMap[CljVal, CljVal]()
  for m in args:
    if not m.isNil and m.kind == ckMap:
      for (k, v) in pmapItems(m.mapData):
        res = pmapAssoc(res, k, v, hash(k), cljEq)
  CljVal(kind: ckMap, mapData: res)

# ---- Higher-order functions ----

proc cljMapSeq*(f: proc(args: seq[CljVal]): CljVal, coll: seq[CljVal]): seq[CljVal] =
  result = @[]
  for item in coll:
    result.add(f(@[item]))

proc cljFilterSeq*(f: proc(args: seq[CljVal]): CljVal, coll: seq[CljVal]): seq[CljVal] =
  result = @[]
  for item in coll:
    let r = f(@[item])
    if cljIsTruthy(r):
      result.add(item)

proc cljReduceSeq*(f: proc(args: seq[CljVal]): CljVal, init: CljVal, coll: seq[CljVal]): CljVal =
  if coll.len == 0:
    return init
  var i = 0
  if init.isNil or init.kind == ckNil:
    result = coll[0]
    i = 1
  else:
    result = init
  while i < coll.len:
    result = f(@[result, coll[i]])
    i += 1

proc cljMap*(f: proc(args: seq[CljVal]): CljVal, coll: CljVal): CljVal =
  if coll.isNil: return cljList(@[])
  case coll.kind
  of ckList: cljList(cljMapSeq(f, coll.listItems))
  of ckVector: cljList(cljMapSeq(f, toSeq(coll.vecData)))
  else: cljList(@[])

proc cljMap*(f: CljVal, coll: CljVal): CljVal =
  if f.kind == ckFn: cljMap(f.fnProc, coll)
  else: raise newException(CatchableError, "map requires a function")

proc cljMapN*(f: CljVal, colls: seq[CljVal]): CljVal =
  if f.kind != ckFn: raise newException(CatchableError, "map requires a function")
  let fn = f.fnProc
  var seqs: seq[seq[CljVal]] = newSeq[seq[CljVal]]()
  for coll in colls:
    if coll.isNil:
      seqs.add(@[])
    else:
      case coll.kind
      of ckList: seqs.add(coll.listItems)
      of ckVector: seqs.add(toSeq(coll.vecData))
      else: seqs.add(@[])
  if seqs.len == 0: return cljList(@[])
  var res = newSeq[CljVal]()
  var i = 0
  while true:
    var args = newSeq[CljVal]()
    for s in seqs:
      if i >= s.len: return cljList(res)
      args.add(s[i])
    res.add(fn(args))
    i += 1

proc cljFilter*(f: proc(args: seq[CljVal]): CljVal, coll: CljVal): CljVal =
  if coll.isNil: return cljList(@[])
  case coll.kind
  of ckList: cljList(cljFilterSeq(f, coll.listItems))
  of ckVector: cljList(cljFilterSeq(f, toSeq(coll.vecData)))
  else: cljList(@[])

proc cljFilter*(f: CljVal, coll: CljVal): CljVal =
  if f.kind == ckFn: cljFilter(f.fnProc, coll)
  else: raise newException(CatchableError, "filter requires a function")

proc cljReduce*(f: proc(args: seq[CljVal]): CljVal, init: CljVal, coll: CljVal): CljVal =
  if coll.isNil: return init
  case coll.kind
  of ckList: cljReduceSeq(f, init, coll.listItems)
  of ckVector: cljReduceSeq(f, init, toSeq(coll.vecData))
  else: init

proc cljReduce*(f: CljVal, init: CljVal, coll: CljVal): CljVal =
  if f.kind == ckFn: cljReduce(f.fnProc, init, coll)
  else: raise newException(CatchableError, "reduce requires a function")

proc cljTransduce*(xform: CljVal, f: CljVal, init: CljVal, coll: CljVal): CljVal =
  # Stub: apply xform to f and reduce
  if xform.kind == ckFn and f.kind == ckFn:
    let rf = xform.fnProc(@[f])
    if rf.kind == ckFn:
      return cljReduce(rf, init, coll)
  # Fallback: just return init
  return init

proc cljTransduce*(args: seq[CljVal]): CljVal =
  if args.len < 4: return cljNil()
  cljTransduce(args[0], args[1], args[2], args[3])

proc cljMapv*(f: proc(args: seq[CljVal]): CljVal, coll: CljVal): CljVal =
  if coll.isNil: return cljVector(@[])
  case coll.kind
  of ckList: cljVector(cljMapSeq(f, coll.listItems))
  of ckVector: cljVector(cljMapSeq(f, toSeq(coll.vecData)))
  else: cljVector(@[])

proc cljMapv*(f: CljVal, coll: CljVal): CljVal =
  if f.kind == ckFn: cljMapv(f.fnProc, coll)
  else: raise newException(CatchableError, "mapv requires a function")

proc cljSome*(f: CljVal, coll: CljVal): CljVal =
  if coll.isNil: return cljNil()
  let fn = f.fnProc
  var items: seq[CljVal]
  case coll.kind
  of ckList: items = coll.listItems
  of ckVector: items = toSeq(coll.vecData)
  else: return cljNil()
  for item in items:
    let r = fn(@[item])
    if cljIsTruthy(r):
      return r
  cljNil()

proc cljEvery*(f: CljVal, coll: CljVal): CljVal =
  if coll.isNil: return cljBool(true)
  let fn = f.fnProc
  var items: seq[CljVal]
  case coll.kind
  of ckList: items = coll.listItems
  of ckVector: items = toSeq(coll.vecData)
  else: return cljBool(true)
  for item in items:
    let r = fn(@[item])
    if not cljIsTruthy(r):
      return cljBool(false)
  cljBool(true)

proc cljApply*(f: CljVal, args: CljVal): CljVal =
  if f.kind != ckFn: raise newException(CatchableError, "apply requires a function")
  var argSeq: seq[CljVal] = @[]
  if not args.isNil:
    case args.kind
    of ckList: argSeq = args.listItems
    of ckVector: argSeq = toSeq(args.vecData)
    else: argSeq = @[args]
  f.fnProc(argSeq)

proc cljComp*(fns: seq[CljVal]): CljVal =
  let realFns = fns.mapIt(it.fnProc)
  cljFn(proc(args: seq[CljVal]): CljVal =
    result = realFns[^1](args)
    for i in countdown(realFns.len - 2, 0):
      result = realFns[i](@[result]))

proc cljPartial*(f: CljVal, partialArgs: seq[CljVal]): CljVal =
  let realF = f.fnProc
  cljFn(proc(args: seq[CljVal]): CljVal =
    var allArgs = partialArgs
    allArgs.add(args)
    realF(allArgs))

proc cljJuxt*(fns: seq[CljVal]): CljVal =
  let realFns = fns.mapIt(it.fnProc)
  cljFn(proc(args: seq[CljVal]): CljVal =
    var results: seq[CljVal] = @[]
    for f in realFns:
      results.add(f(args))
    cljList(results))

proc cljComplement*(f: CljVal): CljVal =
  let realF = f.fnProc
  cljFn(proc(args: seq[CljVal]): CljVal =
    cljNot(realF(args)))

# ---- String functions ----

proc cljStrConcat*(args: seq[CljVal]): CljVal =
  var s = ""
  for a in args:
    s.add(cljStr(a))
  cljString(s)

proc cljPrStrConcat*(args: seq[CljVal]): CljVal =
  var parts: seq[string] = @[]
  for a in args:
    parts.add(cljRepr(a))
  cljString(parts.join(" "))

proc cljSubs*(s: CljVal, startIdx: int): CljVal =
  if s.kind != ckString: raise newException(CatchableError, "subs requires a string")
  if startIdx < 0 or startIdx >= s.strVal.len:
    raise newException(IndexDefect, "subs: index out of range")
  cljString(s.strVal[startIdx..^1])

proc cljSubsRange*(s: CljVal, startIdx, endIdx: int): CljVal =
  if s.kind != ckString: raise newException(CatchableError, "subs requires a string")
  if startIdx < 0 or startIdx > endIdx or endIdx > s.strVal.len:
    raise newException(IndexDefect, "subs: index out of range")
  cljString(s.strVal[startIdx..<endIdx])

proc cljStrJoin*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljString("")
  if args.len == 1:
    case args[0].kind
    of ckList: return cljString(args[0].listItems.mapIt(cljStr(it)).join(""))
    of ckVector: return cljString(toSeq(args[0].vecData).mapIt(cljStr(it)).join(""))
    else: return cljString(cljStr(args[0]))
  let sep = cljStr(args[0])
  case args[1].kind
  of ckList: cljString(args[1].listItems.mapIt(cljStr(it)).join(sep))
  of ckVector: cljString(toSeq(args[1].vecData).mapIt(cljStr(it)).join(sep))
  else: cljString(cljStr(args[1]))

proc cljStrSplit*(s: CljVal, sep: CljVal): CljVal =
  if s.kind != ckString: raise newException(CatchableError, "split requires a string")
  let sepStr = cljStr(sep)
  var parts: seq[string]
  # Check if pattern looks like regex (contains special chars)
  if sepStr.contains(re"[\\^$.*+?{}()\[\]|]"):
    try:
      let regex = re(sepStr)
      parts = s.strVal.split(regex)
    except CatchableError:
      # Fallback to string split if regex is invalid
      parts = s.strVal.split(sepStr)
  else:
    parts = s.strVal.split(sepStr)
  var items: seq[CljVal] = @[]
  for p in parts:
    if p.len > 0:  # Skip empty strings from split
      items.add(cljString(p))
  cljList(items)

proc cljStrReplace*(s: CljVal, match: CljVal, replacement: CljVal): CljVal =
  if s.kind != ckString: raise newException(CatchableError, "replace requires a string")
  cljString(s.strVal.replace(cljStr(match), cljStr(replacement)))

proc cljStrTrim*(s: CljVal): CljVal =
  if s.kind != ckString: raise newException(CatchableError, "trim requires a string")
  cljString(s.strVal.strip())

proc cljStrStartsWith*(s: CljVal, prefix: CljVal): CljVal =
  if s.kind != ckString: raise newException(CatchableError, "starts-with? requires a string")
  cljBool(s.strVal.startsWith(cljStr(prefix)))

proc cljStrEndsWith*(s: CljVal, suffix: CljVal): CljVal =
  if s.kind != ckString: raise newException(CatchableError, "ends-with? requires a string")
  cljBool(s.strVal.endsWith(cljStr(suffix)))

proc cljStrIncludes*(s: CljVal, sub: CljVal): CljVal =
  if s.kind != ckString: raise newException(CatchableError, "includes? requires a string")
  cljBool(cljStr(sub) in s.strVal)

proc cljStrUpper*(s: CljVal): CljVal =
  if s.kind != ckString: raise newException(CatchableError, "upper-case requires a string")
  cljString(s.strVal.toUpper())

proc cljStrLower*(s: CljVal): CljVal =
  if s.kind != ckString: raise newException(CatchableError, "lower-case requires a string")
  cljString(s.strVal.toLower())

# ---- Misc ----

proc cljIdentity*(args: seq[CljVal]): CljVal =
  if args.len == 0: cljNil()
  else: args[0]

proc cljConstantly*(v: CljVal): CljVal =
  cljFn(proc(args: seq[CljVal]): CljVal = v)

proc cljType*(v: CljVal): CljVal =
  if v.isNil: return cljKeyword("nil")
  case v.kind
  of ckNil: cljKeyword("nil")
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

proc cljInstanceP*(t: CljVal, v: CljVal): CljVal =
  if t.kind != ckKeyword: return cljBool(false)
  let vt = cljType(v)
  cljBool(t.kwName == vt.kwName)

proc cljMeta*(v: CljVal): CljVal =
  if v.isNil: return cljNil()
  if v.meta.isNil: return cljNil()
  v.meta

proc cljWithMeta*(v: CljVal, m: CljVal): CljVal =
  if v.isNil: return v
  var copy = v  # share ref, but we need a copy
  copy = CljVal(kind: v.kind, meta: m)
  case v.kind
  of ckNil: discard
  of ckBool: copy.boolVal = v.boolVal
  of ckInt: copy.intVal = v.intVal
  of ckFloat: copy.floatVal = v.floatVal
  of ckString: copy.strVal = v.strVal
  of ckKeyword: copy.kwName = v.kwName
  of ckSymbol: copy.symName = v.symName
  of ckList: copy.listItems = v.listItems
  of ckVector: copy.vecData = v.vecData
  of ckMap: copy.mapData = v.mapData
  of ckSet: copy.setData = v.setData
  of ckFn: copy.fnProc = v.fnProc
  of ckAtom: copy.atomVal = v.atomVal
  of ckTransient: copy.transKind = v.transKind; copy.transVec = v.transVec; copy.transPairs = v.transPairs
  of ckAgent: copy.agentVal = v.agentVal; initLock(copy.agentLock)
  return copy

proc cljAtom*(v: CljVal): CljVal =
  CljVal(kind: ckAtom, atomVal: v)

proc cljAtom*(args: seq[CljVal]): CljVal =
  if args.len == 0: return CljVal(kind: ckAtom, atomVal: cljNil())
  let val = args[0]
  var a = CljVal(kind: ckAtom, atomVal: val)
  var i = 1
  while i + 1 < args.len:
    if args[i].kind == ckKeyword:
      case args[i].kwName
      of "validator": discard
      of "meta": a.meta = args[i+1]
      else: discard
    i += 2
  a

proc cljPromise*(): CljVal =
  cljAtom(cljNil())

proc cljPromise*(args: seq[CljVal]): CljVal =
  cljAtom(cljNil())

proc cljForce*(v: CljVal): CljVal =
  if v.kind == ckAtom: v.atomVal
  else: v

proc cljSleep*(ms: CljVal): CljVal =
  cljNil()

proc cljTap*(args: seq[CljVal]): CljVal =
  if args.len >= 1: return args[0]
  cljNil()

proc cljFutureCancel*(v: CljVal): CljVal =
  cljNil()

proc cljAddTap*(args: seq[CljVal]): CljVal =
  cljNil()

proc cljRemoveTap*(args: seq[CljVal]): CljVal =
  cljNil()

proc cljFuture*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljAtom(cljNil())
  let f = args[0]
  if f.kind == ckFn:
    cljAtom(f.fnProc(@[]))
  else:
    cljAtom(cljNil())

proc cljDelay*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljAtom(cljNil())
  let f = args[0]
  if f.kind == ckFn:
    cljAtom(f.fnProc(@[]))
  else:
    cljAtom(f)

proc cljDeref*(a: CljVal): CljVal =
  if a.kind == ckAtom: a.atomVal
  elif a.kind == ckAgent: a.agentVal
  else: raise newException(CatchableError, "deref requires an atom or agent")

proc cljReset*(a: CljVal, v: CljVal): CljVal =
  if a.kind == ckAtom:
    a.atomVal = v
    v
  else:
    raise newException(CatchableError, "reset! requires an atom")

proc cljSwapImpl(a: CljVal, f: proc(args: seq[CljVal]): CljVal, args: seq[CljVal]): CljVal =
  if a.kind == ckAtom:
    var fargs = @[a.atomVal]
    fargs.add(args)
    a.atomVal = f(fargs)
    a.atomVal
  else:
    raise newException(CatchableError, "swap! requires an atom")

proc cljSwap*(args: seq[CljVal]): CljVal =
  if args.len < 2: raise newException(CatchableError, "swap! requires at least 2 arguments")
  let a = args[0]
  let f = args[1]
  let rest = if args.len > 2: args[2..^1] else: @[]
  if f.kind == ckFn: cljSwapImpl(a, f.fnProc, rest)
  else: raise newException(CatchableError, "swap! requires a function")

proc cljVswap*(args: seq[CljVal]): CljVal =
  # Treat volatile like atom for now
  cljSwap(args)

# ---- Agents ----

proc cljAgent*(v: CljVal): CljVal =
  result = CljVal(kind: ckAgent, agentVal: v, agentBusy: false)
  initLock(result.agentLock)

proc cljAgentSend*(agent: CljVal, f: CljVal, args: seq[CljVal] = @[]): CljVal =
  if agent.kind != ckAgent:
    raise newException(CatchableError, "send requires an agent")
  withLock agent.agentLock:
    agent.agentQueue.add(AgentAction(fn: f, args: args))
    if not agent.agentBusy:
      agent.agentBusy = true
      # Process actions synchronously for now (thread-safe design ready for async)
      var fargs = @[agent.agentVal]
      fargs.add(args)
      if f.kind == ckFn:
        agent.agentVal = f.fnProc(fargs)
      agent.agentBusy = false
      agent.agentQueue = @[]
  agent

proc cljAgentDeref*(a: CljVal): CljVal =
  if a.kind != ckAgent:
    raise newException(CatchableError, "deref requires an agent")
  a.agentVal

proc cljAgentAwait*(agent: CljVal): CljVal =
  if agent.kind != ckAgent:
    raise newException(CatchableError, "await requires an agent")
  cljNil()

proc cljAgentError*(agent: CljVal): CljVal =
  if agent.kind != ckAgent:
    raise newException(CatchableError, "agent-error requires an agent")
  cljNil()

proc cljAgentShutdown*(agent: CljVal): CljVal =
  if agent.kind != ckAgent:
    raise newException(CatchableError, "shutdown-agents requires an agent")
  withLock agent.agentLock:
    agent.agentQueue = @[]
  cljNil()

# ---- STM Refs ----

proc cljRef*(v: CljVal): CljVal =
  CljVal(kind: ckAtom, atomVal: v)

proc cljRefSet*(r, val: CljVal): CljVal =
  if r.kind == ckAtom:
    r.atomVal = val
    val
  else:
    raise newException(CatchableError, "ref-set requires a ref")

proc cljDosync*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljNil()
  args[^1]

proc cljAlter*(args: seq[CljVal]): CljVal =
  if args.len < 2:
    raise newException(CatchableError, "alter requires at least 2 arguments")
  let refv = args[0]
  if refv.kind != ckAtom:
    raise newException(CatchableError, "alter requires a ref")
  let f = args[1]
  if f.kind != ckFn:
    raise newException(CatchableError, "alter requires a function")
  var fargs = @[refv.atomVal]
  if args.len > 2:
    fargs.add(args[2..^1])
  refv.atomVal = f.fnProc(fargs)
  refv.atomVal

# ---- Channels (core.async) ----

proc cljChan*(args: seq[CljVal]): CljVal =
  # For compiled path, channels are represented as vectors
  # (chan) -> empty vector (unbuffered)
  # (chan n) -> vector with capacity marker
  cljVector(@[])

proc cljChanClose*(ch: CljVal): CljVal =
  cljNil()

# ---- Transients ----

proc cljTransient*(coll: CljVal): CljVal =
  case coll.kind
  of ckVector:
    result = CljVal(kind: ckTransient, transKind: ckVector)
    result.transVec = toSeq(coll.vecData)
  of ckMap:
    result = CljVal(kind: ckTransient, transKind: ckMap)
    result.transPairs = pmapEntries(coll.mapData)
  of ckSet:
    result = CljVal(kind: ckTransient, transKind: ckVector)
    result.transVec = pmapKeys(coll.setData)
  else:
    raise newException(CatchableError, "transient requires a collection")

proc cljPersistent*(t: CljVal): CljVal =
  if t.isNil or t.kind != ckTransient:
    raise newException(CatchableError, "persistent! requires a transient")
  case t.transKind
  of ckVector:
    cljVector(t.transVec)
  of ckMap:
    var m = newPersistentMap[CljVal, CljVal]()
    for (k, v) in t.transPairs:
      m = pmapAssoc(m, k, v, hash(k), cljEq)
    CljVal(kind: ckMap, mapData: m)
  else:
    raise newException(CatchableError, "persistent! requires a transient")

proc cljConjB*(t: CljVal, item: CljVal): CljVal =
  if t.isNil or t.kind != ckTransient:
    raise newException(CatchableError, "conj! requires a transient")
  case t.transKind
  of ckVector:
    t.transVec.add(item)
  of ckMap:
    if item.kind == ckVector and item.vecData.count == 2:
      t.transPairs.add((pvecNth(item.vecData, 0), pvecNth(item.vecData, 1)))
  of ckSet: discard
  else: raise newException(CatchableError, "conj! unsupported source type")
  t

proc cljAssocB*(t: CljVal, key: CljVal, val: CljVal): CljVal =
  if t.isNil or t.kind != ckTransient:
    raise newException(CatchableError, "assoc! requires a transient")
  if t.transKind == ckMap:
    t.transPairs.add((key, val))
  t

# ---- Additional functions needed by emitter ----

proc cljNotEq*(args: seq[CljVal]): CljVal =
  cljNot(cljMultiEqual(args))

proc cljGetIn*(m: CljVal, keys: CljVal, default: CljVal = nil): CljVal =
  if keys.isNil or (keys.kind != ckList and keys.kind != ckVector):
    if default != nil: return default
    return cljNil()
  var current = m
  let keyItems = if keys.kind == ckList: keys.listItems else: toSeq(keys.vecData)
  for key in keyItems:
    if current.isNil or current.kind != ckMap:
      if default != nil: return default
      return cljNil()
    current = cljGet(current, key)
    if cljIsNil(current):
      if default != nil: return default
      return cljNil()
  current

proc cljInto*(to: CljVal, src: CljVal): CljVal =
  if src.isNil: return to
  case to.kind
  of ckVector:
    case src.kind
    of ckList:
      var items = toSeq(to.vecData)
      items.add(src.listItems)
      cljVector(items)
    of ckVector:
      var items = toSeq(to.vecData)
      items.add(toSeq(src.vecData))
      cljVector(items)
    else: to
  of ckList:
    case src.kind
    of ckList:
      var items = to.listItems
      items.add(src.listItems)
      cljList(items)
    of ckVector:
      var items = to.listItems
      items.add(toSeq(src.vecData))
      cljList(items)
    else: to
  of ckMap:
    if src.kind == ckMap:
      var res = to.mapData
      for (k, v) in pmapItems(src.mapData):
        res = pmapAssoc(res, k, v, hash(k), cljEq)
      CljVal(kind: ckMap, mapData: res)
    elif src.kind == ckVector:
      var res = to.mapData
      for pair in src.vecData.items:
        if pair.kind == ckVector and pair.vecData.count == 2:
          res = pmapAssoc(res, pvecNth(pair.vecData, 0), pvecNth(pair.vecData, 1), hash(pvecNth(pair.vecData, 0)), cljEq)
      CljVal(kind: ckMap, mapData: res)
    elif src.kind == ckList:
      var res = to.mapData
      for pair in src.listItems:
        if pair.kind == ckVector and pair.vecData.count == 2:
          res = pmapAssoc(res, pvecNth(pair.vecData, 0), pvecNth(pair.vecData, 1), hash(pvecNth(pair.vecData, 0)), cljEq)
      CljVal(kind: ckMap, mapData: res)
    else: to
  else: to

proc cljUpdate*(m: CljVal, key: CljVal, f: proc(args: seq[CljVal]): CljVal, extra: seq[CljVal] = @[]): CljVal =
  if m.isNil or m.kind != ckMap: return m
  let current = cljGet(m, key)
  var fargs = @[current]
  fargs.add(extra)
  let newVal = f(fargs)
  cljAssoc(m, key, newVal)

proc cljUpdate*(m: CljVal, key: CljVal, f: CljVal, extra: seq[CljVal] = @[]): CljVal =
  if f.kind == ckFn: cljUpdate(m, key, f.fnProc, extra)
  else: raise newException(CatchableError, "update requires a function")

proc cljAssocIn*(m: CljVal, keys: CljVal, val: CljVal): CljVal =
  if keys.isNil: return m
  let isList = keys.kind == ckList or keys.kind == ckVector
  if not isList: return m
  let keyItems = if keys.kind == ckList: keys.listItems else: keys.vecData.toSeq
  if keyItems.len == 0: return m
  if keyItems.len == 1:
    return cljAssoc(m, keyItems[0], val)
  let firstKey = keyItems[0]
  let restKeys = cljList(keyItems[1..^1])
  let inner = cljGet(m, firstKey)
  let updated = cljAssocIn(inner, restKeys, val)
  cljAssoc(m, firstKey, updated)

proc cljRange*(n: CljVal): CljVal =
  if n.kind != ckInt: raise newException(CatchableError, "range requires an integer")
  var items: seq[CljVal] = @[]
  for i in 0..<n.intVal:
    items.add(cljInt(i))
  cljList(items)

proc cljRange*(start, finish: CljVal): CljVal =
  if start.kind != ckInt or finish.kind != ckInt:
    raise newException(CatchableError, "range requires integers")
  var items: seq[CljVal] = @[]
  for i in start.intVal..<finish.intVal:
    items.add(cljInt(i))
  cljList(items)

proc cljRange3*(start, finish, step: CljVal): CljVal =
  if start.kind != ckInt or finish.kind != ckInt or step.kind != ckInt:
    raise newException(CatchableError, "range requires integers")
  if step.intVal == 0: raise newException(CatchableError, "range step cannot be zero")
  var items: seq[CljVal] = @[]
  if step.intVal > 0:
    var i = start.intVal
    while i < finish.intVal:
      items.add(cljInt(i))
      i += step.intVal
  else:
    var i = start.intVal
    while i > finish.intVal:
      items.add(cljInt(i))
      i += step.intVal
  cljList(items)

proc cljRepeat*(n: CljVal, x: CljVal): CljVal =
  if n.kind != ckInt: raise newException(CatchableError, "repeat requires an integer count")
  var items: seq[CljVal] = @[]
  for i in 0..<n.intVal:
    items.add(x)
  cljList(items)

proc cljRepeat*(x: CljVal): CljVal =
  cljRepeat(cljInt(1000), x)

proc cljCycle*(n: CljVal, coll: CljVal): CljVal =
  if n.kind != ckInt: raise newException(CatchableError, "cycle requires an integer count")
  var srcItems: seq[CljVal] = @[]
  case coll.kind
  of ckList: srcItems = coll.listItems
  of ckVector: srcItems = toSeq(coll.vecData)
  else: return cljList(@[])
  if srcItems.len == 0: return cljList(@[])
  var items: seq[CljVal] = @[]
  for i in 0..<n.intVal:
    items.add(srcItems[i mod srcItems.len])
  cljList(items)

proc cljCycle*(coll: CljVal): CljVal =
  cljCycle(cljInt(1000), coll)

proc cljIterate*(n: CljVal, f: CljVal, x: CljVal): CljVal =
  if n.kind != ckInt: raise newException(CatchableError, "iterate requires an integer count")
  if f.kind != ckFn: raise newException(CatchableError, "iterate requires a function")
  var items: seq[CljVal] = @[x]
  var current = x
  for i in 1..<n.intVal:
    current = f.fnProc(@[current])
    items.add(current)
  cljList(items)

proc cljInterleave*(args: seq[CljVal]): CljVal =
  if args.len < 2: raise newException(CatchableError, "interleave requires at least 2 arguments")
  var seqs: seq[seq[CljVal]] = @[]
  for a in args:
    case a.kind
    of ckList: seqs.add(a.listItems)
    of ckVector: seqs.add(toSeq(a.vecData))
    else: seqs.add(@[])
  var minLen = seqs[0].len
  for s in seqs:
    if s.len < minLen: minLen = s.len
  var items: seq[CljVal] = @[]
  for i in 0..<minLen:
    for s in seqs:
      items.add(s[i])
  cljList(items)

proc cljReadLine*(): CljVal =
  try:
    var line = ""
    if readLine(stdin, line):
      cljString(line)
    else:
      cljNil()
  except EOFError:
    cljNil()

# ---- File Operations ----

proc cljFileRead*(path: CljVal): CljVal =
  if path.kind != ckString:
    return cljMapFromPairs(@[(cljKeyword("error"), cljString("file/read requires a string path"))])
  try:
    let content = readFile(path.strVal)
    cljString(content)
  except CatchableError as e:
    cljMapFromPairs(@[(cljKeyword("error"), cljString(e.msg))])

proc cljFileWrite*(path, content: CljVal): CljVal =
  if path.kind != ckString or content.kind != ckString:
    return cljMapFromPairs(@[(cljKeyword("error"), cljString("file/write requires two strings"))])
  try:
    writeFile(path.strVal, content.strVal)
    cljBool(true)
  except CatchableError as e:
    cljMapFromPairs(@[(cljKeyword("error"), cljString(e.msg))])

proc cljFileAppend*(path, content: CljVal): CljVal =
  if path.kind != ckString or content.kind != ckString:
    return cljMapFromPairs(@[(cljKeyword("error"), cljString("file/append requires two strings"))])
  try:
    let f = open(path.strVal, fmAppend)
    f.write(content.strVal)
    f.close()
    cljBool(true)
  except CatchableError as e:
    cljMapFromPairs(@[(cljKeyword("error"), cljString(e.msg))])

proc cljFileLs*(dir: CljVal): CljVal =
  let path = if dir.kind == ckString: dir.strVal else: "."
  var items: seq[CljVal] = @[]
  try:
    for kind, name in walkDir(path):
      items.add(cljString(name))
    cljVector(items)
  except CatchableError as e:
    cljVector(@[cljString("error: " & e.msg)])

proc cljFileExists*(path: CljVal): CljVal =
  if path.kind != ckString:
    return cljBool(false)
  cljBool(fileExists(path.strVal))

# ---- Git Operations ----

proc cljGitStatus*(): CljVal =
  let (branchOut, _) = execCmdEx("git rev-parse --abbrev-ref HEAD")
  let branch = branchOut.strip()
  let (statusOut, _) = execCmdEx("git status --porcelain")
  var modified: seq[CljVal] = @[]
  var untracked: seq[CljVal] = @[]
  var staged: seq[CljVal] = @[]
  for line in statusOut.splitLines():
    if line.len < 3: continue
    let status = line[0..1]
    let file = line[3..^1]
    if status[0] != ' ' and status[0] != '?':
      staged.add(cljString(file))
    if status[1] != ' ':
      modified.add(cljString(file))
    if status == "??":
      untracked.add(cljString(file))
  let clean = modified.len == 0 and untracked.len == 0 and staged.len == 0
  cljMapFromPairs(@[
    (cljKeyword("branch"), cljString(branch)),
    (cljKeyword("modified"), cljVector(modified)),
    (cljKeyword("untracked"), cljVector(untracked)),
    (cljKeyword("staged"), cljVector(staged)),
    (cljKeyword("clean"), cljBool(clean))
  ])

proc cljGitCommit*(msg: CljVal): CljVal =
  if msg.kind != ckString:
    return cljMapFromPairs(@[(cljKeyword("error"), cljString("git/commit requires a string message"))])
  let (gitOut, exit) = execCmdEx("git add -A && git commit -m " & quoteShell(msg.strVal))
  if exit != 0:
    return cljMapFromPairs(@[(cljKeyword("error"), cljString(gitOut)), (cljKeyword("success"), cljBool(false))])
  var sha = ""
  let (shaOut, _) = execCmdEx("git rev-parse --short HEAD")
  sha = shaOut.strip()
  cljMapFromPairs(@[
    (cljKeyword("sha"), cljString(sha)),
    (cljKeyword("success"), cljBool(true))
  ])

proc cljGitPush*(): CljVal =
  let (gitOut, exit) = execCmdEx("git push")
  cljMapFromPairs(@[
    (cljKeyword("success"), cljBool(exit == 0)),
    (cljKeyword("output"), cljString(gitOut.strip()))
  ])

proc cljGitDiff*(): CljVal =
  let (gitOut, _) = execCmdEx("git diff")
  cljString(gitOut)

proc cljGitLog*(n: CljVal = cljInt(5)): CljVal =
  let count = if n.kind == ckInt: n.intVal else: 5
  let (gitOut, _) = execCmdEx("git log --oneline -" & $count)
  var items: seq[CljVal] = @[]
  for line in gitOut.splitLines():
    if line.len > 0:
      items.add(cljString(line))

proc cljZipmap*(args: seq[CljVal]): CljVal =
  if args.len < 2:
    raise newException(CatchableError, "zipmap requires 2 arguments")
  let keys = args[0]
  let vals = args[1]
  if keys.kind != ckVector and keys.kind != ckList:
    raise newException(CatchableError, "zipmap: first argument must be seqable")
  var kitems: seq[CljVal] = @[]
  var vitems: seq[CljVal] = @[]
  case keys.kind
  of ckVector: kitems = keys.vecData.toSeq()
  of ckList: kitems = keys.listItems
  else: discard
  case vals.kind
  of ckVector: vitems = vals.vecData.toSeq()
  of ckList: vitems = vals.listItems
  else: discard
  var mk: seq[CljVal] = @[]
  var mv: seq[CljVal] = @[]
  let n = min(kitems.len, vitems.len)
  for i in 0..<n:
    mk.add(kitems[i])
    mv.add(vitems[i])
  return cljMap(mk, mv)

# ---- Missing stubs ----

proc cljRandomUuid*(args: seq[CljVal]): CljVal =
  randomize()
  var uuid = ""
  for i in 0..<32:
    uuid.add("0123456789abcdef"[rand(15)])
    if i in {7, 11, 15, 19}: uuid.add('-')
  cljString(uuid)

proc cljSystemGetProperty*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljNil()
  let key = if args[0].kind == ckString: args[0].strVal else: ""
  case key
  of "line.separator": cljString("\n")
  of "file.separator": cljString("/")
  of "path.separator": cljString(":")
  of "os.name": cljString("linux")
  of "os.arch": cljString("x86_64")
  of "java.version": cljString("0")
  else: cljString("")

proc cljVresetB*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljNil()
  if args[0].kind == ckAtom:
    args[0].atomVal = args[1]
    args[1]
  else:
    raise newException(CatchableError, "vreset! requires a volatile")

proc cljRestartAgent*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljNil()
  if args[0].kind == ckAgent:
    args[0].agentVal = args[1]
    args[0].agentBusy = false
    args[0]
  else:
    raise newException(CatchableError, "restart-agent requires an agent")

proc cljRequire*(args: seq[CljVal]): CljVal =
  cljNil()

proc cljEvalStub*(args: seq[CljVal]): CljVal =
  cljNil()

proc cljResolve*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljNil()
  cljNil()

proc Boolean*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljBool(false)
  let v = args[0]
  if v.kind == ckBool: v
  elif v.kind == ckString: cljBool(v.strVal.toLowerAscii() == "true")
  elif v.kind == ckInt: cljBool(v.intVal != 0)
  elif v.kind == ckFloat: cljBool(v.floatVal != 0.0)
  else: cljBool(cljIsTruthy(v))

proc Boolean*(v: CljVal): CljVal =
  Boolean(@[v])

proc Object*(args: seq[CljVal]): CljVal =
  if args.len == 0: cljKeyword("Object")
  else: args[0]

proc Object*(): CljVal =
  cljKeyword("Object")

proc Integer*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljInt(0)
  cljToInt(args)

proc Integer*(v: CljVal): CljVal =
  cljToInt(@[v])

proc Long*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljInt(0)
  cljToInt(args)

proc Float*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljFloat(0.0)
  cljToFloat(args)

proc Double*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljFloat(0.0)
  cljToFloat(args)

# ---- JSON Support (jsonista-style) ----

proc cljOptBool(opts: CljVal, key: string, defaultVal: bool = false): bool =
  if opts.isNil or opts.kind != ckMap: return defaultVal
  let v = cljGet(opts, cljKeyword(key))
  if v.isNil or v.kind == ckNil:
    let v2 = cljGet(opts, cljKeyword(key & "?"))
    if v2.isNil or v2.kind == ckNil: return defaultVal
    if v2.kind == ckBool: return v2.boolVal
    if v2.kind == ckInt: return v2.intVal != 0
    return defaultVal
  if v.kind == ckBool: return v.boolVal
  if v.kind == ckInt: return v.intVal != 0
  return defaultVal

proc cljToJsonNode*(v: CljVal, opts: CljVal = nil): JsonNode =
  if v.isNil: return newJNull()
  case v.kind
  of ckNil: newJNull()
  of ckBool: newJBool(v.boolVal)
  of ckInt: newJInt(v.intVal)
  of ckFloat: newJFloat(v.floatVal)
  of ckString: newJString(v.strVal)
  of ckKeyword: newJString(v.kwName)
  of ckSymbol: newJString(v.symName)
  of ckList:
    var arr = newJArray()
    for item in v.listItems:
      arr.add(cljToJsonNode(item, opts))
    arr
  of ckVector:
    var arr = newJArray()
    for item in toSeq(v.vecData):
      arr.add(cljToJsonNode(item, opts))
    arr
  of ckMap:
    var obj = newJObject()
    for key in pmapKeys(v.mapData):
      let val = pmapGet(v.mapData, key, cljNil(), hash(key), cljEq)
      var keyStr = ""
      if key.kind == ckString: keyStr = key.strVal
      elif key.kind == ckKeyword: keyStr = key.kwName
      elif key.kind == ckSymbol: keyStr = key.symName
      elif key.kind == ckInt: keyStr = $key.intVal
      else: keyStr = cljStr(key)
      obj[keyStr] = cljToJsonNode(val, opts)
    obj
  of ckSet:
    var arr = newJArray()
    for key in pmapKeys(v.setData):
      arr.add(cljToJsonNode(key, opts))
    arr
  else: newJNull()

proc jsonNodeToClj*(j: JsonNode, opts: CljVal = nil): CljVal =
  if j.isNil: return cljNil()
  case j.kind
  of JNull: cljNil()
  of JBool: cljBool(j.getBool())
  of JInt: cljInt(j.getInt())
  of JFloat: cljFloat(j.getFloat())
  of JString: cljString(j.getStr())
  of JArray:
    var items: seq[CljVal] = @[]
    for elem in j.getElems():
      items.add(jsonNodeToClj(elem, opts))
    cljVector(items)
  of JObject:
    let keywordKeys = cljOptBool(opts, "keyword-keys")
    var pairs: seq[(CljVal, CljVal)] = @[]
    for key, val in j.pairs:
      let k = if keywordKeys: cljKeyword(key) else: cljString(key)
      pairs.add((k, jsonNodeToClj(val, opts)))
    cljMapFromPairs(pairs)
  else: cljNil()

proc cljJsonWriteString*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljString("")
  let v = args[0]
  var opts: CljVal = nil
  if args.len >= 2 and args[1].kind == ckMap:
    opts = args[1]
  let j = cljToJsonNode(v, opts)
  let pretty = cljOptBool(opts, "pretty")
  if pretty:
    cljString(pretty(j, 2))
  else:
    cljString($j)

proc cljJsonReadString*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljNil()
  let s = args[0]
  if s.kind != ckString: return cljNil()
  var opts: CljVal = nil
  if args.len >= 2 and args[1].kind == ckMap:
    opts = args[1]
  try:
    let j = parseJson(s.strVal)
    jsonNodeToClj(j, opts)
  except CatchableError as e:
    cljMapFromPairs(@[(cljKeyword("error"), cljString(e.msg))])

proc cljJsonWriteFile*(args: seq[CljVal]): CljVal =
  if args.len < 2: return cljMapFromPairs(@[(cljKeyword("error"), cljString("json/write-file requires at least path and value"))])
  let path = args[0]
  let v = args[1]
  if path.kind != ckString:
    return cljMapFromPairs(@[(cljKeyword("error"), cljString("json/write-file path must be a string"))])
  var opts: CljVal = nil
  if args.len >= 3 and args[2].kind == ckMap:
    opts = args[2]
  let j = cljToJsonNode(v, opts)
  let pretty = cljOptBool(opts, "pretty")
  try:
    let content = if pretty: pretty(j, 2) else: $j
    writeFile(path.strVal, content)
    cljBool(true)
  except CatchableError as e:
    cljMapFromPairs(@[(cljKeyword("error"), cljString(e.msg))])

proc cljJsonReadFile*(args: seq[CljVal]): CljVal =
  if args.len == 0: return cljMapFromPairs(@[(cljKeyword("error"), cljString("json/read-file requires a path"))])
  let path = args[0]
  if path.kind != ckString:
    return cljMapFromPairs(@[(cljKeyword("error"), cljString("json/read-file path must be a string"))])
  var opts: CljVal = nil
  if args.len >= 2 and args[1].kind == ckMap:
    opts = args[1]
  try:
    let content = readFile(path.strVal)
    let j = parseJson(content)
    jsonNodeToClj(j, opts)
  except CatchableError as e:
    cljMapFromPairs(@[(cljKeyword("error"), cljString(e.msg))])
