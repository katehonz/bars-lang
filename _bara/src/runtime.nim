import hashes

const
  Bits = 5
  Width = 1 shl Bits  # 32
  Mask = Width - 1

type
  CljKind* = enum
    ckNil, ckBool, ckInt, ckFloat, ckString, ckKeyword, ckSymbol,
    ckList, ckVector, ckMap, ckSet, ckFn, ckAtom, ckTransient, ckAgent

  CljVal* = ref CljValObj
  CljValObj = object
    case kind*: CljKind
    of ckNil: discard
    of ckBool: boolVal*: bool
    of ckInt: intVal*: int64
    of ckFloat: floatVal*: float64
    of ckString: strVal*: string
    of ckKeyword: kwName*: string
    of ckSymbol: symName*: string
    of ckList: listItems*: seq[CljVal]
    of ckVector: vecRoot*: VecNode
    of ckMap: mapRoot*: MapNode
    of ckFn: fnProc*: proc(args: seq[CljVal]): CljVal
    of ckAtom: atomVal*: CljVal

  VecNodeKind = enum vnLeaf, vnInternal
  VecNode = ref object
    case kind: VecNodeKind
    of vnLeaf:
      leaf: array[Width, CljVal]
    of vnInternal:
      children: array[Width, VecNode]

  PersistentVector* = object
    count*: int
    shift*: int
    root*: VecNode
    tail*: seq[CljVal]
    tailLen*: int

  MapNodeKind = enum mnLeaf, mnInternal, mnCollision
  MapNode = ref object
    case kind: MapNodeKind
    of mnLeaf:
      leafKey*: CljVal
      leafVal*: CljVal
    of mnInternal:
      bitmap*: uint32
      children*: seq[MapNode]
    of mnCollision:
      collHash*: Hash
      collPairs*: seq[(CljVal, CljVal)]

  PersistentMap* = object
    count*: int
    root*: MapNode
    hasLeaf*: bool
    rootLeaf*: MapNode

# ---- Constructors ----

proc cljNil*(): CljVal = CljVal(kind: ckNil)
proc cljBool*(v: bool): CljVal = CljVal(kind: ckBool, boolVal: v)
proc cljInt*(v: int64): CljVal = CljVal(kind: ckInt, intVal: v)
proc cljInt*(v: int): CljVal = CljVal(kind: ckInt, intVal: v.int64)
proc cljFloat*(v: float64): CljVal = CljVal(kind: ckFloat, floatVal: v)
proc cljString*(v: string): CljVal = CljVal(kind: ckString, strVal: v)
proc cljKeyword*(v: string): CljVal = CljVal(kind: ckKeyword, kwName: v)
proc cljSymbol*(v: string): CljVal = CljVal(kind: ckSymbol, symName: v)
proc cljFn*(p: proc(args: seq[CljVal]): CljVal): CljVal = CljVal(kind: ckFn, fnProc: p)

proc emptyVecNode(): VecNode = VecNode(kind: vnLeaf)
proc emptyMapNode(): MapNode = MapNode(kind: mnInternal, bitmap: 0, children: @[])

# ---- CljVal helpers ----

proc cljValHash*(v: CljVal): Hash =
  case v.kind
  of ckNil: hash(0)
  of ckBool: hash(v.boolVal)
  of ckInt: hash(v.intVal)
  of ckFloat: hash(v.floatVal)
  of ckString: hash(v.strVal)
  of ckKeyword: hash(v.kwName) !& hash(":kw")
  of ckSymbol: hash(v.symName)
  else: hash(cast[uint](v))

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

# ---- Persistent Vector (HAMT) ----

proc newPersistentVector*(): PersistentVector =
  PersistentVector(count: 0, shift: Bits, root: emptyVecNode(), tail: @[], tailLen: 0)

proc tailOff(count: int): int =
  if count < Width: 0
  else: ((count - 1) shr Bits) shl Bits

proc vecPush(v: PersistentVector, val: CljVal): PersistentVector =
  if v.count - tailOff(v.count) < Width:
    # room in tail
    var newTail = v.tail
    newTail.add(val)
    return PersistentVector(count: v.count + 1, shift: v.shift, root: v.root, tail: newTail, tailLen: v.tailLen + 1)
  # tail full, push into tree
  let tailNode = VecNode(kind: vnLeaf, leaf: block:
    var arr: array[Width, CljVal]
    for i in 0..<v.tailLen: arr[i] = v.tail[i]
    arr)
  var newShift = v.shift
  var newRoot = v.root
  if (v.count shr Bits) > (1 shl v.shift):
    var newRootN = VecNode(kind: vnInternal)
    newRootN.children[0] = v.root
    newRootN.children[1] = tailNode
    newRoot = newRootN
    newShift += Bits
  else:
    # insert tail into tree
    proc insertTail(node: VecNode, level: int, parentBitmap: uint32): VecNode =
      discard
    # simplified: just create leaf for now
    newRoot = v.root
  var newTailSeq = @[val]
  return PersistentVector(count: v.count + 1, shift: newShift, root: newRoot, tail: newTailSeq, tailLen: 1)

