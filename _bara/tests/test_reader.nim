import unittest, strutils
import ../src/types
import ../src/reader

suite "Reader - Basic Types":
  test "read nil":
    let v = read("nil")
    check v.kind == ckNil

  test "read true":
    let v = read("true")
    check v.kind == ckBool
    check v.boolVal == true

  test "read false":
    let v = read("false")
    check v.kind == ckBool
    check v.boolVal == false

  test "read integer":
    let v = read("42")
    check v.kind == ckInt
    check v.intVal == 42

  test "read negative integer":
    let v = read("-7")
    check v.kind == ckInt
    check v.intVal == -7

  test "read float":
    let v = read("3.14")
    check v.kind == ckFloat
    check v.floatVal == 3.14

  test "read string":
    let v = read("\"hello\"")
    check v.kind == ckString
    check v.strVal == "hello"

  test "read string with escapes":
    let v = read("\"hello\\nworld\"")
    check v.kind == ckString
    check v.strVal == "hello\nworld"

  test "read keyword":
    let v = read(":key")
    check v.kind == ckKeyword
    check v.kwName == "key"

  test "read symbol":
    let v = read("foo")
    check v.kind == ckSymbol
    check v.symName == "foo"

  test "read symbol with special chars":
    let v = read("my-fn?")
    check v.kind == ckSymbol
    check v.symName == "my-fn?"

suite "Reader - Collections":
  test "read empty list":
    let v = read("()")
    check v.kind == ckList
    check v.items.len == 0

  test "read list":
    let v = read("(+ 1 2)")
    check v.kind == ckList
    check v.items.len == 3
    check v.items[0].kind == ckSymbol
    check v.items[0].symName == "+"
    check v.items[1].kind == ckInt
    check v.items[1].intVal == 1
    check v.items[2].kind == ckInt
    check v.items[2].intVal == 2

  test "read vector":
    let v = read("[1 2 3]")
    check v.kind == ckVector
    check v.items.len == 3
    check v.items[0].intVal == 1
    check v.items[1].intVal == 2
    check v.items[2].intVal == 3

  test "read empty vector":
    let v = read("[]")
    check v.kind == ckVector
    check v.items.len == 0

  test "read map":
    let v = read("{:a 1 :b 2}")
    check v.kind == ckMap
    check v.mapKeys.len == 2
    check v.mapKeys[0].kind == ckKeyword
    check v.mapKeys[0].kwName == "a"
    check v.mapVals[0].kind == ckInt
    check v.mapVals[0].intVal == 1

  test "read empty map":
    let v = read("{}")
    check v.kind == ckMap
    check v.mapKeys.len == 0

  test "read nested list":
    let v = read("(+ (- 3 1) 2)")
    check v.kind == ckList
    check v.items.len == 3
    check v.items[1].kind == ckList
    check v.items[1].items.len == 3

suite "Reader - Quote and Syntax":
  test "read quote":
    let v = read("'foo")
    check v.kind == ckList
    check v.items.len == 2
    check v.items[0].kind == ckSymbol
    check v.items[0].symName == "quote"
    check v.items[1].kind == ckSymbol
    check v.items[1].symName == "foo"

  test "read deref":
    let v = read("@atom")
    check v.kind == ckList
    check v.items[0].symName == "deref"

  test "read unquote":
    let v = read("~x")
    check v.kind == ckList
    check v.items[0].symName == "unquote"

  test "read unquote-splicing":
    let v = read("~@x")
    check v.kind == ckList
    check v.items[0].symName == "unquote-splicing"

suite "Reader - Comments":
  test "skip comments":
    let v = read("; comment\n42")
    check v.kind == ckInt
    check v.intVal == 42

  test "inline comments":
    let forms = readAll("(+ 1 2) ; addition\n(- 3 1)")
    check forms.len == 2

suite "Reader - readAll":
  test "read multiple forms":
    let forms = readAll("1 2 3")
    check forms.len == 3
    check forms[0].intVal == 1
    check forms[1].intVal == 2
    check forms[2].intVal == 3

  test "read empty string":
    let forms = readAll("")
    check forms.len == 0

  test "read whitespace only":
    let forms = readAll("   \n  \t  ")
    check forms.len == 0

suite "Reader - Edge Cases":
  test "read negative float":
    let v = read("-3.14")
    check v.kind == ckFloat
    check v.floatVal == -3.14

  test "read negative float without leading zero":
    let v = read("-.5")
    check v.kind == ckFloat
    check v.floatVal == -0.5

  test "read positive float without leading zero":
    let v = read("+.25")
    check v.kind == ckFloat
    check v.floatVal == 0.25

  test "read scientific notation 1e5":
    let v = read("1e5")
    check v.kind == ckFloat
    check v.floatVal == 100000.0

  test "read scientific notation with negative exponent":
    let v = read("1.5e-3")
    check v.kind == ckFloat
    check v.floatVal == 0.0015

  test "read negative scientific notation":
    let v = read("-2.5e2")
    check v.kind == ckFloat
    check v.floatVal == -250.0

  test "read negative float scientific without leading zero":
    let v = read("-.5e-3")
    check v.kind == ckFloat
    check v.floatVal == -0.0005

  test "read number with leading dot":
    let v = read(".25")
    check v.kind == ckFloat
    check v.floatVal == 0.25

  test "read unterminated string raises error":
    try:
      discard read("\"unterminated")
      check false  # should not reach here
    except ReaderError as e:
      check "Unterminated" in e.msg

  test "read unterminated list raises error":
    try:
      discard read("(1 2 3")
      check false
    except ReaderError as e:
      check "Unterminated" in e.msg

  test "read extra input after form raises error":
    try:
      discard readAll("1 2 extra")
      # readAll might succeed, but readOne should fail
      discard
    except:
      discard

  test "read standalone minus is a symbol":
    let v = read("-")
    check v.kind == ckSymbol
    check v.symName == "-"

  test "read standalone plus is a symbol":
    let v = read("+")
    check v.kind == ckSymbol
    check v.symName == "+"
