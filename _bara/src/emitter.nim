# Bara Lang → Nim Emitter
import strutils, sets, sequtils, tables
import types
import macros

var requiredImports* = initHashSet[string]()
var emitLibMode* = false
var emitEntryProcName* = ""
var loopStack*: seq[seq[string]] = @[]
var nsAliases*: seq[(string, string)] = @[]  # (alias, namespace)
var scopeStack*: seq[HashSet[string]] = @[]
var definedGlobals*: HashSet[string] = initHashSet[string]()
var multiArityFns*: HashSet[string] = initHashSet[string]()
var definedFnArities*: Table[string, int] = initTable[string, int]()  # -1 = multi-arity/rest
var loopResultVar*: string = ""  # Set by loop handler when result capture is needed

# Runtime functions that accept seq[CljVal] (variadic wrapper signature)
let variadicRuntimeFns* = ["+", "-", "*", "/", "=", ">", "<", ">=", "<=", "not=",
                           "println", "prn", "print", "str", "pr-str",
                           "atom", "concat", "min", "max", "merge", "interleave",
                           "zipmap", "hash-map", "hash-set", "sorted-map", "sorted-map-by", "sorted-set", "sorted-set-by", "cons", "use-fixtures", "vswap!", "swap!", "tap>", "add-tap", "remove-tap", "add-watch", "remove-watch", "alter-var-root",
                           "array-map", "inf", "nan", "list",
                           "float", "int", "double", "long", "short", "byte",
                           "boolean", "num", "number",
                           "make-hierarchy", "derive", "underive", "ancestors",
                           "descendants", "parents", "isa?", "promise", "create-ns", "future",
                           "delay",
                           "aclone", "alength", "aget", "int-array", "identical?", "empty", "identity",
                           "conj",
                           "drop-last", "shuffle", "repeatedly", "fnil", "intern",
                           "println-str", "prn-str", "binding", "aset",
                           "volatile!", "deliver", "doall", "dorun",
                           "to-array", "into-array", "vector", "rand", "rand-int",
                           "rand-nth", "random-sample",
                           "assoc", "dissoc", "get", "get-in", "update", "assoc-in",
                           "contains?", "select-keys", "keys", "vals",
                           "disj", "peek", "pop",
                           "transduce", "ex-info",
                           "compare", "subvec",
                           "require", "eval", "resolve", "random-uuid",
                           "vreset!", "restart-agent", "with-out-str",
                           "System/getProperty",
                           "dosync", "alter"]

proc registerGlobal*(name: string) =
  definedGlobals.incl(name)

proc mangleName*(name: string): string
proc runtimeName(op: string): string

proc registerFn*(name: string, arity: int) =
  definedFnArities[name] = arity

proc emitFnWrapper*(name: string): string =
  ## Emit a cljFn wrapper for a user-defined function when used as a value.
  let rtName = runtimeName(name)
  if rtName.len > 0:
    # Built-in runtime function — emit variadic wrapper if applicable
    if name in variadicRuntimeFns:
      return "cljFn(" & rtName & ")"
    else:
      return "cljFn(proc(args: seq[CljVal]): CljVal = " & rtName & "(args[0]))"
  let mangled = mangleName(name)
  if name in multiArityFns:
    # Multi-arity / rest params already take seq[CljVal]
    return "cljFn(" & mangled & ")"
  elif definedFnArities.hasKey(name):
    let arity = definedFnArities[name]
    if arity == 0:
      return "cljFn(proc(args: seq[CljVal]): CljVal = " & mangled & "())"
    else:
      var argRefs: seq[string] = @[]
      for i in 0..<arity:
        argRefs.add("args[" & $i & "]")
      return "cljFn(proc(args: seq[CljVal]): CljVal = " & mangled & "(" & argRefs.join(", ") & "))"
  else:
    return mangled

proc clearGlobals*() =
  definedGlobals = initHashSet[string]()
  definedFnArities = initTable[string, int]()

proc setNsAliases*(aliases: seq[(string, string)]) =
  nsAliases = aliases

var libNsPrefixes*: seq[string] = @[]

proc setLibNsPrefixes*(prefixes: seq[string]) =
  libNsPrefixes = prefixes

proc sanitizeNimIdent*(name: string): string

proc nsToNimModuleName(ns: string): string =
  result = "lib_"
  for c in ns:
    case c
    of '.', '-': result.add('_')
    of 'a'..'z', 'A'..'Z', '0'..'9', '_': result.add(c)
    else: result.add('_')

proc resolveNsAlias*(name: string): string =
  # Resolve mu/square -> square (strip namespace prefix if alias exists)
  let slashIdx = name.find('/')
  if slashIdx < 0: return name
  let prefix = name[0..<slashIdx]
  let suffix = name[slashIdx+1..^1]
  for (alias, ns) in nsAliases:
    if prefix == alias:
      if prefix in libNsPrefixes:
        # Return fully qualified name for lib module symbols
        return nsToNimModuleName(ns) & ".clj_" & sanitizeNimIdent(suffix)
      return suffix
  return name

type
  EmitterError* = object of CatchableError

proc sanitizeNimIdent*(name: string): string =
  ## Sanitize a string to be a valid Nim identifier, without the clj_ prefix.
  result = ""
  for c in name:
    case c
    of '-': result.add('_')
    of '?': result.add("_Q")
    of '!': result.add("_B")
    of '*': result.add("_STAR_")
    of '+': result.add("_PLUS_")
    of '/': result.add("_SLASH_")
    of '=': result.add("_EQ_")
    of '>': result.add("_GT_")
    of '<': result.add("_LT_")
    of '.': result.add('_')
    of '\'': result.add("_QUOTE_")
    of '&': result.add("_AMP_")
    of '#': result.add("_HASH")
    of '%': result.add("pct")
    else: result.add(c)
  # Nim rejects trailing underscores
  while result.len > 0 and result[^1] == '_':
    result = result[0..^2]
  # Nim rejects double underscores in identifiers
  while result.find("__") != -1:
    result = result.replace("__", "_")
  # Nim 2.x only allows bare `_` as identifier starting with underscore
  if result.len > 1 and result[0] == '_':
    result = "x" & result
  # Nim identifiers cannot start with a digit
  if result.len > 0 and result[0] in {'0'..'9'}:
    result = "x" & result
  if result.len == 0:
    result = "val"
  # Avoid conflicts with runtime functions: all-uppercase short names (GET, POST, etc)
  # get a suffix so they don't collide with cljGet, cljSet, etc.
  if result.len > 0 and result.allCharsInSet({'A'..'Z', '_'}) and result.len <= 7:
    result.add("X")
  # Nim keywords that would clash
  let nimKeywords = ["in", "out", "var", "let", "proc", "func", "type", "ref", "ptr",
                     "object", "method", "template", "macro", "iterator", "converter",
                     "discard", "return", "break", "continue", "if", "else", "elif",
                     "when", "case", "of", "for", "while", "try", "except", "finally",
                     "raise", "import", "export", "from", "include", "using", "bind",
                     "mixin", "asm", "defer", "block", "static", "yield", "assert",
                     "do", "enum", "tuple", "shared", "guard", "concept", "distinct",
                     "interface", "lambda", "open", "quit", "result", "nil", "end"]
  if result in nimKeywords:
    result = result & "1"

proc mangleName*(name: string): string =
  result = "clj_" & sanitizeNimIdent(name)

proc pushScope() =
  scopeStack.add(initHashSet[string]())

proc popScope() =
  if scopeStack.len > 0:
    discard scopeStack.pop()

proc addToScope(name: string) =
  if scopeStack.len > 0:
    scopeStack[^1].incl(name)

proc isLocalVar(name: string): bool =
  for s in scopeStack:
    if name in s:
      return true
  return false

proc emitExpr*(v: CljVal, indent: int = 0, needsValue: bool = false): string
proc emitBlock*(items: seq[CljVal], indent: int, useResult: bool = false): string
proc emitQuotedForm*(v: CljVal): string
proc emitFnAsProc*(items: seq[CljVal], indent: int): string

proc indentStr(indent: int): string =
  "  ".repeat(indent)

proc indentCode(code: string, extra: int): string =
  if extra <= 0: return code
  let prefix = indentStr(extra)
  var res = ""
  var lines = code.split("\n")
  for i, line in lines:
    if i > 0: res.add("\n")
    if line.len > 0:
      res.add(prefix & line)
    else:
      res.add(line)
  return res

proc runtimeName(op: string): string =
  case op
  of "+": "cljAdd"
  of "-": "cljSub"
  of "*": "cljMul"
  of "/": "cljDiv"
  of "=": "cljMultiEqual"
  of "==": "cljNumEq"
  of ">": "cljGt"
  of "<": "cljLt"
  of ">=": "cljGe"
  of "<=": "cljLe"
  of "not=": "cljNotEq"
  of "not": "cljNot"
  of "println": "cljPrintln"
  of "prn": "cljPrn"
  of "str": "cljStrConcat"
  of "pr-str": "cljPrStrConcat"
  of "inc": "cljInc"
  of "dec": "cljDec"
  of "zero?": "cljZero"
  of "pos?": "cljPos"
  of "neg?": "cljNeg"
  of "even?": "cljEven"
  of "odd?": "cljOdd"
  of "first": "cljFirst"
  of "second": "cljSecond"
  of "ffirst": "cljFfirst"
  of "nfirst": "cljNfirst"
  of "rest": "cljRest"
  of "next": "cljNext"
  of "last": "cljLast"
  of "nth": "cljNth"
  of "count": "cljCount"
  of "conj": "cljConj"
  of "cons": "cljCons"
  of "seq": "cljSeq"
  of "vec": "cljVec"
  of "empty?": "cljEmpty"
  of "concat": "cljConcat"
  of "take": "cljTake"
  of "drop": "cljDrop"
  of "reverse": "cljReverse"
  of "sort": "cljSort"
  of "distinct": "cljDistinct"
  of "flatten": "cljFlatten"
  of "partition": "cljPartition"
  of "frequencies": "cljFrequencies"
  of "get": "cljGet"
  of "get-in": "cljGetIn"
  of "assoc": "cljAssoc"
  of "dissoc": "cljDissoc"
  of "keys": "cljKeys"
  of "vals": "cljVals"
  of "contains?": "cljContains"
  of "select-keys": "cljSelectKeys"
  of "merge": "cljMerge"
  of "hash-map": "cljHashMap"
  of "hash-set": "cljHashSet"
  of "identity": "cljIdentity"
  of "type": "cljType"
  of "abs": "cljAbs"
  of "mod": "cljMod"
  of "min": "cljMin"
  of "max": "cljMax"
  of "apply": "cljApply"
  of "atom": "cljAtom"
  of "deref": "cljDeref"
  of "reset!": "cljReset"
  of "swap!": "cljSwap"
  of "zipmap": "cljZipmap"
  of "object-array": "cljObjectArray"
  of "sorted-map": "cljSortedMap"
  of "sorted-map-by": "cljSortedMapBy"
  of "sorted-set": "cljSortedSet"
  of "sorted-set-by": "cljSortedSetBy"
  of "sorted?": "cljSortedQ"
  of "use-fixtures": "cljUseFixtures"
  of "transduce": "cljTransduce"
  of "vswap!": "cljVswap"
  of "split": "cljStrSplit"
  of "str/split": "cljStrSplit"
  of "add-watch": "cljAddWatch"
  of "remove-watch": "cljRemoveWatch"
  of "ex-info": "cljExInfo"
  of "ex-data": "cljExData"
  of "alter-var-root": "cljAlterVarRoot"
  of "force": "cljForce"
  of "sleep": "cljSleep"
  of "tap>": "cljTap"
  of "future-cancel": "cljFutureCancel"
  of "add-tap": "cljAddTap"
  of "remove-tap": "cljRemoveTap"
  of "array-map": "cljArrayMap"
  of "rseq": "cljRseq"
  of "list": "cljListEmpty"
  # ---- Type predicates ----
  of "nil?": "cljIsNilP"
  of "some?": "cljIsSome"
  of "keyword?": "cljIsKeyword"
  of "symbol?": "cljIsSymbol"
  of "string?": "cljIsString"
  of "number?": "cljIsNumber"
  of "integer?": "cljIsInteger"
  of "float?": "cljIsFloat"
  of "vector?": "cljIsVector"
  of "map?": "cljIsMap"
  of "set?": "cljIsSet"
  of "list?": "cljIsList"
  of "seq?": "cljIsSeq"
  of "coll?": "cljIsColl"
  of "sequential?": "cljIsSequential"
  of "fn?": "cljIsFn"
  of "boolean?": "cljIsBool"
  of "true?": "cljIsTrueP"
  of "false?": "cljIsFalseP"
  # ---- Keyword/Symbol ops ----
  of "keyword": "cljKeywordFn"
  of "symbol": "cljSymbolFn"
  of "inf": "cljInf"
  of "nan": "cljNaN"
  of "NaN?": "cljNaNQ"
  of "name": "cljName"
  of "namespace": "cljNamespace"
  # of "key": "cljKey"
  # of "val": "cljEntryVal"
  # ---- File operations ----
  of "file/read": "cljFileRead"
  of "file/write": "cljFileWrite"
  of "file/append": "cljFileAppend"
  of "file/ls": "cljFileLs"
  of "file/exists?": "cljFileExists"
  # ---- Git operations ----
  of "git/status": "cljGitStatus"
  of "git/commit": "cljGitCommit"
  of "git/push": "cljGitPush"
  of "git/diff": "cljGitDiff"
  of "git/log": "cljGitLog"
  # ---- clojure.string operations ----
  of "clojure.string/split": "cljStrSplit"
  of "clojure.string/lower-case": "cljStrLower"
  of "clojure.string/upper-case": "cljStrUpper"
  of "clojure.string/trim": "cljStrTrim"
  of "clojure.string/join": "cljStrJoin"
  of "clojure.string/replace": "cljStrReplace"
  of "clojure.string/includes?": "cljStrIncludes"
  of "clojure.string/starts-with?": "cljStrStartsWith"
  of "clojure.string/ends-with?": "cljStrEndsWith"
  of "clojure.string/blank?": "cljStrBlank"
  of "clojure.string/reverse": "cljStrReverse"
  of "disj": "cljDisj"
  of "peek": "cljPeek"
  of "pop": "cljPop"
  of "slurp": "cljFileRead"
  of "spit": "cljFileWrite"
  of "read-line": "cljReadLine"
  of "repeat": "cljRepeat"
  of "cycle": "cljCycle"
  of "iterate": "cljIterate"
  of "interleave": "cljInterleave"
  of "quot": "cljQuot"
  of "rem": "cljRem"
  of "instance?": "cljInstanceP"
  of "meta": "cljMeta"
  of "with-meta": "cljWithMeta"
  of "transient": "cljTransient"
  of "persistent!": "cljPersistent"
  of "conj!": "cljConjB"
  of "assoc!": "cljAssocB"
  # ---- Agent operations ----
  of "agent": "cljAgent"
  of "send": "cljAgentSend"
  of "await": "cljAgentAwait"
  of "agent-error": "cljAgentError"
  of "shutdown-agents": "cljAgentShutdown"
  # ---- Channel operations (core.async) ----
  of "chan": "cljChan"
  of "close!": "cljChanClose"
  of "volatile!": "cljVolatileBang"
  of "volatile-mutable": "cljVolatileMutableQ"
  of "deliver": "cljDeliver"
  of "var?": "cljIsVar"
  of "ifn?": "cljIsIfn"
  of "parse-uuid": "cljParseUuid"
  of "uuid?": "cljIsUuid"
  of "ancestors": "cljAncestors"
  of "descendants": "cljDescendants"
  of "parents": "cljParents"
  of "isa?": "cljIsa"
  of "promise": "cljPromise"
  of "future": "cljFuture"
  of "delay": "cljDelay"
  of "create-ns": "cljCreateNs"
  of "aclone": "cljAclone"
  of "alength": "cljAlength"
  of "aget": "cljAget"
  of "int-array": "cljIntArray"
  of "identical?": "cljIdentical"
  of "empty": "cljEmptyColl"
  of "doall": "cljDoall"
  of "dorun": "cljDorun"
  of "drop-last": "cljDropLast"
  of "shuffle": "cljShuffle"
  of "fnil": "cljFnil"
  of "intern": "cljIntern"
  of "to-array": "cljToArray"
  of "into-array": "cljIntoArray"
  of "repeatedly": "cljRepeatedly"
  of "make-hierarchy": "cljMakeHierarchy"
  of "derive": "cljDerive"
  of "underive": "cljUnderive"
  of "println-str": "cljPrintlnStr"
  of "prn-str": "cljPrnStr"
  of "binding": "cljBinding"
  of "aset": "cljAset"
  of "vector": "cljVectorFn"
  of "compare": "cljCompare"
  of "subvec": "cljSubvec"
  of "rand": "cljRand"
  of "rand-int": "cljRandInt"
  of "rand-nth": "cljRandNth"
  of "random-sample": "cljRandomSample"
  # ---- Type conversion ----
  of "float": "cljToFloat"
  of "int": "cljToInt"
  of "double": "cljToFloat"
  of "long": "cljToInt"
  of "short": "cljToInt"
  of "byte": "cljToInt"
  of "boolean": "cljToBool"
  of "num": "cljToInt"
  of "number": "cljToInt"
  of "int?": "cljIsInteger"
  of "Thread/sleep": "cljSleep"
  of "System/getProperty": "cljSystemGetProperty"
  of "random-uuid": "cljRandomUuid"
  of "vreset!": "cljVresetB"
  of "restart-agent": "cljRestartAgent"
  of "with-out-str": "cljWithOutStr"
  of "require": "cljRequire"
  of "eval": "cljEvalStub"
  of "resolve": "cljResolve"
  # ---- STM ref operations ----
  of "ref": "cljRef"
  of "ref-set": "cljRefSet"
  of "dosync": "cljDosync"
  of "alter": "cljAlter"
  # ---- JSON operations (jsonista-style) ----
  of "json/write-value-as-string": "cljJsonWriteString"
  of "json/read-value": "cljJsonReadString"
  of "json/write-value-to-file": "cljJsonWriteFile"
  of "json/read-value-from-file": "cljJsonReadFile"
  else: ""

