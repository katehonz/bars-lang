import unittest, tables
import ../src/types
import ../src/macros

# Helper: check that a value is a list with given head symbol
proc isListWithHead(v: CljVal, head: string): bool =
  v.kind == ckList and v.items.len > 0 and v.items[0].kind == ckSymbol and v.items[0].symName == head

# Helper: check that a value is a symbol with given name
proc isSym(v: CljVal, name: string): bool =
  v.kind == ckSymbol and v.symName == name

suite "Macros - initBuiltinMacros":
  setup:
    initBuiltinMacros()

suite "Macros - -> thread-first":
  setup:
    initBuiltinMacros()

  test "-> with symbol step":
    let form = cljList(@[cljSymbol("->"), cljInt(5), cljSymbol("inc")])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("inc")
    check expanded.items.len == 2
    check expanded.items[1].kind == ckInt
    check expanded.items[1].intVal == 5

  test "-> with list step":
    let form = cljList(@[cljSymbol("->"), cljInt(5),
      cljList(@[cljSymbol("+"), cljInt(3)])])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("+")
    check expanded.items.len == 3
    check expanded.items[1].kind == ckInt
    check expanded.items[1].intVal == 5
    check expanded.items[2].kind == ckInt
    check expanded.items[2].intVal == 3

  test "-> chained":
    let form = cljList(@[cljSymbol("->"), cljInt(5),
      cljSymbol("inc"),
      cljList(@[cljSymbol("*"), cljInt(2)])])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("*")
    check expanded.items.len == 3
    check expanded.items[1].isListWithHead("inc")
    check expanded.items[1].items.len == 2
    check expanded.items[1].items[1].intVal == 5
    check expanded.items[2].intVal == 2

  test "-> too few args raises":
    let form = cljList(@[cljSymbol("->"), cljInt(5)])
    expect CatchableError:
      discard macroexpand(form)

suite "Macros - ->> thread-last":
  setup:
    initBuiltinMacros()

  test "->> with list step":
    let form = cljList(@[cljSymbol("->>"), cljInt(5),
      cljList(@[cljSymbol("+"), cljInt(3)])])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("+")
    check expanded.items.len == 3
    check expanded.items[1].intVal == 3
    check expanded.items[2].intVal == 5

  test "->> chained":
    let form = cljList(@[cljSymbol("->>"), cljInt(5),
      cljList(@[cljSymbol("conj"), cljInt(1)])])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("conj")
    check expanded.items[1].intVal == 1
    check expanded.items[2].intVal == 5

suite "Macros - and (not expanded by macroexpand)":
  setup:
    initBuiltinMacros()

  test "and is left untouched by macroexpand":
    let form = cljList(@[cljSymbol("and"), cljSymbol("a"), cljSymbol("b")])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("and")
    check expanded.items.len == 3

  test "and macro implementation directly":
    let andFn = macroTable["and"]
    let result = andFn(@[cljSymbol("a"), cljSymbol("b")])
    check result.isListWithHead("if")
    check result.items.len == 4
    check result.items[1].isSym("a")
    check result.items[2].isSym("b")
    check result.items[3].kind == ckBool
    check result.items[3].boolVal == false

  test "and empty directly":
    let andFn = macroTable["and"]
    let result = andFn(@[])
    check result.kind == ckBool
    check result.boolVal == true

  test "and single directly":
    let andFn = macroTable["and"]
    let result = andFn(@[cljSymbol("x")])
    check result.isSym("x")

  test "and three args directly":
    let andFn = macroTable["and"]
    let result = andFn(@[cljSymbol("a"), cljSymbol("b"), cljSymbol("c")])
    check result.isListWithHead("if")
    check result.items[1].isSym("a")
    check result.items[2].isListWithHead("if")
    check result.items[3].kind == ckBool
    check result.items[3].boolVal == false

