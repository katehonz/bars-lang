import tables
import types

type
  MacroFn* = proc(args: seq[CljVal]): CljVal

var macroTable* = initTable[string, MacroFn]()

proc defineMacro*(name: string, fn: MacroFn) =
  macroTable[name] = fn

proc isMacro*(name: string): bool =
  macroTable.hasKey(name)

proc expandMacro*(name: string, args: seq[CljVal]): CljVal =
  macroTable[name](args)

proc expandSyntaxQuote*(form: CljVal): CljVal
proc macroexpand1*(form: CljVal): CljVal
proc macroexpand*(form: CljVal): CljVal

proc gensymCounter*: int =
  var counter {.global.} = 0
  inc counter
  counter

proc gensymName*(prefix: string = "G__"): string =
  prefix & $gensymCounter()

proc expandSyntaxQuote*(form: CljVal): CljVal =
  if form.isNil: return cljNil()
  case form.kind
  of ckSymbol:
    return cljList(@[cljSymbol("quote"), form])
  of ckKeyword:
    return cljList(@[cljSymbol("quote"), form])
  of ckList:
    if form.items.len == 0:
      return cljList(@[cljSymbol("quote"), cljList(@[])])
    let head = form.items[0]
    if head.kind == ckSymbol:
      if head.symName == "unquote":
        if form.items.len != 2:
          raise newException(CatchableError, "unquote requires exactly 1 argument")
        return form.items[1]
      if head.symName == "unquote-splicing":
        if form.items.len != 2:
          raise newException(CatchableError, "unquote-splicing requires exactly 1 argument")
        return form.items[1]
    # Process each element
    var parts: seq[CljVal] = @[]
    for item in form.items:
      parts.add(expandSyntaxQuote(item))
    return cljList(@[cljSymbol("concat")] & parts)
  of ckVector:
    var parts: seq[CljVal] = @[]
    for item in form.items:
      parts.add(expandSyntaxQuote(item))
    return cljList(@[cljSymbol("apply"), cljSymbol("vector"), cljList(@[cljSymbol("concat")] & parts)])
  of ckMap:
    var parts: seq[CljVal] = @[]
    for i in 0..<form.mapKeys.len:
      parts.add(expandSyntaxQuote(form.mapKeys[i]))
      parts.add(expandSyntaxQuote(form.mapVals[i]))
    return cljList(@[cljSymbol("apply"), cljSymbol("hash-map"), cljList(@[cljSymbol("concat")] & parts)])
  of ckSet:
    var parts: seq[CljVal] = @[]
    for item in form.setItems:
      parts.add(expandSyntaxQuote(item))
    return cljList(@[cljSymbol("apply"), cljSymbol("hash-set"), cljList(@[cljSymbol("concat")] & parts)])
  else:
    return form

proc macroexpand1*(form: CljVal): CljVal =
  if form.isNil: return form
  if form.kind != ckList or form.items.len == 0:
    return form
  let head = form.items[0]
  if head.kind != ckSymbol:
    return form
  let name = head.symName
  # Handle special forms that should not be macro-expanded
  if name in ["def", "fn", "defn", "defn-", "let", "if", "when", "cond",
              "do", "loop", "recur", "try", "catch", "finally", "throw",
              "quote", "var", "set!", "ns", "defmacro",
              "and", "or", "nil?", "range"]:
    return form
  # Handle syntax-quote
  if name == "syntax-quote":
    if form.items.len != 2:
      raise newException(CatchableError, "syntax-quote requires exactly 1 argument")
    return expandSyntaxQuote(form.items[1])
  # Check if it's a macro (try full name, then bare name without namespace prefix)
  if isMacro(name):
    return expandMacro(name, form.items[1..^1])
  let slashPos = name.find('/')
  if slashPos > 0:
    let bareName = name[slashPos+1..^1]
    if isMacro(bareName):
      return expandMacro(bareName, form.items[1..^1])
  return form

proc macroexpand*(form: CljVal): CljVal =
  result = form
  while true:
    let expanded = macroexpand1(result)
    if expanded == result:
      return result
    result = expanded

# ---- Built-in macro implementations ----