proc emitFnAsProc(items: seq[CljVal], indent: int): string =
  # Emit a fn form as a raw proc (without cljFn wrapper), used by def handler
  if items.len < 2:
    raise newException(EmitterError, "fn requires params")
  var paramsIdx = 1
  if items[1].kind == ckSymbol:
    paramsIdx = 2
  if paramsIdx >= items.len:
    raise newException(EmitterError, "fn requires params and body")
  var params = items[paramsIdx]
  if params.kind == ckList and params.items.len == 3 and
     params.items[0].kind == ckSymbol and params.items[0].symName == "with-meta":
    params = params.items[1]
  if params.kind != ckVector:
    raise newException(EmitterError, "fn params must be a vector")
  var paramNames: seq[string] = @[]
  pushScope()
  for p in params.items:
    if p.kind != ckSymbol:
      raise newException(EmitterError, "fn params must be symbols")
    addToScope(p.symName)
    paramNames.add(mangleName(p.symName) & ": CljVal")
  let body = items[(paramsIdx+1)..^1]
  var bodyCode = ""
  if body.len == 1:
    bodyCode = emitExpr(body[0], indent + 1)
  else:
    bodyCode = emitBlock(body, indent + 1)
  popScope()
  let sp = indentStr(indent)
  if bodyCode.find("\n") == -1:
    return sp & "(proc (" & paramNames.join(", ") & "): CljVal = " & bodyCode.strip() & ")"
  else:
    return sp & "(proc (" & paramNames.join(", ") & "): CljVal =\n" & bodyCode & ")"

proc letDestructuredBindings(bindings: CljVal): CljVal =
  # Expand let bindings with vector/map destructuring into simple symbol bindings
  if bindings.kind != ckVector:
    return bindings
  var res: seq[CljVal] = @[]
  var i = 0
  while i < bindings.items.len:
    let bname = bindings.items[i]
    let bval = bindings.items[i+1]
    if bname.kind == ckSymbol:
      res.add(bname)
      res.add(bval)
    elif bname.kind == ckVector:
      let tmp = cljSymbol("ds_" & $i)
      res.add(tmp)
      res.add(bval)
      for j in 0..<bname.items.len:
        if bname.items[j].kind == ckSymbol:
          res.add(bname.items[j])
          res.add(cljList(@[cljSymbol("nth"), tmp, cljInt(j)]))
    elif bname.kind == ckMap:
      let tmp = cljSymbol("ds_" & $i)
      res.add(tmp)
      res.add(bval)
      var hasAs = false
      var asName: CljVal = nil
      var j = 0
      while j < bname.mapKeys.len:
        let key = bname.mapKeys[j]
        let val = bname.mapVals[j]
        if key.kind == ckKeyword and key.kwName == "keys" and val.kind == ckVector:
          for k in 0..<val.items.len:
            if val.items[k].kind == ckSymbol:
              res.add(val.items[k])
              res.add(cljList(@[cljSymbol("get"), tmp, cljKeyword(val.items[k].symName)]))
        elif key.kind == ckKeyword and key.kwName == "as":
          hasAs = true
          asName = val
        j += 1
      if hasAs and asName != nil and asName.kind == ckSymbol:
        res.add(asName)
        res.add(tmp)
    i += 2
  return cljVector(res)