suite "Macros - or (not expanded by macroexpand)":
  setup:
    initBuiltinMacros()

  test "or is left untouched by macroexpand":
    let form = cljList(@[cljSymbol("or"), cljSymbol("a"), cljSymbol("b")])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("or")

  test "or empty directly":
    let orFn = macroTable["or"]
    let result = orFn(@[])
    check result.kind == ckNil

  test "or single directly":
    let orFn = macroTable["or"]
    let result = orFn(@[cljSymbol("x")])
    check result.isSym("x")

  test "or two args directly":
    let orFn = macroTable["or"]
    let result = orFn(@[cljSymbol("a"), cljSymbol("b")])
    check result.isListWithHead("if")
    check result.items.len == 4
    check result.items[1].isSym("a")
    check result.items[2].isSym("a")
    check result.items[3].isSym("b")

suite "Macros - when (not expanded by macroexpand)":
  setup:
    initBuiltinMacros()

  test "when is left untouched by macroexpand":
    let form = cljList(@[cljSymbol("when"), cljSymbol("x"), cljInt(1)])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("when")

  test "when macro directly":
    let whenFn = macroTable["when"]
    let result = whenFn(@[cljSymbol("x"), cljInt(1), cljInt(2)])
    check result.isListWithHead("if")
    check result.items.len == 3
    check result.items[1].isSym("x")
    check result.items[2].isListWithHead("do")
    check result.items[2].items.len == 3

  test "when too few args raises":
    expect CatchableError:
      discard macroTable["when"](@[cljSymbol("x")])

suite "Macros - when-not":
  setup:
    initBuiltinMacros()

  test "when-not expands to if":
    let form = cljList(@[cljSymbol("when-not"), cljSymbol("x"), cljInt(1)])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("if")
    check expanded.items.len == 4
    check expanded.items[1].isSym("x")
    check expanded.items[2].kind == ckNil
    check expanded.items[3].isListWithHead("do")

suite "Macros - cond (not expanded by macroexpand)":
  setup:
    initBuiltinMacros()

  test "cond is left untouched by macroexpand":
    let form = cljList(@[cljSymbol("cond"), cljSymbol("a"), cljInt(1)])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("cond")

  test "cond empty directly":
    let condFn = macroTable["cond"]
    let result = condFn(@[])
    check result.kind == ckNil

  test "cond single clause directly":
    let condFn = macroTable["cond"]
    let result = condFn(@[cljSymbol("a"), cljInt(1)])
    check result.isListWithHead("if")
    check result.items.len == 3
    check result.items[1].isSym("a")
    check result.items[2].intVal == 1

  test "cond two clauses directly":
    let condFn = macroTable["cond"]
    let result = condFn(@[cljSymbol("a"), cljInt(1), cljSymbol("b"), cljInt(2)])
    check result.isListWithHead("if")
    check result.items.len == 4
    check result.items[1].isSym("a")
    check result.items[2].intVal == 1
    check result.items[3].isListWithHead("cond")

  test "cond with :else directly":
    let condFn = macroTable["cond"]
    let result = condFn(@[cljKeyword("else"), cljInt(42)])
    check result.kind == ckInt
    check result.intVal == 42

  test "cond odd args raises":
    expect CatchableError:
      discard macroTable["cond"](@[cljSymbol("a")])

suite "Macros - as->":
  setup:
    initBuiltinMacros()

  test "as-> basic":
    let form = cljList(@[cljSymbol("as->"), cljInt(5), cljSymbol("x"),
      cljList(@[cljSymbol("inc"), cljSymbol("x")])])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("let")
    check expanded.items.len == 3
    check expanded.items[1].kind == ckVector
    check expanded.items[1].items.len == 2
    check expanded.items[1].items[0].isSym("x")
    check expanded.items[1].items[1].intVal == 5
    check expanded.items[2].isListWithHead("inc")