proc vecGet(v: PersistentVector, idx: int): CljVal =
  if idx < 0 or idx >= v.count:
    raise newException(IndexDefect, "Index out of range: " & $idx)
  let to = tailOff(v.count)
  if idx >= to:
    return v.tail[idx - to]
  var node = v.root
  var level = v.shift
  while level > 0:
    node = node.children[(idx shr level) and Mask]
    level -= Bits
  return node.leaf[idx and Mask]

# ---- Simplified seq-based persistent vector ----
# For now use Nim seq with copy-on-write semantics via wrapper

type
  CljVec* = ref object
    data*: seq[CljVal]

  CljMap* = ref object
    keys*: seq[CljVal]
    vals*: seq[CljVal]

proc newCljVec*(): CljVec = CljVec(data: @[])
proc newCljVec*(items: seq[CljVal]): CljVec = CljVec(data: items)

proc cljVecLen*(v: CljVec): int = v.data.len
proc cljVecGet*(v: CljVec, i: int): CljVal =
  if i < 0 or i >= v.data.len:
    raise newException(IndexDefect, "Index out of range: " & $i)
  v.data[i]

proc cljVecConj*(v: CljVec, val: CljVal): CljVec =
  var newData = v.data
  newData.add(val)
  newCljVec(newData)

proc cljVecAssoc*(v: CljVec, i: int, val: CljVal): CljVec =
  var newData = v.data
  if i == newData.len:
    newData.add(val)
  elif i >= 0 and i < newData.len:
    newData[i] = val
  else:
    raise newException(IndexDefect, "Index out of range: " & $i)
  newCljVec(newData)

proc newCljMap*(): CljMap = CljMap(keys: @[], vals: @[])

proc cljMapGet*(m: CljMap, key: CljVal): CljVal =
  for i in 0..<m.keys.len:
    if m.keys[i] == key:
      return m.vals[i]
  return cljNil()

proc cljMapAssoc*(m: CljMap, key: CljVal, val: CljVal): CljMap =
  var newKeys = m.keys
  var newVals = m.vals
  for i in 0..<newKeys.len:
    if newKeys[i] == key:
      newVals[i] = val
      return CljMap(keys: newKeys, vals: newVals)
  newKeys.add(key)
  newVals.add(val)
  CljMap(keys: newKeys, vals: newVals)

proc cljMapDissoc*(m: CljMap, key: CljVal): CljMap =
  var newKeys: seq[CljVal] = @[]
  var newVals: seq[CljVal] = @[]
  for i in 0..<m.keys.len:
    if m.keys[i] != key:
      newKeys.add(m.keys[i])
      newVals.add(m.vals[i])
  CljMap(keys: newKeys, vals: newVals)

proc cljMapContains*(m: CljMap, key: CljVal): bool =
  for i in 0..<m.keys.len:
    if m.keys[i] == key:
      return true
  false

proc cljMapCount*(m: CljMap): int = m.keys.len

proc cljMapKeys*(m: CljMap): seq[CljVal] = m.keys
proc cljMapVals*(m: CljMap): seq[CljVal] = m.vals

# ---- String display ----

proc cljRepr*(v: CljVal): string =
  if v.isNil: return "nil"
  case v.kind
  of ckNil: "nil"
  of ckBool: $v.boolVal
  of ckInt: $v.intVal
  of ckFloat: $v.floatVal
  of ckString: "\"" & v.strVal & "\""
  of ckKeyword: ":" & v.kwName
  of ckSymbol: v.symName
  of ckList: "(" & v.listItems.mapIt(cljRepr(it)).join(" ") & ")"
  of ckVector: "[" & v.listItems.mapIt(cljRepr(it)).join(" ") & "]"
  of ckMap: "{not-implemented}"
  of ckFn: "#<fn>"
  of ckAtom: "(atom " & cljRepr(v.atomVal) & ")"

proc cljStr*(v: CljVal): string =
  if v.isNil: return ""
  case v.kind
  of ckString: v.strVal
  of ckKeyword: ":" & v.kwName
  of ckSymbol: v.symName
  else: cljRepr(v)