proc emitSpecialForm(items: seq[CljVal], indent: int, needsValue: bool = false): string =
  let sp = indentStr(indent)
  let head = items[0]
  if head.kind != ckSymbol:
    # (:key map) — keyword as function: lookup key in map
    if head.kind == ckKeyword:
      if items.len == 2:
        return sp & "cljGet(" & emitExpr(items[1], 0) & ", cljKeyword(\"" & head.kwName & "\"))"
      elif items.len == 3:
        return sp & "cljGetDefault(" & emitExpr(items[1], 0) & ", cljKeyword(\"" & head.kwName & "\"), " & emitExpr(items[2], 0) & ")"
    # Head is not a symbol - evaluate as function call: ((fn ...) args...)
    var argParts: seq[string] = @[]
    for i in 1..<items.len:
      argParts.add(emitExpr(items[i], indent, needsValue = true))
    let fnCode = emitExpr(head, 0)
    return sp & "cljApply(" & fnCode & ", cljList(@[" & argParts.join(", ") & "]))"
  let op = resolveNsAlias(head.symName)

  # ---- Special forms (language constructs) ----
  case op
  of "ns":
    # Namespace declaration: (ns my.app (:require [other.lib :as lib]))
    if items.len < 2:
      raise newException(EmitterError, "ns requires a namespace name")
    let nsName = items[1]
    if nsName.kind != ckSymbol:
      raise newException(EmitterError, "ns name must be a symbol")
    var lines: seq[string] = @[]
    lines.add(sp & "# Namespace: " & nsName.symName)
    # Process require clauses — register aliases
    var newAliases: seq[(string, string)] = @[]
    for ri in 2..<items.len:
      let clause = items[ri]
      let isRequire = (clause.kind == ckList and clause.items.len > 0 and
        ((clause.items[0].kind == ckSymbol and clause.items[0].symName == ":require") or
         (clause.items[0].kind == ckKeyword and clause.items[0].kwName == "require")))
      let isImport = (clause.kind == ckList and clause.items.len > 0 and
        ((clause.items[0].kind == ckSymbol and clause.items[0].symName == ":import") or
         (clause.items[0].kind == ckKeyword and clause.items[0].kwName == "import")))
      if isRequire:
        for ci in 1..<clause.items.len:
          let req = clause.items[ci]
          if req.kind == ckVector and req.items.len >= 1:
            let libName = req.items[0]
            if libName.kind == ckSymbol:
              var alias = libName.symName
              # Check for :as
              if req.items.len >= 3 and req.items[1].kind == ckKeyword and req.items[1].kwName == "as":
                if req.items[2].kind == ckSymbol:
                  alias = req.items[2].symName
              # Also check for :refer
              var referNames: seq[string] = @[]
              var ri2 = 1
              while ri2 < req.items.len:
                if req.items[ri2].kind == ckKeyword and req.items[ri2].kwName == "refer":
                  if ri2 + 1 < req.items.len and req.items[ri2+1].kind == ckVector:
                    for rn in req.items[ri2+1].items:
                      if rn.kind == ckSymbol:
                        referNames.add(rn.symName)
                  ri2 += 2
                elif req.items[ri2].kind == ckKeyword and req.items[ri2].kwName in ["as", "refer-macros"]:
                  ri2 += 2
                else:
                  ri2 += 1
              newAliases.add((alias, libName.symName))
              for rn in referNames:
                newAliases.add((rn, rn))
              # Convert namespace to file path: my.app -> my/app
              let filePath = libName.symName.replace(".", "/") & ".clj"
              lines.add(sp & "# require: " & libName.symName & " as " & alias & " from " & filePath)
      if isImport:
        # Skip :import clauses
        discard
    # Merge new aliases with existing
    for (a, ns) in newAliases:
      var found = false
      for (ea, ens) in nsAliases:
        if ea == a:
          found = true
          break
      if not found:
        nsAliases.add((a, ns))
    return lines.join("\n")

  of "defmacro":
    # Register user-defined macro
    if items.len < 4:
      raise newException(EmitterError, "defmacro requires name, params, and body")
    let name = items[1]
    if name.kind != ckSymbol:
      raise newException(EmitterError, "defmacro name must be a symbol")
    let macroName = name.symName
    let macroParams = items[2]
    let macroBody = items[3..^1]
    defineMacro(macroName, proc(args: seq[CljVal]): CljVal =
      # Build env: param name -> arg value
      var env: seq[(string, CljVal)] = @[]
      if macroParams.kind == ckVector:
        for i in 0..<macroParams.items.len:
          if macroParams.items[i].kind == ckSymbol:
            let pName = macroParams.items[i].symName
            if pName == "&":
              if i + 1 < macroParams.items.len:
                let restName = macroParams.items[i+1].symName
                env.add((restName, cljList(args[i..^1])))
              break
            elif i < args.len:
              env.add((pName, args[i]))
      # Mini-evaluator for macro body
      proc eval(form: CljVal): CljVal =
        if form.isNil: return cljNil()
        case form.kind
        of ckSymbol:
          for (n, v) in env:
            if form.symName == n: return v
          return form
        of ckKeyword: return form
        of ckInt: return form
        of ckFloat: return form
        of ckString: return form
        of ckBool: return form
        of ckNil: return form
        of ckVector:
          var newItems: seq[CljVal] = @[]
          for item in form.items:
            newItems.add(eval(item))
          return cljVector(newItems)
        of ckList:
          if form.items.len == 0: return cljList(@[])
          let head = form.items[0]
          if head.kind == ckSymbol:
            let hName = head.symName
            # quote
            if hName == "quote" and form.items.len == 2:
              return form.items[1]
            # syntax-quote
            if hName == "syntax-quote" and form.items.len == 2:
              return eval(expandSyntaxQuote(form.items[1]))
            # list
            if hName == "list":
              var evaluated: seq[CljVal] = @[]
              for i in 1..<form.items.len:
                evaluated.add(eval(form.items[i]))
              return cljList(evaluated)
            # cons
            if hName == "cons" and form.items.len == 3:
              let fst = eval(form.items[1])
              let rst = eval(form.items[2])
              var res = @[fst]
              if rst.kind == ckList:
                res.add(rst.items)
              return cljList(res)
            # concat
            if hName == "concat":
              var res: seq[CljVal] = @[]
              for i in 1..<form.items.len:
                let v = eval(form.items[i])
                if v.kind == ckList:
                  res.add(v.items)
              return cljList(res)
            # vec
            if hName == "vec" and form.items.len == 2:
              let v = eval(form.items[1])
              if v.kind == ckList: return cljVector(v.items)
              return v
            # conj
            if hName == "conj" and form.items.len == 3:
              let coll = eval(form.items[2])
              let item = eval(form.items[1])
              if coll.kind == ckList:
                var newItems = @[item]
                newItems.add(coll.items)
                return cljList(newItems)
              return coll
            # str
            if hName == "str":
              var s = ""
              for i in 1..<form.items.len:
                let v = eval(form.items[i])
                case v.kind
                of ckString: s.add(v.strVal)
                else: s.add($v)
              return cljString(s)
            # Apply: evaluate all items, first must be fn
            var evalItems: seq[CljVal] = @[]
            for item in form.items:
              evalItems.add(eval(item))
            return cljList(evalItems)
          # Non-symbol head: evaluate all
          var evalItems: seq[CljVal] = @[]
          for item in form.items:
            evalItems.add(eval(item))
          return cljList(evalItems)
        else: return form
      # Evaluate body
      if macroBody.len == 1:
        return eval(macroBody[0])
      var resultItems: seq[CljVal] = @[cljSymbol("do")]
      for b in macroBody:
        resultItems.add(eval(b))
      cljList(resultItems)
    )
    return sp & "discard cljNil()"

  of "def":
    if items.len < 3:
      return sp & "cljNil()"
    if items.len > 3:
      # (def name docstring value) or similar - use last arg as value
      let nameItem = items[1]
      var valItem = items[^1]
      if nameItem.kind == ckSymbol:
        let mangled = mangleName(nameItem.symName)
        registerGlobal(nameItem.symName)
        let valCode = emitExpr(valItem, 0, needsValue = true)
        let exportMarker = if emitLibMode: "*" else: ""
        return sp & "let " & mangled & exportMarker & " = " & valCode
      return sp & "cljNil()"
    var name = items[1]
    # Strip metadata: (with-meta sym meta) -> sym
    if name.kind == ckList and name.items.len == 3 and
       name.items[0].kind == ckSymbol and name.items[0].symName == "with-meta":
      name = name.items[1]
    if name.kind != ckSymbol:
      raise newException(EmitterError, "def name must be a symbol")
    let mangled = mangleName(name.symName)
    addToScope(name.symName)
    registerGlobal(name.symName)
    let valForm = items[2]
    # Special handling: (def name (fn ...)) should emit raw proc, not cljFn wrapper
    let isFnDef = valForm.kind == ckList and valForm.items.len > 0 and
                  valForm.items[0].kind == ckSymbol and valForm.items[0].symName == "fn"
    let exportMarker = if emitLibMode: "*" else: ""
    if indent == 0:
      if isFnDef:
        # Emit fn as raw proc for def context
        let oldEmitLibMode = emitLibMode
        emitLibMode = false
        let valCode = emitFnAsProc(valForm.items, 0)
        emitLibMode = oldEmitLibMode
        return sp & "let " & mangled & exportMarker & " = " & valCode
      let valCode = emitExpr(items[2], 0, needsValue = true)
      return sp & "let " & mangled & exportMarker & " = " & valCode
    else:
      # For nested def: use global var so it's accessible from closures
      if isFnDef:
        let oldEmitLibMode = emitLibMode
        emitLibMode = false
        let valCode = emitFnAsProc(valForm.items, indent)
        emitLibMode = oldEmitLibMode
        return sp & "var " & mangled & exportMarker & " = " & valCode.strip() & "\n" & sp & mangled
      let valCode = emitExpr(items[2], indent, needsValue = true)
      return sp & "var " & mangled & exportMarker & " = " & valCode.strip() & "\n" & sp & mangled

  of "defn":
    if items.len < 3:
      raise newException(EmitterError, "defn requires name and params")
    var name = items[1]
    if name.kind == ckList and name.items.len == 3 and
       name.items[0].kind == ckSymbol and name.items[0].symName == "with-meta":
      name = name.items[1]
    if name.kind != ckSymbol:
      raise newException(EmitterError, "defn name must be a symbol")
    registerGlobal(name.symName)
    # Skip docstring if present: (defn name "doc" [params] body...)
    var paramsIdx = 2
    if items.len > 3 and items[2].kind == ckString:
      paramsIdx = 3
    let params = items[paramsIdx]
    # Multi-arity defn: (defn name ([a] ...) ([a b] ...))
    if params.kind == ckList:
      let procName = mangleName(name.symName)
      let exportMarker = if emitLibMode: "*" else: ""
      # Register as multi-arity BEFORE emitting arity bodies (so internal calls wrap correctly)
      multiArityFns.incl(name.symName)
      var arityProcs: seq[string] = @[]
      var dispatchCases: seq[string] = @[]
      for arityIdx in paramsIdx..<items.len:
        let arityForm = items[arityIdx]
        if arityForm.kind == ckList and arityForm.items.len >= 2 and
           arityForm.items[0].kind == ckVector:
          let arityParams = arityForm.items[0]
          let arityBody = arityForm.items[1..^1]
          let paramCount = arityParams.items.len
          var paramNames: seq[string] = @[]
          pushScope()
          for p in arityParams.items:
            if p.kind != ckSymbol:
              raise newException(EmitterError, "defn params must be symbols")
            addToScope(p.symName)
            paramNames.add(mangleName(p.symName) & ": CljVal")
          var bodyCode = ""
          if arityBody.len == 1:
            bodyCode = emitExpr(arityBody[0], indent + 1)
          else:
            bodyCode = emitBlock(arityBody, indent + 1)
          popScope()
          let arityName = procName & "_arity" & $paramCount
          arityProcs.add(sp & "proc " & arityName & "(" & paramNames.join(", ") & "): CljVal =\n" & bodyCode)
          let argCall = (0..<paramCount).mapIt("args[" & $it & "]").join(", ")
          dispatchCases.add(indentStr(indent + 1) & "of " & $paramCount & ": " & arityName & "(" & argCall & ")")
      if arityProcs.len > 0:
        var allLines: seq[string] = @[]
        # Forward declaration for the dispatch proc
        allLines.add(sp & "proc " & procName & exportMarker & "(args: seq[CljVal]): CljVal")
        for ap in arityProcs:
          allLines.add(ap)
        allLines.add(sp & "proc " & procName & exportMarker & "(args: seq[CljVal]): CljVal =")
        allLines.add(indentStr(indent + 1) & "case args.len")
        for dc in dispatchCases:
          allLines.add(dc)
        allLines.add(indentStr(indent + 1) & "else: raise newException(CatchableError, \"Wrong number of args to " & name.symName & "\")")
        # Register as multi-arity so call sites use cljApply
        multiArityFns.incl(name.symName)
        return allLines.join("\n")
    if params.kind != ckVector:
      raise newException(EmitterError, "defn params must be a vector")
    var paramNames: seq[string] = @[]
    var hasRest = false
    var restIdx = -1
    pushScope()
    # First pass: check for & rest params
    for pi, p in params.items:
      if p.kind == ckSymbol and p.symName == "&":
        hasRest = true
        restIdx = pi
        break
    if hasRest:
      # Collect named params before &
      for pi in 0..<restIdx:
        let p = params.items[pi]
        if p.kind != ckSymbol:
          raise newException(EmitterError, "defn params must be symbols")
        addToScope(p.symName)
      # The param after & is the rest param name
      if restIdx + 1 < params.items.len:
        let restParam = params.items[restIdx + 1]
        if restParam.kind != ckSymbol:
          raise newException(EmitterError, "defn rest param must be a symbol")
        addToScope(restParam.symName)
    else:
      for p in params.items:
        if p.kind != ckSymbol:
          raise newException(EmitterError, "defn params must be symbols")
        addToScope(p.symName)
        paramNames.add(mangleName(p.symName) & ": CljVal")
    let body = items[(paramsIdx+1)..^1]
    let procName = mangleName(name.symName)
    let exportMarker = if emitLibMode: "*" else: ""
    if hasRest:
      # Rest params: generate proc with args: seq[CljVal]
      # Register so call sites wrap args in @[...]
      multiArityFns.incl(name.symName)
      registerFn(name.symName, -1)
      let namedCount = restIdx
      var preambleLines: seq[string] = @[]
      for pi in 0..<restIdx:
        let p = params.items[pi]
        preambleLines.add(indentStr(indent + 1) & "let " & mangleName(p.symName) & " = args[" & $pi & "]")
      let restParamName = params.items[restIdx + 1].symName
      preambleLines.add(indentStr(indent + 1) & "let " & mangleName(restParamName) & " = cljList(args[" & $namedCount & "..^1])")
      var bodyCode = ""
      if body.len == 0:
        bodyCode = indentStr(indent + 1) & "cljNil()"
      elif body.len == 1:
        bodyCode = emitExpr(body[0], indent + 1)
      else:
        bodyCode = emitBlock(body, indent + 1)
      popScope()
      let preamble = preambleLines.join("\n")
      return sp & "proc " & procName & exportMarker & "(args: seq[CljVal]): CljVal =\n" & preamble & "\n" & bodyCode
    registerFn(name.symName, paramNames.len)
    if indent == 0:
      var bodyCode = ""
      if body.len == 0:
        bodyCode = indentStr(indent + 1) & "cljNil()"
      elif body.len == 1:
        bodyCode = emitExpr(body[0], indent + 1)
      else:
        bodyCode = emitBlock(body, indent + 1)
      popScope()
      var result = sp & "proc " & procName & exportMarker & "(" & paramNames.join(", ") & "): CljVal =\n" & bodyCode
      if emitLibMode and paramNames.len > 0 and not (name.symName in multiArityFns):
        var wrapperArgs: seq[string] = @[]
        for i in 0..<paramNames.len:
          wrapperArgs.add("args[" & $i & "]")
        result.add("\n" & sp & "proc " & procName & exportMarker & "(args: seq[CljVal]): CljVal =\n")
        result.add(indentStr(indent + 1) & procName & "(" & wrapperArgs.join(", ") & ")\n")
      return result
    else:
      var bodyCode = ""
      if body.len == 1:
        bodyCode = emitExpr(body[0], indent + 2)
      else:
        bodyCode = emitBlock(body, indent + 2)
      popScope()
      return sp & "(block:\n" &
        indentStr(indent + 1) & "proc " & procName & "(" & paramNames.join(", ") & "): CljVal =\n" & bodyCode & "\n" &
        indentStr(indent + 1) & "cljNil())"

  of "defn-":
    if items.len < 3:
      raise newException(EmitterError, "defn- requires name and params")
    var name = items[1]
    # Strip metadata: (with-meta sym meta) -> sym
    if name.kind == ckList and name.items.len == 3 and
       name.items[0].kind == ckSymbol and name.items[0].symName == "with-meta":
      name = name.items[1]
    if name.kind != ckSymbol:
      raise newException(EmitterError, "defn- name must be a symbol")
    registerGlobal(name.symName)
    # Skip docstring if present: (defn- name "doc" [params] body...)
    var paramsIdx = 2
    if items.len > 3 and items[2].kind == ckString:
      paramsIdx = 3
    let params = items[paramsIdx]
    if params.kind != ckVector:
      raise newException(EmitterError, "defn- params must be a vector")
    var paramNames: seq[string] = @[]
    var hasRest = false
    var restIdx = -1
    pushScope()
    # First pass: check for & rest params
    for pi, p in params.items:
      if p.kind == ckSymbol and p.symName == "&":
        hasRest = true
        restIdx = pi
        break
    if hasRest:
      for pi in 0..<restIdx:
        let p = params.items[pi]
        if p.kind != ckSymbol:
          raise newException(EmitterError, "defn- params must be symbols")
        addToScope(p.symName)
      if restIdx + 1 < params.items.len:
        let restParam = params.items[restIdx + 1]
        if restParam.kind != ckSymbol:
          raise newException(EmitterError, "defn- rest param must be a symbol")
        addToScope(restParam.symName)
    else:
      for p in params.items:
        if p.kind != ckSymbol:
          raise newException(EmitterError, "defn- params must be symbols")
        addToScope(p.symName)
        paramNames.add(mangleName(p.symName) & ": CljVal")
    let body = items[(paramsIdx+1)..^1]
    let procName = mangleName(name.symName)
    if hasRest:
      # Rest params: generate proc with args: seq[CljVal]
      multiArityFns.incl(name.symName)
      registerFn(name.symName, -1)
      let namedCount = restIdx
      var preambleLines: seq[string] = @[]
      for pi in 0..<restIdx:
        let p = params.items[pi]
        preambleLines.add(indentStr(indent + 1) & "let " & mangleName(p.symName) & " = args[" & $pi & "]")
      let restParamName = params.items[restIdx + 1].symName
      preambleLines.add(indentStr(indent + 1) & "let " & mangleName(restParamName) & " = cljList(args[" & $namedCount & "..^1])")
      var bodyCode = ""
      if body.len == 0:
        bodyCode = indentStr(indent + 1) & "cljNil()"
      elif body.len == 1:
        bodyCode = emitExpr(body[0], indent + 1)
      else:
        bodyCode = emitBlock(body, indent + 1)
      popScope()
      let preamble = preambleLines.join("\n")
      return sp & "proc " & procName & "(args: seq[CljVal]): CljVal {.used.} =\n" & preamble & "\n" & bodyCode
    registerFn(name.symName, paramNames.len)
    var bodyCode = ""
    if body.len == 0:
      bodyCode = indentStr(indent + 1) & "cljNil()"
    elif body.len == 1:
      bodyCode = emitExpr(body[0], indent + 1)
    else:
      bodyCode = emitBlock(body, indent + 1)
    popScope()
    return sp & "proc " & procName & "(" & paramNames.join(", ") & "): CljVal {.used.} =\n" & bodyCode

  of "fn":
    if items.len < 2:
      raise newException(EmitterError, "fn requires params")
    var paramsIdx = 1
    var fnName = ""
    # Handle named fn: (fn name [params] body)
    if items[1].kind == ckSymbol:
      paramsIdx = 2
      fnName = items[1].symName
    if paramsIdx >= items.len:
      raise newException(EmitterError, "fn requires params and body")
    var params = items[paramsIdx]
    # Strip metadata from params
    if params.kind == ckList and params.items.len == 3 and
       params.items[0].kind == ckSymbol and params.items[0].symName == "with-meta":
      params = params.items[1]
    if params.kind != ckVector:
      raise newException(EmitterError, "fn params must be a vector")
    let paramCount = params.items.len
    pushScope()
    var paramNames: seq[string] = @[]
    if fnName.len > 0:
      addToScope(fnName)
    for p in params.items:
      if p.kind != ckSymbol:
        raise newException(EmitterError, "fn params must be symbols")
      addToScope(p.symName)
      paramNames.add(mangleName(p.symName))
    let body = items[(paramsIdx+1)..^1]
    var bodyCode = ""
    if body.len == 1:
      bodyCode = emitExpr(body[0], indent + 1)
    else:
      bodyCode = emitBlock(body, indent + 1)
    popScope()
    # Wrap with cljFn: convert params to args: seq[CljVal]
    var argsLines: seq[string] = @[]
    if paramCount > 0:
      for i in 0..<paramCount:
        argsLines.add(indentStr(indent + 1) & "let " & paramNames[i] & " = args[" & $i & "]")
    var fnBodyLines: seq[string] = @[]
    if argsLines.len > 0:
      for a in argsLines:
        fnBodyLines.add(a)
    if bodyCode.find("\n") == -1:
      fnBodyLines.add(indentStr(indent + 1) & bodyCode.strip())
    else:
      fnBodyLines.add(bodyCode)
    if fnName.len > 0 or argsLines.len > 0 or bodyCode.find("\n") != -1:
      # Wrap in IIFE to avoid indentation issues when used as an argument
      var wrapperLines: seq[string] = @[]
      wrapperLines.add(sp & "((proc (): CljVal =")
      var tempName: string
      if fnName.len > 0:
        tempName = mangleName(fnName)
      else:
        tempName = "fnResult"
      wrapperLines.add(indentStr(indent + 1) & "var " & tempName & ": CljVal")
      wrapperLines.add(indentStr(indent + 1) & tempName & " = cljFn(proc(args: seq[CljVal]): CljVal =")
      let indentedFnBody = indentCode(fnBodyLines.join("\n"), 1)
      for line in indentedFnBody.split("\n"):
        wrapperLines.add(line)
      wrapperLines.add(indentStr(indent + 1) & ")")
      wrapperLines.add(indentStr(indent + 1) & tempName)
      wrapperLines.add(sp & ")())")
      return wrapperLines.join("\n")
    else:
      return sp & "cljFn(proc(args: seq[CljVal]): CljVal = " & bodyCode.strip() & ")"

  of "let":
    if items.len < 3:
      raise newException(EmitterError, "let requires bindings and body")
    var bindings = letDestructuredBindings(items[1])
    if bindings.kind != ckVector:
      raise newException(EmitterError, "let bindings must be a vector")
    if bindings.items.len mod 2 != 0:
      raise newException(EmitterError, "let bindings must have even number of elements")
    var lines: seq[string] = @[]
    lines.add(sp & "block:")
    pushScope()
    var bi = 0
    while bi < bindings.items.len:
      let bname = bindings.items[bi]
      let bval = bindings.items[bi+1]
      if bname.kind != ckSymbol:
        raise newException(EmitterError, "let binding name must be a symbol, got " & $bname.kind & ": " & $bname)
      addToScope(bname.symName)
      let bcode = emitExpr(bval, indent + 1, needsValue = true)
      if bcode.find("\n") != -1:
        # Multi-line value: use var and place first line on next line for correct indentation
        lines.add(indentStr(indent + 1) & "var " & mangleName(bname.symName) & ": CljVal")
        var bcodeLines = bcode.split("\n")
        for j, line in bcodeLines:
          if j == 0:
            lines.add(indentStr(indent + 1) & mangleName(bname.symName) & " = " & line)
          else:
            lines.add(line)
      else:
        lines.add(indentStr(indent + 1) & "let " & mangleName(bname.symName) & " = " & bcode)
      bi += 2
    let body = items[2..^1]
    for j, b in body:
      let bcode = emitExpr(b, indent + 1)
      if j == body.len - 1:
        lines.add(bcode)
      else:
        let stripped = bcode.strip()
        if stripped.contains("\n"):
          # Multi-line expression as non-last form: wrap in proc
          let indentedCode = indentCode(bcode, 1)
          lines.add(indentStr(indent + 1) & "discard ((proc (): CljVal =\n" & indentedCode & "\n" & indentStr(indent + 1) & ")())")
        elif stripped.startsWith("echo ") or stripped.startsWith("discard ") or
           stripped.startsWith("if ") or stripped.startsWith("try:") or
           stripped.startsWith("var ") or stripped.startsWith("let ") or
           stripped.startsWith("proc ") or stripped.startsWith("while "):
          lines.add(bcode)
        elif stripped.startsWith("block:"):
          # Multi-line block as non-last form: discard the last line
          var blockLines = bcode.split("\n")
          var lastIdx = blockLines.len - 1
          while lastIdx >= 0 and blockLines[lastIdx].strip() == "":
            lastIdx.dec
          if lastIdx >= 0:
            let lastLine = blockLines[lastIdx].strip()
            if not lastLine.startsWith("discard ") and not lastLine.startsWith("result = "):
              let prefixLen = blockLines[lastIdx].len - blockLines[lastIdx].strip().len
              blockLines[lastIdx] = blockLines[lastIdx][0..<prefixLen] & "discard " & lastLine
          lines.add(blockLines.join("\n"))
        else:
          lines.add(indentStr(indent + 1) & "discard " & stripped)
    popScope()
    return lines.join("\n")

  of "if":
    if items.len < 3 or items.len > 4:
      raise newException(EmitterError, "if requires condition, then, and optional else")
    # Recursively check if an if form has control flow in any branch
    proc ifHasControlFlow(form: CljVal): bool =
      if form.kind != ckList or form.items.len < 3: return false
      if form.items[0].kind != ckSymbol or form.items[0].symName != "if": return false
      let thenCode = emitExpr(form.items[2], 0)
      if thenCode.strip().contains("continue") or thenCode.strip().contains("break"):
        return true
      if form.items.len == 4:
        let elseCode = emitExpr(form.items[3], 0)
        if elseCode.strip().contains("continue") or elseCode.strip().contains("break"):
          return true
        # Recurse into nested if in else branch
        if form.items[3].kind == ckList and form.items[3].items.len > 0 and
           form.items[3].items[0].kind == ckSymbol and form.items[3].items[0].symName == "if":
          return ifHasControlFlow(form.items[3])
      return false
    let condCode = emitExpr(items[1], 0)
    let thenCode = emitExpr(items[2], indent + 1)
    let thenStripped = thenCode.strip()
    let thenIsControl = thenStripped.contains("continue") or thenStripped.contains("break")
    let hasCF = ifHasControlFlow(items[0])
    if items.len == 4:
      let elseCode = emitExpr(items[3], indent + 1)
      let elseStripped = elseCode.strip()
      let elseIsControl = elseStripped.contains("continue") or elseStripped.contains("break")
      if thenIsControl or elseIsControl:
        # Direct control flow in branches — use statement form
        var lines: seq[string] = @[]
        lines.add(sp & "if cljIsTruthy(" & condCode.strip() & "):")
        if thenIsControl:
          lines.add(thenCode)
        elif loopResultVar.len > 0:
          lines.add(indentStr(indent + 1) & loopResultVar & " = " & thenStripped)
        else:
          lines.add(indentStr(indent + 1) & "discard " & thenStripped)
        lines.add(sp & "else:")
        if elseIsControl:
          lines.add(elseCode)
        elif loopResultVar.len > 0:
          lines.add(indentStr(indent + 1) & loopResultVar & " = " & elseStripped)
        else:
          lines.add(indentStr(indent + 1) & "discard " & elseStripped)
        return lines.join("\n")
      var ifBlock = sp & "if cljIsTruthy(" & condCode.strip() & "):\n" & thenCode
      ifBlock.add("\n" & sp & "else:\n" & elseCode)
      return ifBlock
    var ifBlock = sp & "if cljIsTruthy(" & condCode.strip() & "):\n" & thenCode
    return ifBlock

  of "when":
    if items.len < 3:
      raise newException(EmitterError, "when requires condition and body")
    let condCode = emitExpr(items[1], indent)
    var lines: seq[string] = @[]
    lines.add(sp & "if cljIsTruthy(" & condCode.strip() & "):")
    let body = items[2..^1]
    for bi, b in body:
      let bcode = emitExpr(b, indent + 1)
      let stripped = bcode.strip()
      let isStatement = stripped.startsWith("echo ") or stripped.startsWith("discard ") or
                        stripped.startsWith("var ") or stripped.startsWith("let ") or
                        stripped.startsWith("proc ") or
                        stripped.startsWith("if ") or stripped.startsWith("try:") or
                        stripped.startsWith("while ") or stripped.contains("continue")
      if isStatement:
        lines.add(bcode)
      elif stripped.startsWith("block:"):
        var blockLines = bcode.split("\n")
        var lastIdx = blockLines.len - 1
        while lastIdx >= 0 and blockLines[lastIdx].strip() == "":
          lastIdx.dec
        if lastIdx >= 0:
          let lastLine = blockLines[lastIdx].strip()
          if not lastLine.startsWith("discard ") and not lastLine.startsWith("result = "):
            let prefixLen = blockLines[lastIdx].len - blockLines[lastIdx].strip().len
            blockLines[lastIdx] = blockLines[lastIdx][0..<prefixLen] & "discard " & lastLine
        lines.add(blockLines.join("\n"))
      else:
        lines.add(indentStr(indent + 1) & "discard " & stripped)
    lines.add(sp & "else:")
    lines.add(indentStr(indent + 1) & "discard cljNil()")
    return lines.join("\n")

  of "cond":
    if items.len < 3 or items.len mod 2 != 1:
      raise newException(EmitterError, "cond requires test/expr pairs")
    # Build nested if-elif chain
    var lines: seq[string] = @[]
    var first = true
    var ci = 1
    while ci < items.len - 1:
      let testExpr = items[ci]
      let thenExpr = items[ci + 1]
      let condCode = emitExpr(testExpr, 0).strip()
      let thenCode = emitExpr(thenExpr, indent + 1)
      if first:
        lines.add(sp & "if cljIsTruthy(" & condCode & "):\n" & sp & "  return " & thenCode.strip())
        first = false
      else:
        lines.add(sp & "elif cljIsTruthy(" & condCode & "):\n" & sp & "  return " & thenCode.strip())
      ci += 2
    return lines.join("\n")

  of "loop":
    if items.len < 3:
      raise newException(EmitterError, "loop requires bindings and body")
    let bindings = items[1]
    if bindings.kind != ckVector:
      raise newException(EmitterError, "loop bindings must be a vector")
    if bindings.items.len mod 2 != 0:
      raise newException(EmitterError, "loop bindings must have even number of elements")
    var loopParams: seq[(string, string, string)] = @[]  # (mangled, original, value)
    var li = 0
    while li < bindings.items.len:
      var lname = bindings.items[li]
      let lval = bindings.items[li+1]
      if lname.kind == ckList and lname.items.len == 3 and
         lname.items[0].kind == ckSymbol and lname.items[0].symName == "with-meta":
        lname = lname.items[1]
      if lname.kind != ckSymbol:
        raise newException(EmitterError, "loop binding name must be a symbol")
      loopParams.add((mangleName(lname.symName), lname.symName, emitExpr(lval, 0, needsValue = true)))
      li += 2
    var loopVars: seq[string] = @[]
    var lines: seq[string] = @[]
    pushScope()
    for (lpName, lpOrig, lpVal) in loopParams:
      addToScope(lpOrig)
      lines.add(sp & "var " & lpName & ": CljVal = " & lpVal)
      loopVars.add(lpName)
    loopStack.add(loopVars)
    let body = items[2..^1]
    # Check if the last form is an 'if' with control flow in branches (recursively)
    proc ifHasCF(form: CljVal): bool =
      if form.kind != ckList or form.items.len < 3: return false
      if form.items[0].kind != ckSymbol or form.items[0].symName != "if": return false
      let thenCode = emitExpr(form.items[2], 0)
      if thenCode.strip().contains("continue") or thenCode.strip().contains("break"):
        return true
      if form.items.len == 4:
        let elseCode = emitExpr(form.items[3], 0)
        if elseCode.strip().contains("continue") or elseCode.strip().contains("break"):
          return true
        if form.items[3].kind == ckList and form.items[3].items.len > 0 and
           form.items[3].items[0].kind == ckSymbol and form.items[3].items[0].symName == "if":
          return ifHasCF(form.items[3])
      return false
    var needsResultVar = false
    if body.len > 0:
      needsResultVar = ifHasCF(body[^1])
    if needsResultVar:
      lines.add(sp & "var loopResult: CljVal = cljNil()")
      loopResultVar = "loopResult"
    lines.add(sp & "while true:")
    for bi, b in body:
      let bcode = emitExpr(b, indent + 1)
      let stripped = bcode.strip()
      let isLast = (bi == body.len - 1)
      if isLast and needsResultVar:
        # Last form with control flow: the if handler uses loopResultVar
        lines.add(bcode)
      elif isLast or stripped.startsWith("echo ") or stripped.startsWith("discard ") or
         stripped.startsWith("var ") or stripped.startsWith("let ") or
         stripped.startsWith("proc ") or
         stripped.startsWith("if ") or stripped.startsWith("try:") or
         stripped.startsWith("while ") or stripped.contains("continue"):
        lines.add(bcode)
      elif stripped.startsWith("block:"):
        var blockLines = bcode.split("\n")
        var lastIdx = blockLines.len - 1
        while lastIdx >= 0 and blockLines[lastIdx].strip() == "":
          lastIdx.dec
        if lastIdx >= 0:
          let lastLine = blockLines[lastIdx].strip()
          if not lastLine.startsWith("discard ") and not lastLine.startsWith("result = "):
            let prefixLen = blockLines[lastIdx].len - blockLines[lastIdx].strip().len
            blockLines[lastIdx] = blockLines[lastIdx][0..<prefixLen] & "discard " & lastLine
        lines.add(blockLines.join("\n"))
      else:
        lines.add(indentStr(indent + 1) & "discard " & stripped)
    lines.add(indentStr(indent + 1) & "break")
    discard loopStack.pop()
    popScope()
    if needsResultVar:
      lines.add(sp & "loopResult")
      loopResultVar = ""
    let loopCode = lines.join("\n")
    if needsValue:
      # Wrap in IIFE for expression contexts (function args, let RHS, etc.)
      var iifeLines: seq[string] = @[]
      iifeLines.add(sp & "(proc(): CljVal =")
      iifeLines.add(indentCode(loopCode, 1))
      if not needsResultVar:
        iifeLines.add(indentStr(indent + 1) & "cljNil()")
      iifeLines.add(sp & ")()")
      return iifeLines.join("\n")
    return loopCode

  of "recur":
    if items.len < 2:
      raise newException(EmitterError, "recur requires arguments")
    if loopStack.len == 0:
      raise newException(EmitterError, "recur outside of loop")
    let loopVars = loopStack[^1]
    if items.len - 1 != loopVars.len:
      raise newException(EmitterError, "recur requires " & $loopVars.len & " arguments, got " & $(items.len - 1))
    var lines: seq[string] = @[]
    for ri in 1..<items.len:
      lines.add(sp & loopVars[ri-1] & " = " & emitExpr(items[ri], 0))
    lines.add(sp & "continue")
    return lines.join("\n")

  of "do":
    if items.len < 2:
      return sp & "discard cljNil()"
    return emitBlock(items[1..^1], indent)

  of "lazy-seq":
    # lazy-seq is treated as do (eager evaluation for native compilation)
    if items.len < 2:
      return sp & "cljNil()"
    return emitExpr(items[1], indent)

  of "try":
    if items.len < 2:
      raise newException(EmitterError, "try requires body")
    var bodyForms: seq[CljVal] = @[]
    var catchClauses: seq[(string, string, string, seq[CljVal])] = @[]  # (exType, mangledName, origName, body)
    var finallyBody: seq[CljVal] = @[]
    var ti = 1
    while ti < items.len:
      let form = items[ti]
      if form.kind == ckList and form.items.len > 0 and form.items[0].kind == ckSymbol:
        if form.items[0].symName == "catch":
          if form.items.len < 3:
            raise newException(EmitterError, "catch requires at least name and body")
          var exTypeStr = "CatchableError"
          var nameIdx = 2
          var bodyIdx = 3
          if form.items[1].kind == ckSymbol and form.items.len >= 4:
            let rawType = form.items[1].symName
            # Map known Clojure exception types to Nim
            if rawType in ["clojure.lang.ExceptionInfo", "ExceptionInfo"]:
              exTypeStr = "ExInfo"
            elif rawType in ["Throwable", "Exception", "java.lang.Exception", "java.lang.Throwable"]:
              exTypeStr = "CatchableError"
            else:
              exTypeStr = rawType
          elif form.items[1].kind == ckKeyword:
            if form.items[1].kwName == "default":
              exTypeStr = "CatchableError"
            else:
              exTypeStr = form.items[1].kwName
          else:
            # (catch name body...)
            nameIdx = 1
            bodyIdx = 2
          let exName = form.items[nameIdx]
          if exName.kind != ckSymbol:
            raise newException(EmitterError, "catch name must be a symbol")
          catchClauses.add((exTypeStr, mangleName(exName.symName), exName.symName, form.items[bodyIdx..^1]))
        elif form.items[0].symName == "finally":
          finallyBody = form.items[1..^1]
        else:
          bodyForms.add(form)
      else:
        bodyForms.add(form)
      inc ti
    var lines: seq[string] = @[]
    lines.add(sp & "try:")
    for i, b in bodyForms:
      let isLast = (i == bodyForms.len - 1)
      let code = emitExpr(b, indent + 1)
      if isLast:
        lines.add(code)
      else:
        let stripped = code.strip()
        if stripped.startsWith("echo ") or stripped.startsWith("discard ") or
           stripped.startsWith("block:") or stripped.startsWith("if ") or
           stripped.startsWith("try:") or stripped.startsWith("var ") or
           stripped.startsWith("let ") or stripped.startsWith("proc ") or
           stripped.startsWith("result = ") or stripped.contains("\n") or
           stripped.contains(" = "):
          lines.add(code)
        else:
          lines.add(indentStr(indent + 1) & "discard " & stripped)
    for (exType, exVar, exOrig, exBody) in catchClauses:
      lines.add(sp & "except " & exType & ":")
      lines.add(indentStr(indent + 1) & "let " & exVar & " = cljMap(@[cljKeyword(\"message\")], @[cljString(getCurrentExceptionMsg())])")
      lines.add(indentStr(indent + 1) & "discard cljAssoc(" & exVar & ", cljKeyword(\"type\"), cljString(\"" & exType & "\"))")
      lines.add(indentStr(indent + 1) & "let exPtr" & exVar & " = getCurrentException()")
      lines.add(indentStr(indent + 1) & "if exPtr" & exVar & " of ExInfo:")
      lines.add(indentStr(indent + 2) & "discard cljAssoc(" & exVar & ", cljKeyword(\"data\"), (ref ExInfo)(exPtr" & exVar & ").exData)")
      pushScope()
      addToScope(exOrig)
      for i, eb in exBody:
        let isLast = (i == exBody.len - 1)
        let code = emitExpr(eb, indent + 1)
        if isLast:
          lines.add(code)
        else:
          let stripped = code.strip()
          if stripped.startsWith("echo ") or stripped.startsWith("discard ") or
             stripped.startsWith("block:") or stripped.startsWith("if ") or
             stripped.startsWith("try:") or stripped.startsWith("var ") or
             stripped.startsWith("let ") or stripped.startsWith("proc ") or
             stripped.startsWith("result = ") or stripped.contains("\n") or
             stripped.contains(" = "):
            lines.add(code)
          else:
            lines.add(indentStr(indent + 1) & "discard " & stripped)
      popScope()
    if finallyBody.len > 0:
      lines.add(sp & "finally:")
      for fb in finallyBody:
        let fbCode = emitExpr(fb, indent + 1)
        let fbStripped = fbCode.strip()
        if fbStripped.startsWith("echo ") or fbStripped.startsWith("discard ") or
           fbStripped.startsWith("var ") or fbStripped.startsWith("let ") or
           fbStripped.startsWith("proc ") or fbStripped.startsWith("if ") or
           fbStripped.startsWith("try:") or fbStripped.startsWith("while "):
          lines.add(fbCode)
        else:
          lines.add(indentStr(indent + 1) & "discard " & fbStripped)
    return lines.join("\n")

  of "throw":
    if items.len != 2:
      raise newException(EmitterError, "throw requires exactly 1 argument")
    return sp & "raise newException(CatchableError, cljStr(" & emitExpr(items[1], 0) & "))"

  of "when-var-exists":
    if items.len < 3:
      raise newException(EmitterError, "when-var-exists requires a symbol and body")
    let varSym = items[1]
    if varSym.kind != ckSymbol:
      raise newException(EmitterError, "when-var-exists requires a symbol as first argument")
    let symName = resolveNsAlias(varSym.symName)
    let isSpecial = symName in ["case", "defprotocol", "defrecord", "deftype", "defmulti", "defmethod",
                                 "var", "bound-fn", "bound-fn*", "promise", "delay", "future",
                                 "sorted-map-by", "sorted-set-by", "compare-and-set!",
                                 "empty", "aclone", "int-array", "identical?"]
    let exists = runtimeName(symName).len > 0 or isLocalVar(symName) or isSpecial
    if exists:
      let body = items[2..^1]
      if body.len == 1:
        return emitExpr(body[0], indent)
      else:
        return emitBlock(body, indent)
    else:
      return sp & "cljNil()"

  of "quote":
    if items.len != 2:
      raise newException(EmitterError, "quote requires exactly 1 argument")
    let quoted = items[1]
    case quoted.kind
    of ckSymbol:
      return sp & "cljSymbol(\"" & quoted.symName & "\")"
    of ckList:
      var parts: seq[string] = @[]
      for item in quoted.items:
        parts.add(emitQuotedForm(item))
      return sp & "cljList(@[" & parts.join(", ") & "])"
    of ckVector:
      var parts: seq[string] = @[]
      for item in quoted.items:
        parts.add(emitQuotedForm(item))
      return sp & "cljVector(@[" & parts.join(", ") & "])"
    else:
      return emitExpr(quoted, indent)

  of "map":
    if items.len < 3:
      raise newException(EmitterError, "map requires at least 2 arguments (f, coll)")
    let fnArg = items[1]
    let isVariadic = items.len > 3
    var collArgs: seq[string] = @[]
    for idx in 2..<items.len:
      collArgs.add(emitExpr(items[idx], 0))
    if isVariadic:
      # Multiple collections: use cljMapN
      let collList = "@[" & collArgs.join(", ") & "]"
      if fnArg.kind == ckSymbol:
        let rn = runtimeName(fnArg.symName)
        if rn.len > 0:
          return sp & "cljMapN(cljFn(proc(args: seq[CljVal]): CljVal = " & rn & "(args)), " & collList & ")"
        return sp & "cljMapN(cljFn(proc(args: seq[CljVal]): CljVal = " & mangleName(fnArg.symName) & "(args)), " & collList & ")"
      elif fnArg.kind == ckList and fnArg.items.len > 0 and fnArg.items[0].kind == ckSymbol and fnArg.items[0].symName in ["fn", "fn*"]:
        let fnParams = fnArg.items[1]
        let fnBody = fnArg.items[2..^1]
        var pNames: seq[string] = @[]
        for p in fnParams.items:
          pNames.add(mangleName(p.symName))
        var bodyExpr = ""
        if fnBody.len == 1:
          bodyExpr = emitExpr(fnBody[0], 0).strip()
        else:
          var parts: seq[string] = @[]
          for b in fnBody:
            parts.add(emitExpr(b, 0).strip())
          bodyExpr = parts.join("; ")
        var letBindings = ""
        for j in 0..<pNames.len:
          letBindings.add("let " & pNames[j] & " = args[" & $j & "]; ")
        let fnProc = "proc(args: seq[CljVal]): CljVal = (" & letBindings & bodyExpr & ")"
        return sp & "cljMapN(cljFn(" & fnProc & "), " & collList & ")"
      else:
        return sp & "cljMapN(" & emitExpr(fnArg, 0) & ", " & collList & ")"
    else:
      let collArg = collArgs[0]
      if fnArg.kind == ckSymbol:
        let rn = runtimeName(fnArg.symName)
        if rn.len > 0:
          let isVar = fnArg.symName in variadicRuntimeFns
          if isVar:
            return sp & "cljMap(cljFn(proc(args: seq[CljVal]): CljVal = " & rn & "(args)), " & collArg & ")"
          else:
            return sp & "cljMap(cljFn(proc(args: seq[CljVal]): CljVal = " & rn & "(args[0])), " & collArg & ")"
        return sp & "cljMap(cljFn(proc(args: seq[CljVal]): CljVal = " & mangleName(fnArg.symName) & "(args[0])), " & collArg & ")"
      elif fnArg.kind == ckList and fnArg.items.len > 0 and fnArg.items[0].kind == ckSymbol and fnArg.items[0].symName in ["fn", "fn*"]:
        let fnParams = fnArg.items[1]
        let fnBody = fnArg.items[2..^1]
        var pNames: seq[string] = @[]
        for p in fnParams.items:
          pNames.add(mangleName(p.symName))
        var bodyExpr = ""
        if fnBody.len == 1:
          bodyExpr = emitExpr(fnBody[0], 0).strip()
        else:
          var parts: seq[string] = @[]
          for b in fnBody:
            parts.add(emitExpr(b, 0).strip())
          bodyExpr = parts.join("; ")
        let fnProc = "proc(args: seq[CljVal]): CljVal = (let " & pNames[0] & " = args[0]; " & bodyExpr & ")"
        return sp & "cljMap(cljFn(" & fnProc & "), " & collArg & ")"
      else:
        return sp & "cljMap(" & emitExpr(fnArg, 0) & ", " & collArg & ")"

  of "filter":
    if items.len != 3:
      raise newException(EmitterError, "filter requires exactly 2 arguments")
    let fnArg = items[1]
    let collArg = emitExpr(items[2], 0)
    let isFn = fnArg.kind == ckList and fnArg.items.len > 0 and fnArg.items[0].kind == ckSymbol and fnArg.items[0].symName in ["fn", "fn*"]
    if isFn:
      let fnParams = fnArg.items[1]
      let fnBody = fnArg.items[2..^1]
      var pNames: seq[string] = @[]
      for p in fnParams.items:
        pNames.add(mangleName(p.symName))
      var bodyExpr = ""
      if fnBody.len == 1:
        bodyExpr = emitExpr(fnBody[0], 0).strip()
      else:
        var parts: seq[string] = @[]
        for b in fnBody:
          parts.add(emitExpr(b, 0).strip())
        bodyExpr = parts.join("; ")
      # Wrap single-param fn as seq[CljVal] version
      let fnProc = "proc(args: seq[CljVal]): CljVal = (let " & pNames[0] & " = args[0]; " & bodyExpr & ")"
      return sp & "cljFilter(cljFn(" & fnProc & "), " & collArg & ")"
    else:
      return sp & "cljFilter(" & emitExpr(fnArg, indent) & ", " & collArg & ")"

  of "reduce":
    if items.len < 3 or items.len > 4:
      raise newException(EmitterError, "reduce requires 2 or 3 arguments")
    if items.len == 3:
      # (reduce f coll) — first element as init
      let fnArg = items[1]
      let collArg = emitExpr(items[2], 0)
      let isFn = fnArg.kind == ckList and fnArg.items.len > 0 and fnArg.items[0].kind == ckSymbol and fnArg.items[0].symName in ["fn", "fn*"]
      let isSymbol = fnArg.kind == ckSymbol
      if isFn:
        let fnParams = fnArg.items[1]
        let fnBody = fnArg.items[2..^1]
        var pNames: seq[string] = @[]
        for p in fnParams.items:
          pNames.add(mangleName(p.symName))
        var bodyExpr = ""
        if fnBody.len == 1:
          bodyExpr = emitExpr(fnBody[0], 0).strip()
        else:
          var parts: seq[string] = @[]
          for b in fnBody:
            parts.add(emitExpr(b, 0).strip())
          bodyExpr = parts.join("; ")
        let fnProc = "proc(args: seq[CljVal]): CljVal = (let " & pNames[0] & " = args[0]; let " & pNames[1] & " = args[1]; " & bodyExpr & ")"
        return sp & "cljReduce(cljFn(" & fnProc & "), cljNil(), " & collArg & ")"
      elif isSymbol:
        let rn = runtimeName(fnArg.symName)
        if rn.len > 0:
          let wrapper = "proc(args: seq[CljVal]): CljVal = " & rn & "(args)"
          return sp & "cljReduce(cljFn(" & wrapper & "), cljNil(), " & collArg & ")"
        let mangled = mangleName(fnArg.symName)
        let wrapper = "proc(args: seq[CljVal]): CljVal = " & mangled & "(args[0], args[1])"
        return sp & "cljReduce(cljFn(" & wrapper & "), cljNil(), " & collArg & ")"
      else:
        return sp & "cljReduce(" & emitExpr(fnArg, 0) & ", cljNil(), " & collArg & ")"
    else:
      # (reduce f init coll)
      let fnArg = items[1]
      let initArg = emitExpr(items[2], 0)
      let collArg = emitExpr(items[3], 0)
      let isFn = fnArg.kind == ckList and fnArg.items.len > 0 and fnArg.items[0].kind == ckSymbol and fnArg.items[0].symName in ["fn", "fn*"]
      let isSymbol = fnArg.kind == ckSymbol
      if isFn:
        let fnParams = fnArg.items[1]
        let fnBody = fnArg.items[2..^1]
        var pNames: seq[string] = @[]
        for p in fnParams.items:
          pNames.add(mangleName(p.symName))
        var bodyExpr = ""
        if fnBody.len == 1:
          bodyExpr = emitExpr(fnBody[0], 0).strip()
        else:
          var parts: seq[string] = @[]
          for b in fnBody:
            parts.add(emitExpr(b, 0).strip())
          bodyExpr = parts.join("; ")
        let fnProc = "proc(args: seq[CljVal]): CljVal = (let " & pNames[0] & " = args[0]; let " & pNames[1] & " = args[1]; " & bodyExpr & ")"
        return sp & "cljReduce(cljFn(" & fnProc & "), " & initArg & ", " & collArg & ")"
      elif isSymbol:
        let rn = runtimeName(fnArg.symName)
        if rn.len > 0:
          let wrapper = "proc(args: seq[CljVal]): CljVal = " & rn & "(args)"
          return sp & "cljReduce(cljFn(" & wrapper & "), " & initArg & ", " & collArg & ")"
        let mangled = mangleName(fnArg.symName)
        let wrapper = "proc(args: seq[CljVal]): CljVal = " & mangled & "(args[0], args[1])"
        return sp & "cljReduce(cljFn(" & wrapper & "), " & initArg & ", " & collArg & ")"
      else:
        return sp & "cljReduce(" & emitExpr(fnArg, 0) & ", " & initArg & ", " & collArg & ")"

  of "mapv":
    if items.len != 3:
      raise newException(EmitterError, "mapv requires exactly 2 arguments")
    return sp & "cljMapv(" & emitExpr(items[1], 0) & ", " & emitExpr(items[2], 0) & ")"

  of "apply":
    if items.len < 3:
      raise newException(EmitterError, "apply requires at least 2 arguments")
    if items.len == 3:
      return sp & "cljApply(" & emitExpr(items[1], 0) & ", " & emitExpr(items[2], 0) & ")"
    else:
      # (apply f x y args) -> (apply (partial f x y) args)
      let fnArg = emitExpr(items[1], 0)
      var partialArgs: seq[string] = @[]
      for i in 2..<items.len - 1:
        partialArgs.add(emitExpr(items[i], 0))
      let lastArg = emitExpr(items[^1], 0)
      return sp & "cljApply(cljPartial(" & fnArg & ", @[" & partialArgs.join(", ") & "]), " & lastArg & ")"

  of "some":
    if items.len != 3:
      raise newException(EmitterError, "some requires exactly 2 arguments")
    return sp & "cljSome(" & emitExpr(items[1], 0) & ", " & emitExpr(items[2], 0) & ")"

  of "every?":
    if items.len != 3:
      raise newException(EmitterError, "every? requires exactly 2 arguments")
    return sp & "cljEvery(" & emitExpr(items[1], 0) & ", " & emitExpr(items[2], 0) & ")"

  of "into":
    if items.len != 3:
      raise newException(EmitterError, "into requires exactly 2 arguments")
    return sp & "cljInto(" & emitExpr(items[1], 0) & ", " & emitExpr(items[2], 0) & ")"

  of "comp":
    var parts: seq[string] = @[]
    for i in 1..<items.len:
      parts.add(emitExpr(items[i], 0))
    return sp & "cljComp(@[" & parts.join(", ") & "])"

  of "partial":
    var parts: seq[string] = @[]
    for i in 1..<items.len:
      if items[i].kind == ckList and items[i].items.len > 0 and items[i].items[0].kind == ckSymbol and items[i].items[0].symName in ["fn", "fn*"]:
        let fnParams = items[i].items[1]
        let fnBody = items[i].items[2..^1]
        var pNames: seq[string] = @[]
        for p in fnParams.items:
          pNames.add(mangleName(p.symName))
        var bodyExpr = ""
        if fnBody.len == 1:
          bodyExpr = emitExpr(fnBody[0], 0).strip()
        else:
          var bodyParts: seq[string] = @[]
          for b in fnBody:
            bodyParts.add(emitExpr(b, 0).strip())
          bodyExpr = bodyParts.join("; ")
        var letBindings = ""
        for j in 0..<pNames.len:
          letBindings.add("let " & pNames[j] & " = args[" & $j & "]; ")
        let fnProc = "proc(args: seq[CljVal]): CljVal = (" & letBindings & bodyExpr & ")"
        parts.add("cljFn(" & fnProc & ")")
      else:
        parts.add(emitExpr(items[i], 0))
    return sp & "cljPartial(" & parts[0] & ", @[" & parts[1..^1].join(", ") & "])"

  of "juxt":
    var parts: seq[string] = @[]
    for i in 1..<items.len:
      parts.add(emitExpr(items[i], 0))
    return sp & "cljJuxt(@[" & parts.join(", ") & "])"

  of "complement":
    if items.len != 2:
      raise newException(EmitterError, "complement requires exactly 1 argument")
    return sp & "cljComplement(" & emitExpr(items[1], 0) & ")"

  of "constantly":
    if items.len != 2:
      raise newException(EmitterError, "constantly requires exactly 1 argument")
    return sp & "cljConstantly(" & emitExpr(items[1], 0) & ")"

  of "var":
    if items.len != 2:
      raise newException(EmitterError, "var requires exactly 1 argument")
    let target = items[1]
    if target.kind == ckSymbol:
      return sp & "cljVar(" & emitExpr(target, 0) & ")"
    return sp & "cljVar(" & emitExpr(target, 0) & ")"

  of "definterface":
    if items.len < 2:
      raise newException(EmitterError, "definterface requires a name")
    let iname = items[1]
    if iname.kind != ckSymbol:
      raise newException(EmitterError, "definterface name must be a symbol")
    registerGlobal(iname.symName)
    return sp & "discard cljProtocol(\"" & iname.symName & "\")"

  of "defprotocol":
    if items.len < 2:
      raise newException(EmitterError, "defprotocol requires a name")
    let pname = items[1]
    if pname.kind != ckSymbol:
      raise newException(EmitterError, "defprotocol name must be a symbol")
    registerGlobal(pname.symName)
    return sp & "let " & mangleName(pname.symName) & " = cljProtocol(\"" & pname.symName & "\")"

  of "defrecord":
    if items.len < 3:
      raise newException(EmitterError, "defrecord requires name, fields, and optional protocols")
    let rname = items[1]
    if rname.kind != ckSymbol:
      raise newException(EmitterError, "defrecord name must be a symbol")
    registerGlobal(rname.symName)
    let mangled = mangleName(rname.symName)
    let fields = items[2]
    var fieldNames: seq[string] = @[]
    if fields.kind == ckVector:
      for f in fields.items:
        if f.kind == ckSymbol:
          fieldNames.add(f.symName)
    var paramParts: seq[string] = @[]
    for i, fn in fieldNames:
      paramParts.add(mangleName(fn) & ": CljVal")
    var mapParts: seq[string] = @[]
    for fn in fieldNames:
      mapParts.add("cljKeyword(\"" & fn & "\")")
      mapParts.add(mangleName(fn))
    return sp & "proc " & mangled & "(" & paramParts.join(", ") & "): CljVal =\n" & 
      indentStr(indent + 1) & "cljHashMap(@[" & mapParts.join(", ") & "])"

  of "deftype":
    if items.len < 3:
      raise newException(EmitterError, "deftype requires name, fields, and optional protocols")
    let tname = items[1]
    if tname.kind != ckSymbol:
      raise newException(EmitterError, "deftype name must be a symbol")
    registerGlobal(tname.symName)
    return sp & "let " & mangleName(tname.symName) & " = cljTypeConstructor(\"" & tname.symName & "\", cljVector(@[]))"

  of "new":
    # Java-style constructor: (new ClassName args...) — emit as constructor call
    if items.len < 2:
      return sp & "cljNil()"
    let className = items[1]
    if className.kind != ckSymbol:
      return sp & "cljNil()"
    var argParts: seq[string] = @[]
    for i in 2..<items.len:
      argParts.add(emitExpr(items[i], indent, needsValue = true))
    let mangled = mangleName(className.symName)
    return sp & mangled & "(" & argParts.join(", ") & ")"

  of "defmulti":
    if items.len < 3:
      raise newException(EmitterError, "defmulti requires name and dispatch function")
    let mname = items[1]
    if mname.kind != ckSymbol:
      raise newException(EmitterError, "defmulti name must be a symbol")
    let dispatchFn = emitExpr(items[2], 0)
    return sp & "let " & mangleName(mname.symName) & " = cljMultiFn(\"" & mname.symName & "\", " & dispatchFn & ")"

  of "defmethod":
    if items.len < 4:
      raise newException(EmitterError, "defmethod requires name, dispatch-val, params, and body")
    let mname = items[1]
    if mname.kind != ckSymbol:
      raise newException(EmitterError, "defmethod name must be a symbol")
    var params = items[3]
    if params.kind != ckVector:
      raise newException(EmitterError, "defmethod params must be a vector")
    var paramNames: seq[string] = @[]
    for p in params.items:
      if p.kind != ckSymbol:
        raise newException(EmitterError, "defmethod params must be symbols")
      paramNames.add(mangleName(p.symName) & ": CljVal")
    let body = items[4..^1]
    var bodyCode = ""
    if body.len == 1:
      bodyCode = emitExpr(body[0], indent + 1)
    else:
      bodyCode = emitBlock(body, indent + 1)
    return sp & "proc " & mangleName(mname.symName) & "_impl(" & paramNames.join(", ") & "): CljVal =\n" & bodyCode

  of "case":
    if items.len < 2:
      raise newException(EmitterError, "case requires expression and clauses")
    let caseExpr = emitExpr(items[1], 0)
    var ci = 2
    var lines: seq[string] = @[]
    lines.add(sp & "block:")
    lines.add(indentStr(indent + 1) & "let case_expr_val = " & caseExpr)
    var first = true
    while ci < items.len:
      let clause = items[ci]
      if ci + 1 >= items.len:
        lines.add(indentStr(indent + 1) & "else: " & emitExpr(clause, indent + 1))
        break
      let resultExpr = emitExpr(items[ci + 1], indent + 1)
      if clause.kind == ckList or clause.kind == ckVector:
        var subItems: seq[CljVal] = @[]
        if clause.kind == ckList: subItems = clause.items
        elif clause.kind == ckVector: subItems = clause.items
        var condParts: seq[string] = @[]
        for s in subItems:
          if s.kind == ckList:
            let quoted = emitQuotedForm(s)
            condParts.add("cljIsTruthy(cljMultiEqual2(case_expr_val, " & quoted & "))")
          else:
            condParts.add("cljIsTruthy(cljMultiEqual2(case_expr_val, " & emitExpr(s, 0) & "))")
        let cond = condParts.join(" or ")
        if first:
          lines.add(indentStr(indent + 1) & "if " & cond & ":")
          lines.add(indentStr(indent + 2) & resultExpr)
          first = false
        else:
          lines.add(indentStr(indent + 1) & "elif " & cond & ":")
          lines.add(indentStr(indent + 2) & resultExpr)
        ci += 2
      elif clause.kind == ckSymbol and clause.symName == "default":
        lines.add(indentStr(indent + 1) & "else:")
        lines.add(indentStr(indent + 2) & resultExpr)
        ci += 2
      else:
        let cond = "cljIsTruthy(cljMultiEqual2(case_expr_val, " & emitExpr(clause, 0) & "))"
        if first:
          lines.add(indentStr(indent + 1) & "if " & cond & ":")
          lines.add(indentStr(indent + 2) & resultExpr)
          first = false
        else:
          lines.add(indentStr(indent + 1) & "elif " & cond & ":")
          lines.add(indentStr(indent + 2) & resultExpr)
        ci += 2
    if lines.len <= 2:
      return sp & "cljNil()"
    if not lines[^1].strip().startsWith("else:"):
      lines.add(indentStr(indent + 1) & "else: cljNil()")
    return lines.join("\n")

  of "bound-fn":
    # Delegate to fn for now (full dynamic binding not supported in compiled mode)
    let fnForm = cljList(@[cljSymbol("fn")] & items[1..^1])
    return emitExpr(fnForm, indent)

  of "bound-fn*":
    if items.len < 2:
      raise newException(EmitterError, "bound-fn* requires a function argument")
    return emitExpr(items[1], indent)

  of "promise":
    if items.len < 1: return sp & "cljPromise()"
    return sp & "cljPromise()"

  of "->var":
    if items.len != 2:
      raise newException(EmitterError, "->var requires exactly 1 argument")
    let target = items[1]
    if target.kind == ckSymbol:
      return sp & "cljVar(" & emitExpr(target, 0) & ")"
    return sp & "cljVar(" & emitExpr(target, 0) & ")"

  of "group-by":
    if items.len != 3:
      raise newException(EmitterError, "group-by requires exactly 2 arguments")
    return sp & "cljGroupBy(" & emitExpr(items[1], 0) & ", " & emitExpr(items[2], 0) & ")"

  of "subs":
    if items.len < 3 or items.len > 4:
      raise newException(EmitterError, "subs requires 2 or 3 arguments")
    if items.len == 3:
      return sp & "cljSubs(" & emitExpr(items[1], 0) & ", cljInt(" & emitExpr(items[2], 0) & ").intVal)"
    else:
      return sp & "cljSubsRange(" & emitExpr(items[1], 0) & ", cljInt(" & emitExpr(items[2], 0) & ").intVal, cljInt(" & emitExpr(items[3], 0) & ").intVal)"

  of "get-in":
    if items.len < 3 or items.len > 4:
      raise newException(EmitterError, "get-in requires 2 or 3 arguments")
    if items.len == 3:
      return sp & "cljGetIn(" & emitExpr(items[1], 0) & ", " & emitExpr(items[2], 0) & ")"
    else:
      return sp & "cljGetIn(" & emitExpr(items[1], 0) & ", " & emitExpr(items[2], 0) & ", " & emitExpr(items[3], 0) & ")"

  of "update":
    if items.len < 4:
      raise newException(EmitterError, "update requires at least 3 arguments")
    var fArg: string
    if items[3].kind == ckSymbol:
      let rn = runtimeName(items[3].symName)
      if rn.len > 0:
        fArg = "cljFn(proc(args: seq[CljVal]): CljVal = " & rn & "(args))"
      else:
        fArg = mangleName(items[3].symName)
    else:
      fArg = emitExpr(items[3], 0)
    var extraArgs: seq[string] = @[]
    for i in 4..<items.len:
      extraArgs.add(emitExpr(items[i], 0))
    if extraArgs.len > 0:
      return sp & "cljUpdate(" & emitExpr(items[1], 0) & ", " & emitExpr(items[2], 0) & ", " & fArg & ", @[" & extraArgs.join(", ") & "])"
    else:
      return sp & "cljUpdate(" & emitExpr(items[1], 0) & ", " & emitExpr(items[2], 0) & ", " & fArg & ")"

  of "assoc-in":
    if items.len != 4:
      raise newException(EmitterError, "assoc-in requires exactly 3 arguments")
    return sp & "cljAssocIn(" & emitExpr(items[1], 0) & ", " & emitExpr(items[2], 0) & ", " & emitExpr(items[3], 0) & ")"

  of "and":
    if items.len < 2: return sp & "cljBool(true)"
    if items.len == 2: return emitExpr(items[1], indent)
    # (and a b c) => ternary: if a then (if b then c else false) else false
    # Generate as nested inline if
    let lastExpr = emitExpr(items[^1], 0)
    var r = lastExpr
    for i in countdown(items.len - 2, 1):
      r = "(if cljIsTruthy(" & emitExpr(items[i], 0) & "): " & r & " else: cljBool(false))"
    return sp & r

  of "or":
    if items.len < 2: return sp & "cljNil()"
    if items.len == 2: return emitExpr(items[1], indent)
    # (or a b c) => ternary: if a then a else (if b then b else c)
    let lastExpr = emitExpr(items[^1], 0)
    var r = lastExpr
    for i in countdown(items.len - 2, 1):
      let argCode = emitExpr(items[i], 0)
      r = "(if cljIsTruthy(" & argCode & "): " & argCode & " else: " & r & ")"
    return sp & r

  of "nil?":
    if items.len != 2:
      raise newException(EmitterError, "nil? requires exactly 1 argument")
    return sp & "cljBool(cljIsNil(" & emitExpr(items[1], 0) & "))"

  of "set!":
    if items.len != 3:
      raise newException(EmitterError, "set! requires exactly 2 arguments")
    let target = items[1]
    if target.kind != ckSymbol:
      raise newException(EmitterError, "set! target must be a symbol")
    return sp & mangleName(target.symName) & " = " & emitExpr(items[2], 0)

  of "set":
    if items.len != 2:
      raise newException(EmitterError, "set requires exactly 1 argument")
    let arg = items[1]
    case arg.kind
    of ckVector:
      var parts: seq[string] = @[]
      for item in arg.items:
        parts.add(emitExpr(item, 0))
      return sp & "cljSet(@[" & parts.join(", ") & "])"
    of ckList:
      return sp & "cljSet(" & emitExpr(arg, 0) & ")"
    else:
      return sp & "cljSet(@[" & emitExpr(arg, 0) & "])"

  of "range":
    if items.len < 1 or items.len > 4:
      raise newException(EmitterError, "range requires 0, 1, 2, or 3 arguments")
    if items.len == 1:
      return sp & "cljList(@[])"
    elif items.len == 2:
      return sp & "cljRange(" & emitExpr(items[1], 0) & ")"
    elif items.len == 3:
      return sp & "cljRange(" & emitExpr(items[1], 0) & ", " & emitExpr(items[2], 0) & ")"
    else:
      return sp & "cljRange3(" & emitExpr(items[1], 0) & ", " & emitExpr(items[2], 0) & ", " & emitExpr(items[3], 0) & ")"

  of "iterate":
    if items.len != 4:
      raise newException(EmitterError, "iterate requires 3 arguments (n, f, x)")
    let fnArg = items[2]
    let nArg = emitExpr(items[1], 0)
    let xArg = emitExpr(items[3], 0)
    if fnArg.kind == ckSymbol:
      let rn = runtimeName(fnArg.symName)
      if rn.len > 0:
        return sp & "cljIterate(" & nArg & ", cljFn(proc(args: seq[CljVal]): CljVal = " & rn & "(args)), " & xArg & ")"
      return sp & "cljIterate(" & nArg & ", cljFn(proc(args: seq[CljVal]): CljVal = " & mangleName(fnArg.symName) & "(args[0])), " & xArg & ")"
    else:
      return sp & "cljIterate(" & nArg & ", " & emitExpr(fnArg, 0) & ", " & xArg & ")"

  else:
    # ---- Nim interop: nim/module/function ----
    if op.startsWith("nim/") or op.startsWith("nim."):
      let parts = op.replace(".", "/").split("/")
      if parts.len >= 3:
        let module = parts[1]
        # Sanitize each part of the function chain for Nim identifier validity
        # (native Nim identifiers must NOT get the clj_ prefix)
        var mangledParts: seq[string] = @[]
        for p in parts[2..^1]:
          mangledParts.add(sanitizeNimIdent(p))
        var funcChain = mangledParts.join(".")
        # Strip ? suffix (Clojure convention) — not valid in Nim
        if funcChain.endsWith("?"):
          funcChain = funcChain[0..^2]
        var argParts: seq[string] = @[]
        for i in 1..<items.len:
          argParts.add(emitExpr(items[i], 0))
        # Known Nim module interop patterns
        case module
        of "math":
          requiredImports.incl("math")
          var nimArgs: seq[string] = @[]
          for a in argParts:
            nimArgs.add(a & ".floatVal")
          return sp & "cljFloat(" & funcChain & "(" & nimArgs.join(", ") & "))"
        of "strutils":
          requiredImports.incl("strutils")
          let strFns = ["endsWith", "startsWith", "contains", "find"]
          let strRetFns = ["replace", "strip", "toLower", "toUpper", "join"]
          let strIntFns = ["repeat", "count"]
          if funcChain in strFns:
            if argParts.len >= 1:
              var nimArgs: seq[string] = @[]
              nimArgs.add(argParts[0] & ".strVal")
              for i in 1..<argParts.len:
                nimArgs.add(argParts[i] & ".strVal")
              return sp & "cljBool(" & funcChain & "(" & nimArgs.join(", ") & "))"
          elif funcChain in strRetFns:
            if argParts.len >= 1:
              var nimArgs: seq[string] = @[]
              nimArgs.add(argParts[0] & ".strVal")
              for i in 1..<argParts.len:
                nimArgs.add(argParts[i] & ".strVal")
              return sp & "cljString(" & funcChain & "(" & nimArgs.join(", ") & "))"
          elif funcChain in strIntFns:
            # repeat(s, n), count(s, sub) — first arg string, rest int
            if argParts.len >= 2:
              var nimArgs: seq[string] = @[]
              nimArgs.add(argParts[0] & ".strVal")
              for i in 1..<argParts.len:
                nimArgs.add(argParts[i] & ".intVal")
              return sp & "cljString(" & funcChain & "(" & nimArgs.join(", ") & "))"
          elif funcChain == "split":
            if argParts.len >= 2:
              return sp & "cljList(" & funcChain & "(" & argParts[0] & ".strVal, " & argParts[1] & ".strVal).mapIt(cljString(it)))"
          return sp & funcChain & "(" & argParts.join(", ") & ")"
        of "times":
          requiredImports.incl("times")
          return sp & funcChain & "(" & argParts.join(", ") & ")"
        of "os":
          requiredImports.incl("os")
          return sp & "cljString(" & funcChain & "(" & argParts.join(", ") & "))"
        of "system":
          return sp & funcChain & "(" & argParts.join(", ") & ")"
        else:
          requiredImports.incl(module)
          return sp & funcChain & "(" & argParts.join(", ") & ")"
      elif parts.len == 2:
        return sp & "cljString(\"" & parts[1] & "\")"

    # ---- C FFI import: (c/import "header" :fn1 :fn2) ----
    if op == "c/import" or op == "c-ffi/import":
      if items.len < 2:
        raise newException(EmitterError, "c/import requires at least a header path")
      let header = items[1]
      if header.kind != ckString:
        raise newException(EmitterError, "c/import header must be a string")
      let headerPath = header.strVal
      var ffiProcs: seq[string] = @[]
      for i in 2..<items.len:
        if items[i].kind == ckKeyword:
          let fnName = items[i].kwName
          ffiProcs.add("proc " & fnName & "*(): clong {.importc, header: \"" & headerPath & "\".}")
        elif items[i].kind == ckSymbol:
          let fnName = items[i].symName
          ffiProcs.add("proc " & fnName & "*(): clong {.importc, header: \"" & headerPath & "\".}")
      return ffiProcs.join("\n" & sp)

    # ---- Known runtime functions ----
    let rn = runtimeName(op)
    if rn.len > 0:
      var argParts: seq[string] = @[]
      for i in 1..<items.len:
        argParts.add(emitExpr(items[i], indent, needsValue = true))
      # Variadic functions take seq[CljVal]
      let variadic = op in ["+", "-", "*", "/", "=", ">", "<", ">=", "<=", "not=",
                             "println", "prn", "print", "str", "pr-str",
                             "atom", "concat", "min", "max", "merge", "interleave",
                             "zipmap", "hash-map", "hash-set", "sorted-map", "sorted-map-by", "sorted-set", "sorted-set-by", "cons", "use-fixtures", "vswap!", "swap!", "tap>", "add-tap", "remove-tap", "add-watch", "remove-watch", "alter-var-root",
                             "array-map", "inf", "nan", "list",
                             "float", "int", "double", "long", "short", "byte",
                             "boolean", "num", "number",
                             "make-hierarchy", "derive", "underive", "ancestors",
                             "descendants", "parents", "isa?", "promise", "create-ns", "future",
                             "delay",
                             "aclone", "alength", "aget", "int-array", "identical?", "empty", "identity",
                             "conj",
                             "drop-last", "shuffle", "repeatedly", "fnil", "intern",
                             "println-str", "prn-str", "binding", "aset",
                             "volatile!", "deliver", "doall", "dorun",
                             "to-array", "into-array", "vector", "rand", "rand-int",
                             "rand-nth", "random-sample",
                             "assoc", "dissoc", "get", "get-in", "update", "assoc-in",
                             "select-keys",
                             "disj", "peek", "pop",
                             "transduce", "ex-info",
                             "compare", "subvec",
                             "require", "eval", "resolve", "random-uuid",
                             "vreset!", "restart-agent", "with-out-str",
                              "System/getProperty",
                              "dosync", "alter",
                              "json/write-value-as-string", "json/read-value",
                              "json/write-value-to-file", "json/read-value-from-file"]

      var call: string
      if variadic:
        call = rn & "(@[" & argParts.join(", ") & "])"
      else:
        call = rn & "(" & argParts.join(", ") & ")"
      return sp & call

    # ---- User-defined function call ----
    var args: seq[string] = @[]
    for i in 1..<items.len:
      args.add(emitExpr(items[i], indent))
    # Handle record constructor: Foo. -> strip trailing dot
    var callOp = op
    if callOp.endsWith("."):
      callOp = callOp[0..^2]
    let baseOp = if callOp.contains("/"): callOp.split("/")[1] else: callOp
    let resolvedOp = resolveNsAlias(callOp)
    if resolvedOp.contains("."):
      return sp & resolvedOp & "(@[" & args.join(", ") & "])"
    let mangled = mangleName(callOp)
    # Multi-arity function: wrap args in seq
    if callOp in multiArityFns:
      return sp & mangled & "(@[" & args.join(", ") & "])"
    if isLocalVar(callOp):
      # Local value (may be fn, map, set, vector, keyword) — use runtime dispatch
      return sp & "cljCall(" & mangled & ", @[" & args.join(", ") & "])"
    return sp & mangled & "(" & args.join(", ") & ")"

