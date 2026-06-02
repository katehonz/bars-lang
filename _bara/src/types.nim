# Bara Lang Value Types (Compiler internal representation)
import sequtils, strutils

type
  CljKind* = enum
    ckNil, ckBool, ckInt, ckFloat, ckString, ckKeyword, ckSymbol,
    ckList, ckVector, ckMap, ckSet, ckFn, ckAtom, ckTransient, ckAgent

  CljVal* = ref object
    meta*: CljVal
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
    of ckFn:
      fnName*: string
      fnBody*: seq[CljVal]
    of ckAtom: atomVal*: CljVal
    of ckTransient:
      transKind*: CljKind
      transVec*: seq[CljVal]
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

proc cljSet*(items: seq[CljVal]): CljVal = CljVal(kind: ckSet, setItems: items)
proc cljFn*(name: string, body: seq[CljVal]): CljVal = CljVal(kind: ckFn, fnName: name, fnBody: body)
proc cljAtom*(val: CljVal): CljVal = CljVal(kind: ckAtom, atomVal: val)
proc cljTransient*(kind: CljKind): CljVal = CljVal(kind: ckTransient, transKind: kind)
proc cljAgent*(val: CljVal): CljVal = CljVal(kind: ckAgent, agentVal: val)

proc cljMapFromPairs*(pairs: seq[(CljVal, CljVal)]): CljVal =
  var ks: seq[CljVal] = @[]
  var vs: seq[CljVal] = @[]
  for (k, v) in pairs:
    ks.add(k)
    vs.add(v)
  cljMap(ks, vs)

proc `$`*(v: CljVal): string =
  if v.isNil: return "nil"
  case v.kind
  of ckNil: "nil"
  of ckBool: $v.boolVal
  of ckInt: $v.intVal
  of ckFloat: $v.floatVal
  of ckString: "\"" & v.strVal & "\""
  of ckKeyword: ":" & v.kwName
  of ckSymbol: v.symName
  of ckList: "(" & v.items.mapIt($it).join(" ") & ")"
  of ckVector: "[" & v.items.mapIt($it).join(" ") & "]"
  of ckMap:
    var parts: seq[string] = @[]
    for i in 0..<v.mapKeys.len:
      parts.add($v.mapKeys[i] & " " & $v.mapVals[i])
    "{" & parts.join(", ") & "}"
  of ckSet: "#{" & v.setItems.mapIt($it).join(" ") & "}"
  of ckFn: "#<fn:" & v.fnName & ">"
  of ckAtom: "(atom " & $v.atomVal & ")"
  of ckTransient: "#<transient:" & $v.transKind & ">"
  of ckAgent: "(agent " & $v.agentVal & ")"