suite "Macros - doto":
  setup:
    initBuiltinMacros()

  test "doto creates let":
    let form = cljList(@[cljSymbol("doto"), cljString("hello"),
      cljList(@[cljSymbol("toUpper")])])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("let")
    check expanded.items.len == 4  # let, [gs "hello"], (toUpper gs), gs
    check expanded.items[1].kind == ckVector
    check expanded.items[1].items.len == 2
    check expanded.items[1].items[1].kind == ckString

suite "Macros - some->":
  setup:
    initBuiltinMacros()

  test "some-> wraps in nil? check":
    let form = cljList(@[cljSymbol("some->"), cljInt(5),
      cljList(@[cljSymbol("inc")])])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("let")
    check expanded.items.len == 3
    check expanded.items[2].isListWithHead("if")
    check expanded.items[2].items[1].isListWithHead("nil?")

suite "Macros - some->>":
  setup:
    initBuiltinMacros()

  test "some->> appends to list":
    let form = cljList(@[cljSymbol("some->>"), cljInt(5),
      cljList(@[cljSymbol("conj"), cljInt(1)])])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("let")

suite "Macros - when-let":
  setup:
    initBuiltinMacros()

  test "when-let expands via macroexpand":
    let form = cljList(@[cljSymbol("when-let"),
      cljVector(@[cljSymbol("x"), cljInt(5)]),
      cljInt(42)])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("let")

  test "when-let macro directly":
    let whenLetFn = macroTable["when-let"]
    let result = whenLetFn(@[
      cljVector(@[cljSymbol("x"), cljInt(5)]),
      cljInt(42)])
    check result.isListWithHead("let")
    check result.items.len == 3

suite "Macros - macroexpand1":
  setup:
    initBuiltinMacros()

  test "macroexpand1 returns form for non-macro":
    let form = cljList(@[cljSymbol("+"), cljInt(1), cljInt(2)])
    let expanded = macroexpand1(form)
    check expanded.isListWithHead("+")

  test "macroexpand1 expands -> macro":
    let form = cljList(@[cljSymbol("->"), cljInt(5), cljSymbol("inc")])
    let expanded = macroexpand1(form)
    check expanded.isListWithHead("inc")

  test "macroexpand1 leaves special forms alone":
    let form = cljList(@[cljSymbol("def"), cljSymbol("x"), cljInt(1)])
    let expanded = macroexpand1(form)
    check expanded.isListWithHead("def")

  test "macroexpand1 leaves and alone":
    let form = cljList(@[cljSymbol("and"), cljSymbol("a"), cljSymbol("b")])
    let expanded = macroexpand1(form)
    check expanded.isListWithHead("and")

suite "Macros - macroexpand":
  setup:
    initBuiltinMacros()

  test "macroexpand fully expands chained ->":
    let form = cljList(@[cljSymbol("->"), cljInt(5),
      cljSymbol("inc"),
      cljList(@[cljSymbol("*"), cljInt(2)])])
    let expanded = macroexpand(form)
    check expanded.isListWithHead("*")
    check expanded.items[1].isListWithHead("inc")

suite "Macros - syntax-quote":
  setup:
    initBuiltinMacros()

  test "syntax-quote on symbol returns quoted symbol":
    let form = cljList(@[cljSymbol("syntax-quote"), cljSymbol("x")])
    let expanded = macroexpand1(form)
    check expanded.isListWithHead("quote")
    check expanded.items[1].isSym("x")

  test "syntax-quote on list returns concat":
    let form = cljList(@[cljSymbol("syntax-quote"),
      cljList(@[cljSymbol("inc"), cljSymbol("x")])])
    let expanded = macroexpand1(form)
    check expanded.isListWithHead("concat")

suite "Macros - fn*":
  setup:
    initBuiltinMacros()

  test "fn* wraps to fn":
    let form = cljList(@[cljSymbol("fn*"), cljVector(@[cljSymbol("x")]), cljSymbol("x")])
    let expanded = macroexpand1(form)
    check expanded.isListWithHead("fn")
    check expanded.items.len == 3