proc emitQuotedForm*(v: CljVal): string =
  case v.kind
  of ckSymbol:
    return "cljSymbol(\"" & v.symName & "\")"
  of ckKeyword:
    return "cljKeyword(\"" & v.kwName & "\")"
  of ckList:
    var parts: seq[string] = @[]
    for item in v.items:
      parts.add(emitQuotedForm(item))
    return "cljList(@[" & parts.join(", ") & "])"
  of ckVector:
    var parts: seq[string] = @[]
    for item in v.items:
      parts.add(emitQuotedForm(item))
    return "cljVector(@[" & parts.join(", ") & "])"
  of ckMap:
    var keyParts: seq[string] = @[]
    var valParts: seq[string] = @[]
    for i in 0..<v.mapKeys.len:
      keyParts.add(emitQuotedForm(v.mapKeys[i]))
      valParts.add(emitQuotedForm(v.mapVals[i]))
    return "cljMap(@[" & keyParts.join(", ") & "], @[" & valParts.join(", ") & "])"
  of ckSet:
    var parts: seq[string] = @[]
    for item in v.setItems:
      parts.add(emitQuotedForm(item))
    return "cljSet(@[" & parts.join(", ") & "])"
  else:
    return emitExpr(v, 0)

proc emitExpr*(v: CljVal, indent: int = 0, needsValue: bool = false): string =
  let sp = indentStr(indent)
  case v.kind
  of ckNil:
    return sp & "cljNil()"
  of ckBool:
    return sp & "cljBool(" & $v.boolVal & ")"
  of ckInt:
    return sp & "cljInt(" & $v.intVal & ")"
  of ckFloat:
    let fv = v.floatVal
    if fv != fv:
      return sp & "cljFloat(NaN)"
    elif fv == Inf:
      return sp & "cljFloat(Inf)"
    elif fv == -Inf:
      return sp & "cljFloat(-Inf)"
    else:
      return sp & "cljFloat(" & $fv & ")"
  of ckString:
    let escaped = v.strVal.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
    return sp & "cljString(\"" & escaped & "\")"
  of ckKeyword:
    return sp & "cljKeyword(\"" & v.kwName & "\")"
  of ckSymbol:
    let symName = resolveNsAlias(v.symName)
    # If symName contains a dot, it's a fully qualified lib module reference
    if symName.contains("."):
      return sp & symName
    let rn = runtimeName(symName)
    if rn.len > 0 and not isLocalVar(symName):
      # Check if the runtime function is variadic (takes seq[CljVal])
      let variadic = symName in variadicRuntimeFns
      if variadic:
        return sp & "cljFn(proc(args: seq[CljVal]): CljVal = " & rn & "(args))"
      else:
        return sp & "cljFn(proc(args: seq[CljVal]): CljVal = " & rn & "(args[0]))"
    if isLocalVar(symName):
      return sp & mangleName(symName)
    if symName in definedGlobals:
      # If the global is a user-defined function, emit a cljFn wrapper
      # so it can be passed as a first-class value.
      if symName in multiArityFns or definedFnArities.hasKey(symName):
        return sp & emitFnWrapper(symName)
      return sp & mangleName(symName)
    return sp & "cljSymbol(\"" & symName & "\")"
  of ckList:
    if v.items.len == 0:
      return sp & "cljList(@[])"
    # Macro-expand before emitting
    let expanded = macroexpand(v)
    if expanded == v:
      return emitSpecialForm(v.items, indent, needsValue)
    return emitExpr(expanded, indent, needsValue)
  of ckVector:
    var parts: seq[string] = @[]
    for item in v.items:
      parts.add(emitExpr(item, indent, needsValue = true))
    return sp & "cljVector(@[" & parts.join(", ") & "])"
  of ckMap:
    if v.mapKeys.len == 0:
      return sp & "cljMap(@[], @[])"
    var keyParts: seq[string] = @[]
    var valParts: seq[string] = @[]
    for i in 0..<v.mapKeys.len:
      keyParts.add(emitExpr(v.mapKeys[i], indent, needsValue = true))
      valParts.add(emitExpr(v.mapVals[i], indent, needsValue = true))
    return sp & "cljMap(@[" & keyParts.join(", ") & "], @[" & valParts.join(", ") & "])"
  of ckSet:
    var parts: seq[string] = @[]
    for item in v.setItems:
      parts.add(emitExpr(item, indent, needsValue = true))
    return sp & "cljSet(@[" & parts.join(", ") & "])"
  of ckFn:
    return sp & "cljFn(proc(args: seq[CljVal]): CljVal = discard cljNil())"
  of ckAtom:
    return sp & "cljAtom(" & emitExpr(v.atomVal, 0, needsValue = true) & ")"
  of ckTransient:
    return sp & "cljTransient(cljNil())"
  of ckAgent:
    return sp & "cljAgent(" & emitExpr(v.agentVal, 0) & ")"