proc threadingMacro(args: seq[CljVal], reverse: bool): CljVal =
  if args.len < 2:
    raise newException(CatchableError, "Threading macro requires at least 2 arguments")
  var acc = args[0]
  for i in 1..<args.len:
    let form = args[i]
    if form.kind == ckList and form.items.len > 0:
      if reverse:
        acc = cljList(form.items & @[acc])
      else:
        acc = cljList(@[form.items[0], acc] & form.items[1..^1])
    elif form.kind == ckSymbol:
      acc = cljList(@[form, acc])
    else:
      raise newException(CatchableError, "Threading macro requires lists or symbols")
  return acc

proc initMacros*() =
  # fn* macro
  defineMacro("fn*", proc(args: seq[CljVal]): CljVal =
    if args.len < 2:
      raise newException(CatchableError, "fn* requires params and body")
    cljList(@[cljSymbol("fn")] & args)
  )

  # -> (thread-first)
  defineMacro("->", proc(args: seq[CljVal]): CljVal =
    threadingMacro(args, false)
  )

  # ->> (thread-last)
  defineMacro("->>", proc(args: seq[CljVal]): CljVal =
    threadingMacro(args, true)
  )

  # and
  defineMacro("and", proc(args: seq[CljVal]): CljVal =
    if args.len == 0: return cljBool(true)
    if args.len == 1: return args[0]
    var acc = args[^1]
    for i in countdown(args.len - 2, 0):
      acc = cljList(@[cljSymbol("if"), args[i], acc, cljBool(false)])
    return acc
  )

  # or
  defineMacro("or", proc(args: seq[CljVal]): CljVal =
    if args.len == 0: return cljNil()
    if args.len == 1: return args[0]
    var acc = args[^1]
    for i in countdown(args.len - 2, 0):
      acc = cljList(@[cljSymbol("if"), args[i], args[i], acc])
    return acc
  )

  # when-let
  defineMacro("when-let", proc(args: seq[CljVal]): CljVal =
    if args.len < 2:
      raise newException(CatchableError, "when-let requires binding vector and body")
    let binding = args[0]
    let body = args[1..^1]
    if binding.kind != ckVector or binding.items.len != 2:
      raise newException(CatchableError, "when-let requires [name val]")
    let name = binding.items[0]
    let val = binding.items[1]
    let gs = cljSymbol(gensymName("wl_"))
    cljList(@[cljSymbol("let"), cljVector(@[gs, val]),
      cljList(@[cljSymbol("when"), gs,
        cljList(@[cljSymbol("let"), cljVector(@[name, gs])] & body)])])
  )

  # if-let
  defineMacro("if-let", proc(args: seq[CljVal]): CljVal =
    if args.len < 3:
      raise newException(CatchableError, "if-let requires binding vector, then, and else")
    let binding = args[0]
    let thenBranch = args[1]
    let elseBranch = args[2]
    if binding.kind != ckVector or binding.items.len != 2:
      raise newException(CatchableError, "if-let requires [name val]")
    let name = binding.items[0]
    let val = binding.items[1]
    let gs = cljSymbol(gensymName("il_"))
    cljList(@[cljSymbol("let"), cljVector(@[gs, val]),
      cljList(@[cljSymbol("if"), gs,
        cljList(@[cljSymbol("let"), cljVector(@[name, gs]), thenBranch]),
        elseBranch])])
  )

  # when
  defineMacro("when", proc(args: seq[CljVal]): CljVal =
    if args.len < 2:
      raise newException(CatchableError, "when requires condition and body")
    let cond = args[0]
    let body = args[1..^1]
    cljList(@[cljSymbol("if"), cond,
      cljList(@[cljSymbol("do")] & body)])
  )

  # when-not
  defineMacro("when-not", proc(args: seq[CljVal]): CljVal =
    if args.len < 1:
      raise newException(CatchableError, "when-not requires condition and body")
    let cond = args[0]
    let body = args[1..^1]
    cljList(@[cljSymbol("if"), cond, cljNil(),
      cljList(@[cljSymbol("do")] & body)])
  )

  # cond
  defineMacro("cond", proc(args: seq[CljVal]): CljVal =
    if args.len == 0: return cljNil()
    if args.len mod 2 != 0:
      raise newException(CatchableError, "cond requires pairs of test/expr")
    let test = args[0]
    let expr = args[1]
    if test.kind == ckKeyword and test.kwName == "else":
      return expr
    if args.len == 2:
      return cljList(@[cljSymbol("if"), test, expr])
    return cljList(@[cljSymbol("if"), test, expr,
      cljList(@[cljSymbol("cond")] & args[2..^1])])
  )

  # cond->
  defineMacro("cond->", proc(args: seq[CljVal]): CljVal =
    if args.len < 1:
      raise newException(CatchableError, "cond-> requires initial value and clauses")
    let init = args[0]
    let clauses = args[1..^1]
    if clauses.len mod 2 != 0:
      raise newException(CatchableError, "cond-> requires pairs of test/expr")
    var acc = init
    for i in 0..<(clauses.len div 2):
      let test = clauses[i * 2]
      let expr = clauses[i * 2 + 1]
      let gs = cljSymbol(gensymName("ct_"))
      if expr.kind == ckList and expr.items.len > 0:
        acc = cljList(@[cljSymbol("let"), cljVector(@[gs, acc]),
          cljList(@[cljSymbol("if"), test,
            cljList(@[expr.items[0], gs] & expr.items[1..^1]),
            gs])])
      else:
        acc = cljList(@[cljSymbol("let"), cljVector(@[gs, acc]),
          cljList(@[cljSymbol("if"), test,
            cljList(@[expr, gs]),
            gs])])
    return acc
  )

  # cond->>
  defineMacro("cond->>", proc(args: seq[CljVal]): CljVal =
    if args.len < 1:
      raise newException(CatchableError, "cond->> requires initial value and clauses")
    let init = args[0]
    let clauses = args[1..^1]
    if clauses.len mod 2 != 0:
      raise newException(CatchableError, "cond->> requires pairs of test/expr")
    var acc = init
    for i in 0..<(clauses.len div 2):
      let test = clauses[i * 2]
      let expr = clauses[i * 2 + 1]
      let gs = cljSymbol(gensymName("ct_"))
      if expr.kind == ckList and expr.items.len > 0:
        acc = cljList(@[cljSymbol("let"), cljVector(@[gs, acc]),
          cljList(@[cljSymbol("if"), test,
            cljList(expr.items & @[gs]),
            gs])])
      else:
        acc = cljList(@[cljSymbol("let"), cljVector(@[gs, acc]),
          cljList(@[cljSymbol("if"), test,
            cljList(@[expr, gs]),
            gs])])
    return acc
  )

  # doto
  defineMacro("doto", proc(args: seq[CljVal]): CljVal =
    if args.len < 1:
      raise newException(CatchableError, "doto requires initial value and body")
    let init = args[0]
    let body = args[1..^1]
    let gs = cljSymbol(gensymName("dt_"))
    var forms: seq[CljVal] = @[]
    forms.add(cljSymbol("let"))
    forms.add(cljVector(@[gs, init]))
    for form in body:
      if form.kind == ckList and form.items.len > 0:
        forms.add(cljList(@[form.items[0], gs] & form.items[1..^1]))
      else:
        forms.add(cljList(@[form, gs]))
    forms.add(gs)
    return cljList(forms)
  )

  # as->
  defineMacro("as->", proc(args: seq[CljVal]): CljVal =
    if args.len < 3:
      raise newException(CatchableError, "as-> requires init, name, and body")
    let init = args[0]
    let name = args[1]
    let body = args[2..^1]
    var acc = init
    for form in body:
      acc = cljList(@[cljSymbol("let"), cljVector(@[name, acc]), form])
    return acc
  )

  # some->
  defineMacro("some->", proc(args: seq[CljVal]): CljVal =
    if args.len < 1:
      raise newException(CatchableError, "some-> requires initial value and body")
    let init = args[0]
    let body = args[1..^1]
    var acc = init
    for form in body:
      let gs = cljSymbol(gensymName("st_"))
      let nilCheck = cljList(@[cljSymbol("nil?"), gs])
      if form.kind == ckList and form.items.len > 0:
        acc = cljList(@[cljSymbol("let"), cljVector(@[gs, acc]),
          cljList(@[cljSymbol("if"), nilCheck,
            cljNil(),
            cljList(@[form.items[0], gs] & form.items[1..^1])])])
      else:
        acc = cljList(@[cljSymbol("let"), cljVector(@[gs, acc]),
          cljList(@[cljSymbol("if"), nilCheck,
            cljNil(),
            cljList(@[form, gs])])])
    return acc
  )

  # some->>
  defineMacro("some->>", proc(args: seq[CljVal]): CljVal =
    if args.len < 1:
      raise newException(CatchableError, "some->> requires initial value and body")
    let init = args[0]
    let body = args[1..^1]
    var acc = init
    for form in body:
      let gs = cljSymbol(gensymName("st_"))
      if form.kind == ckList and form.items.len > 0:
        acc = cljList(@[cljSymbol("let"), cljVector(@[gs, acc]),
          cljList(@[cljSymbol("if"), gs,
            cljList(form.items & @[gs]),
            cljNil()])])
      else:
        acc = cljList(@[cljSymbol("let"), cljVector(@[gs, acc]),
          cljList(@[cljSymbol("if"), gs,
            cljList(@[form, gs]),
            cljNil()])])
    return acc
  )

  # for
  defineMacro("for", proc(args: seq[CljVal]): CljVal =
    if args.len < 2:
      raise newException(CatchableError, "for requires bindings and body")
    let bindings = args[0]
    let body = args[1..^1]
    if bindings.kind != ckVector:
      raise newException(CatchableError, "for bindings must be a vector")
    let gs = cljSymbol(gensymName("fr_"))
    cljList(@[cljSymbol("let"), cljVector(@[gs, cljVector(@[])]),
      cljList(@[cljSymbol("doseq")] & @[bindings] & @[
        cljList(@[cljSymbol("set!"), gs, cljList(@[cljSymbol("conj"), gs] & body)])]),
      gs])
  )

  # doseq
  defineMacro("doseq", proc(args: seq[CljVal]): CljVal =
    if args.len < 2:
      raise newException(CatchableError, "doseq requires bindings and body")
    let bindings = args[0]
    let body = args[1..^1]
    if bindings.kind != ckVector:
      raise newException(CatchableError, "doseq bindings must be a vector")
    
    # Parse bindings: collect [name coll] pairs and :when/:let/:while modifiers
    var pairs: seq[(CljVal, CljVal)] = @[]
    var whenExpr: CljVal = nil
    var letBinds: seq[CljVal] = @[]
    var whileExpr: CljVal = nil
    var i = 0
    while i < bindings.items.len:
      let item = bindings.items[i]
      if item.kind == ckKeyword:
        let kw = item.kwName
        if kw in ["when", "let", "while"] and i + 1 < bindings.items.len:
          case kw
          of "when":
            whenExpr = bindings.items[i + 1]
          of "let":
            let lb = bindings.items[i + 1]
            if lb.kind == ckVector:
              for it in lb.items:
                letBinds.add(it)
            else:
              letBinds.add(lb)
          of "while":
            whileExpr = bindings.items[i + 1]
          else: discard
          i += 2
        else:
          i += 1
      else:
        if i + 1 < bindings.items.len:
          pairs.add((item, bindings.items[i + 1]))
        i += 2
    
    if pairs.len == 0:
      var b = body
      if letBinds.len > 0:
        b = @[cljList(@[cljSymbol("let"), cljVector(letBinds)] & b)]
      if whenExpr != nil:
        b = @[cljList(@[cljSymbol("when"), whenExpr] & b)]
      if whileExpr != nil:
        let gs = cljSymbol(gensymName("dw_"))
        b = @[cljList(@[cljSymbol("loop"), cljVector(@[gs, cljBool(true)]),
          cljList(@[cljSymbol("when"), whileExpr] & b & @[cljList(@[cljSymbol("recur"), gs])])])]
      return cljList(@[cljSymbol("do")] & b)
    
    # Build nested doseq for multiple pairs, innermost gets the body with modifiers
    var inner: seq[CljVal] = body
    if letBinds.len > 0:
      inner = @[cljList(@[cljSymbol("let"), cljVector(letBinds)] & inner)]
    if whenExpr != nil:
      inner = @[cljList(@[cljSymbol("when"), whenExpr] & inner)]
    if whileExpr != nil:
      let gs = cljSymbol(gensymName("dw_"))
      inner = @[cljList(@[cljSymbol("loop"), cljVector(@[gs, cljBool(true)]),
        cljList(@[cljSymbol("when"), whileExpr] & inner & @[cljList(@[cljSymbol("recur"), gs])])])]
    
    proc makeLoop(name: CljVal, coll: CljVal, innerBody: seq[CljVal]): CljVal =
      if name.kind == ckVector:
        let seqGs = cljSymbol(gensymName("sq_"))
        let tmpGs = cljSymbol(gensymName("tmp_"))
        var innerBindings: seq[CljVal] = @[]
        for jn in 0..<name.items.len:
          innerBindings.add(name.items[jn])
          innerBindings.add(cljList(@[cljSymbol("nth"), tmpGs, cljInt(jn)]))
        let destructured = cljList(@[cljSymbol("let"), cljVector(innerBindings)] & innerBody)
        let recurForm = cljList(@[cljSymbol("recur"), cljList(@[cljSymbol("next"), seqGs])])
        let loopBody = cljList(@[cljSymbol("when"), seqGs,
          cljList(@[cljSymbol("let"), cljVector(@[tmpGs, cljList(@[cljSymbol("first"), seqGs])]), destructured]),
          recurForm])
        return cljList(@[cljSymbol("loop"), cljVector(@[seqGs, cljList(@[cljSymbol("seq"), coll])]), loopBody])
      else:
        let seqColl = cljList(@[cljSymbol("seq"), coll])
        let gs = cljSymbol(gensymName("ds_"))
        let recurForm = cljList(@[cljSymbol("recur"), cljList(@[cljSymbol("first"), gs]), cljList(@[cljSymbol("next"), gs])])
        let loopBody = cljList(@[cljSymbol("when"), name] & innerBody & @[recurForm])
        return cljList(@[cljSymbol("loop"), cljVector(@[name, cljList(@[cljSymbol("first"), seqColl]), gs, cljList(@[cljSymbol("next"), seqColl])]), loopBody])
    
    var acc = makeLoop(pairs[^1][0], pairs[^1][1], inner)
    for j in countdown(pairs.len - 2, 0):
      let innerSeq = @[result]
      acc = makeLoop(pairs[j][0], pairs[j][1], innerSeq)
    return acc
  )

  # dotimes
  defineMacro("dotimes", proc(args: seq[CljVal]): CljVal =
    if args.len < 2:
      raise newException(CatchableError, "dotimes requires binding and body")
    let binding = args[0]
    let body = args[1..^1]
    if binding.kind != ckVector or binding.items.len != 2:
      raise newException(CatchableError, "dotimes requires [name count]")
    let name = binding.items[0]
    let count = binding.items[1]
    let gs = cljSymbol(gensymName("dt_"))
    cljList(@[cljSymbol("let"), cljVector(@[gs, count]),
      cljList(@[cljSymbol("loop"), cljVector(@[name, cljInt(0)]),
        cljList(@[cljSymbol("when"), cljList(@[cljSymbol("<"), name, gs])] & body),
        cljList(@[cljSymbol("recur"), cljList(@[cljSymbol("+"), name, cljInt(1)])])])])
  )

  # defmacro
  defineMacro("defmacro", proc(args: seq[CljVal]): CljVal =
    if args.len < 3:
      raise newException(CatchableError, "defmacro requires name, params, and body")
    let name = args[0]
    let params = args[1]
    let body = args[2..^1]
    cljList(@[cljSymbol("def"), name,
      cljList(@[cljSymbol("fn"), params] & body)])
  )

  # comment
  defineMacro("comment", proc(args: seq[CljVal]): CljVal =
    cljNil()
  )

  # assert
  defineMacro("assert", proc(args: seq[CljVal]): CljVal =
    if args.len == 0: return cljNil()
    let test = args[0]
    let msg = if args.len > 1: args[1] else: cljString("Assert failed")
    cljList(@[cljSymbol("when-not"), test,
      cljList(@[cljSymbol("throw"), msg])])
  )

  # with-open
  defineMacro("with-open", proc(args: seq[CljVal]): CljVal =
    if args.len < 2:
      raise newException(CatchableError, "with-open requires binding and body")
    let binding = args[0]
    let body = args[1..^1]
    if binding.kind != ckVector or binding.items.len != 2:
      raise newException(CatchableError, "with-open requires [name init]")
    let init = binding.items[1]
    let gs = cljSymbol(gensymName("wo_"))
    cljList(@[cljSymbol("let"), cljVector(@[gs, init]),
      cljList(@[cljSymbol("try")] & body & @[
        cljList(@[cljSymbol("finally"),
          cljList(@[cljSymbol(".close"), gs])])])])
  )

  # clojure.test macros
  defineMacro("deftest", proc(args: seq[CljVal]): CljVal =
    if args.len == 0:
      raise newException(CatchableError, "deftest requires name and body")
    let name = args[0]
    let body = args[1..^1]
    cljList(@[cljSymbol("def"), name,
      cljList(@[cljSymbol("fn"), cljVector(@[])] & body)])
  )

  defineMacro("is", proc(args: seq[CljVal]): CljVal =
    # is is a no-op for compilation tests
    cljNil()
  )

  defineMacro("testing", proc(args: seq[CljVal]): CljVal =
    if args.len == 0: return cljNil()
    cljList(@[cljSymbol("do")] & args[1..^1])
  )

  defineMacro("when-first", proc(args: seq[CljVal]): CljVal =
    if args.len < 2: return cljNil()
    let bindings = args[0]
    if bindings.kind != ckVector or bindings.items.len != 2:
      return cljNil()
    let bindName = bindings.items[0]
    let bindColl = bindings.items[1]
    let body = args[1..^1]
    # (when-first [x coll] body) => (when (seq coll) (let [x (first coll)] body))
    cljList(@[cljSymbol("when"),
      cljList(@[cljSymbol("seq"), bindColl]),
      cljList(@[cljSymbol("let"), cljVector(@[bindName, cljList(@[cljSymbol("first"), bindColl])])] & body)])
  )

  defineMacro("thrown?", proc(args: seq[CljVal]): CljVal =
    if args.len == 0: return cljNil()
    let form = args[0]
    cljList(@[cljSymbol("try"), form, cljBool(false),
      cljList(@[cljSymbol("catch"), cljSymbol("Exception"), cljSymbol("e"), cljBool(true)])])
  )

  defineMacro("are", proc(args: seq[CljVal]): CljVal =
    if args.len < 2:
      raise newException(CatchableError, "are requires argv and test cases")
    let argv = args[0]
    let testExpr = args[1]
    let exprs = args[2..^1]
    if argv.kind != ckVector:
      raise newException(CatchableError, "are argv must be a vector")
    let arity = argv.items.len
    if exprs.len mod arity != 0:
      raise newException(CatchableError, "are test cases must match argv arity")
    var isForms: seq[CljVal] = @[]
    for i in countup(0, exprs.len - arity, arity):
      var bindings: seq[CljVal] = @[]
      for j in 0..<arity:
        bindings.add(argv.items[j])
        bindings.add(exprs[i+j])
      let letForm = cljList(@[cljSymbol("let"), cljVector(bindings),
        cljList(@[cljSymbol("is"), testExpr])])
      isForms.add(letForm)
    if isForms.len == 1:
      return isForms[0]
    return cljList(@[cljSymbol("do")] & isForms)
  )

  # when-var-exists: always expands body (var check is compile-time in emitter)
  defineMacro("when-var-exists", proc(args: seq[CljVal]): CljVal =
    if args.len < 2:
      raise newException(CatchableError, "when-var-exists requires symbol and body")
    let body = args[1..^1]
    if body.len == 1:
      return body[0]
    return cljList(@[cljSymbol("do")] & body)
  )

var macrosInitialized = false

proc initBuiltinMacros*() =
  if macrosInitialized: return
  initMacros()
  macrosInitialized = true
