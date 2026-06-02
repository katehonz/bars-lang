import unittest, hashes
import ../lib/cljnim_pmap

proc intEq(a, b: int): bool = a == b
proc strEq(a, b: string): bool = a == b

suite "Persistent Map - Basic":
  test "empty map":
    var m = newPersistentMap[int, int]()
    check m.count == 0
    check pmapGet(m, 42, -1, hash(42), intEq) == -1

  test "single entry":
    var m = newPersistentMap[int, string]()
    m = pmapAssoc(m, 1, "one", hash(1), intEq)
    check m.count == 1
    check pmapGet(m, 1, "default", hash(1), intEq) == "one"
    check pmapGet(m, 2, "default", hash(2), intEq) == "default"

  test "few entries":
    var m = newPersistentMap[int, int]()
    for i in 0..<5:
      m = pmapAssoc(m, i, i * 10, hash(i), intEq)
    check m.count == 5
    check pmapGet(m, 0, -1, hash(0), intEq) == 0
    check pmapGet(m, 4, -1, hash(4), intEq) == 40
    check pmapContains(m, 3, hash(3), intEq) == true
    check pmapContains(m, 99, hash(99), intEq) == false

suite "Persistent Map - assoc":
  test "assoc overwrites existing":
    var m = newPersistentMap[int, string]()
    m = pmapAssoc(m, 1, "one", hash(1), intEq)
    m = pmapAssoc(m, 1, "uno", hash(1), intEq)
    check pmapGet(m, 1, "", hash(1), intEq) == "uno"
    check m.count == 1

  test "assoc preserves old map":
    var m1 = newPersistentMap[int, int]()
    m1 = pmapAssoc(m1, 1, 10, hash(1), intEq)
    var m2 = pmapAssoc(m1, 2, 20, hash(2), intEq)
    check m1.count == 1
    check m2.count == 2
    check pmapGet(m1, 2, -1, hash(2), intEq) == -1
    check pmapGet(m2, 1, -1, hash(1), intEq) == 10

  test "assoc many entries (100)":
    var m = newPersistentMap[int, int]()
    for i in 0..<100:
      m = pmapAssoc(m, i, i * i, hash(i), intEq)
    check m.count == 100
    check pmapGet(m, 0, -1, hash(0), intEq) == 0
    check pmapGet(m, 50, -1, hash(50), intEq) == 2500
    check pmapGet(m, 99, -1, hash(99), intEq) == 9801
    for i in 0..<100:
      check pmapGet(m, i, -1, hash(i), intEq) == i * i

  test "assoc many entries (500)":
    var m = newPersistentMap[int, int]()
    for i in 0..<500:
      m = pmapAssoc(m, i, i * 2, hash(i), intEq)
    check m.count == 500
    check pmapGet(m, 0, -1, hash(0), intEq) == 0
    check pmapGet(m, 250, -1, hash(250), intEq) == 500
    check pmapGet(m, 499, -1, hash(499), intEq) == 998

suite "Persistent Map - dissoc":
  test "dissoc existing key":
    var m = newPersistentMap[int, string]()
    m = pmapAssoc(m, 1, "one", hash(1), intEq)
    m = pmapAssoc(m, 2, "two", hash(2), intEq)
    m = pmapAssoc(m, 3, "three", hash(3), intEq)
    m = pmapDissoc(m, 2, hash(2), intEq)
    check m.count == 2
    check pmapContains(m, 1, hash(1), intEq) == true
    check pmapContains(m, 2, hash(2), intEq) == false
    check pmapContains(m, 3, hash(3), intEq) == true

  test "dissoc non-existing key":
    var m = newPersistentMap[int, int]()
    m = pmapAssoc(m, 1, 10, hash(1), intEq)
    m = pmapDissoc(m, 99, hash(99), intEq)
    check m.count == 1
    check pmapContains(m, 1, hash(1), intEq) == true

  test "dissoc until empty":
    var m = newPersistentMap[int, int]()
    m = pmapAssoc(m, 1, 10, hash(1), intEq)
    m = pmapDissoc(m, 1, hash(1), intEq)
    check m.count == 0
    check m.root.isNil

suite "Persistent Map - keys/values":
  test "keys":
    var m = newPersistentMap[int, string]()
    m = pmapAssoc(m, 1, "one", hash(1), intEq)
    m = pmapAssoc(m, 2, "two", hash(2), intEq)
    let k = pmapKeys(m)
    check k.len == 2
    check 1 in k
    check 2 in k

  test "vals":
    var m = newPersistentMap[int, string]()
    m = pmapAssoc(m, 1, "one", hash(1), intEq)
    m = pmapAssoc(m, 2, "two", hash(2), intEq)
    let v = pmapVals(m)
    check v.len == 2
    check "one" in v
    check "two" in v

  test "entries":
    var m = newPersistentMap[int, string]()
    m = pmapAssoc(m, 1, "one", hash(1), intEq)
    m = pmapAssoc(m, 2, "two", hash(2), intEq)
    let e = pmapEntries(m)
    check e.len == 2

suite "Persistent Map - items iterator":
  test "iterate empty":
    var m = newPersistentMap[int, int]()
    var count = 0
    for (k, v) in pmapItems(m):
      count += 1
    check count == 0

  test "iterate non-empty":
    var m = newPersistentMap[int, int]()
    for i in 0..<10:
      m = pmapAssoc(m, i, i * 10, hash(i), intEq)
    var count = 0
    var sum = 0
    for (k, v) in pmapItems(m):
      count += 1
      sum += v
    check count == 10
    check sum == 450

suite "Persistent Map - string keys":
  test "string keys":
    var m = newPersistentMap[string, int]()
    m = pmapAssoc(m, "hello", 1, hash("hello"), strEq)
    m = pmapAssoc(m, "world", 2, hash("world"), strEq)
    check pmapGet(m, "hello", -1, hash("hello"), strEq) == 1
    check pmapGet(m, "world", -1, hash("world"), strEq) == 2
    check pmapGet(m, "missing", -1, hash("missing"), strEq) == -1

suite "Persistent Map - build from pairs":
  test "pmapBuild":
    var pairs: seq[(int, string)] = @[(1, "one"), (2, "two"), (3, "three")]
    var m = pmapBuild(pairs, intEq)
    check m.count == 3
    check pmapGet(m, 2, "", hash(2), intEq) == "two"