proc emitBlock(items: seq[CljVal], indent: int, useResult: bool = false): string =
  if items.len == 0:
    return indentStr(indent) & "discard cljNil()"
  var lines: seq[string] = @[]
  for i, item in items:
    var code = emitExpr(item, indent)
    let stripped = code.strip()
    if i < items.len - 1:
      let firstNl = code.find("\n")
      let firstLine = if firstNl == -1: stripped else: code[0..<firstNl].strip()
      if firstNl == -1:
        if stripped.startsWith("let ") or stripped.startsWith("proc ") or stripped.startsWith("var ") or
           stripped.startsWith("discard "):
          code = indentStr(indent) & stripped
        else:
          code = indentStr(indent) & "discard " & stripped
      else:
        # Multi-line code — check if it starts with a var declaration that should be hoisted
        let codeLines = code.split("\n")
        let firstLine = codeLines[0].strip()
        if firstLine.startsWith("var ") and firstLine.contains(" = "):
          # Split: emit var decl directly at current indent, wrap remaining in IIFE
          if codeLines.len > 1:
            var restLines: seq[string] = @[]
            for li in 1..<codeLines.len:
              restLines.add(codeLines[li])
            let rest = restLines.join("\n").strip()
            if rest.len > 0:
              let indentedRest = indentCode(restLines.join("\n"), 1)
              code = indentStr(indent) & firstLine & "\n" & indentStr(indent) & "discard ((proc (): CljVal =\n" & indentedRest & "\n" & indentStr(indent) & ")())"
            else:
              code = indentStr(indent) & firstLine
          else:
            code = indentStr(indent) & firstLine
        else:
          let indentedCode = indentCode(code, 1)
          code = indentStr(indent) & "discard ((proc (): CljVal =\n" & indentedCode & "\n" & indentStr(indent) & ")())"
    elif useResult:
      if stripped.startsWith("discard "):
        code = indentStr(indent) & "result = " & stripped[8..^1]
      elif not stripped.startsWith("result = "):
        let firstNl = code.find("\n")
        if firstNl == -1:
          code = indentStr(indent) & "result = " & stripped
        else:
          let firstLine = code[0..<firstNl].strip()
          let rest = code[firstNl..^1]
          code = indentStr(indent) & "result = " & firstLine & rest
    lines.add(code)
  return lines.join("\n")

proc emitProgramInternal(forms: seq[CljVal]): string =
  scopeStack = @[]
  pushScope()
  requiredImports = initHashSet[string]()
  loopStack = @[]
  loopResultVar = ""
  nsAliases = @[]
  libNsPrefixes = @[]
  definedGlobals = initHashSet[string]()
  definedFnArities = initTable[string, int]()
  multiArityFns = initHashSet[string]()
  var headerLines: seq[string] = @[
    "# Generated by Bara Lang",
    "import cljnim_runtime",
  ]

  var defs: seq[string] = @[]
  var mainForms: seq[string] = @[]

  # Iterative worklist-based form processing (avoids deep recursion)
  type WorkItem = tuple[form: CljVal, isLast: bool]
  var worklist: seq[WorkItem] = @[]

  proc processOneForm(form: CljVal, isLast: bool) =
    let expanded = macroexpand(form)
    let ef = if expanded.kind == ckList: expanded else: form
    let headSym = ef.kind == ckList and ef.items.len > 0 and
                   ef.items[0].kind == ckSymbol
    let headName = if headSym: ef.items[0].symName else: ""
    # Recurse into (do ...) forms produced by macro expansion
    if headSym and headName == "do":
      let subForms = ef.items[1..^1]
      for j in countdown(subForms.len - 1, 0):
        let subLast = isLast and (j == subForms.len - 1)
        worklist.add((subForms[j], subLast))
      return
    let isDef = headSym and headName in ["def", "defn", "defn-", "defprotocol", "defrecord", "deftype", "defmulti", "defmethod", "var"]
    let isMacro = headSym and headName in ["defmacro"]
    let isNs = headSym and headName == "ns"
    if isNs:
      discard
    elif isDef or isMacro:
      let defCode = emitExpr(ef, 0)
      defs.add(defCode)
    else:
      let code = emitExpr(ef, 2, needsValue = isLast)
      let stripped = code.strip()
      if stripped.startsWith("echo ") or stripped.startsWith("discard ") or
         stripped.startsWith("var ") or stripped.startsWith("while ") or
         stripped.startsWith("if ") or stripped.startsWith("block:") or
         stripped.startsWith("for ") or stripped.startsWith("try"):
        mainForms.add(code)
      elif isLast:
        mainForms.add(indentStr(2) & "echo cljRepr(" & stripped & ")")
      else:
        mainForms.add(indentStr(2) & "discard cljRepr(" & stripped & ")")

  proc unwrapOneForm(form: CljVal, isLast: bool) =
    if form.kind == ckList and form.items.len > 0 and
       form.items[0].kind == ckSymbol and form.items[0].symName == "do":
      let subForms = form.items[1..^1]
      for j in countdown(subForms.len - 1, 0):
        let subLast = isLast and (j == subForms.len - 1)
        worklist.add((subForms[j], subLast))
    elif form.kind == ckList and form.items.len == 2 and
         form.items[0].kind == ckSymbol and form.items[0].symName == "splice-unwrap":
      let inner = form.items[1]
      if inner.kind == ckVector:
        for j in countdown(inner.items.len - 1, 0):
          let subLast = isLast and (j == inner.items.len - 1)
          worklist.add((inner.items[j], subLast))
      else:
        processOneForm(form, isLast)
    else:
      processOneForm(form, isLast)

  for i in countdown(forms.len - 1, 0):
    worklist.add((forms[i], i == forms.len - 1))

  while worklist.len > 0:
    let (item, itemIsLast) = worklist.pop()
    if item.kind == ckList and item.items.len > 0 and item.items[0].kind == ckSymbol:
      unwrapOneForm(item, itemIsLast)

  var lines = headerLines
  # Add collected Nim imports
  for imp in requiredImports:
    lines.add("import " & imp)
  lines.add("")
  for d in defs:
    lines.add(d)

  if mainForms.len > 0:
    lines.add("")
    if emitLibMode:
      # Lib mode: emit main forms at top level (no when isMainModule guard)
      for form in mainForms:
        lines.add(form)
    else:
      if emitEntryProcName.len > 0:
        lines.add("proc " & emitEntryProcName & "*(args: seq[CljVal] = @[]): CljVal =")
        for form in mainForms:
          lines.add(form)
        lines.add("")
        lines.add("when isMainModule:")
        lines.add("  discard " & emitEntryProcName & "()")
      else:
        lines.add("when isMainModule:")
        for form in mainForms:
          lines.add(form)

  return lines.join("\n") & "\n"

proc emitProgram*(forms: seq[CljVal]): string =
  emitLibMode = false
  emitProgramInternal(forms)

proc emitProgramLib*(forms: seq[CljVal]): string =
  emitLibMode = true
  emitProgramInternal(forms)
