import unittest
import ../lib/cljnim_pvec

suite "Persistent Vector - Basic":
  test "empty vector":
    var v = newPersistentVector[int]()
    check v.count == 0
    check toSeq(v) == newSeq[int]()

  test "single element":
    var v = newPersistentVector[int](@[42])
    check v.count == 1
    check pvecNth(v, 0) == 42

  test "few elements":
    var v = newPersistentVector[int](@[1, 2, 3, 4, 5])
    check v.count == 5
    for i in 0..<5:
      check pvecNth(v, i) == i + 1

  test "nth out of bounds":
    var v = newPersistentVector[int](@[1, 2, 3])
    expect IndexDefect:
      discard pvecNth(v, 10)
    expect IndexDefect:
      discard pvecNth(v, -1)

suite "Persistent Vector - conj":
  test "conj one by one":
    var v = newPersistentVector[int]()
    for i in 0..<100:
      v = pvecConj(v, i)
      check v.count == i + 1
      check pvecNth(v, i) == i
    # Verify all elements
    for i in 0..<100:
      check pvecNth(v, i) == i

  test "conj across tail boundary (32)":
    var v = newPersistentVector[int]()
    for i in 0..<40:
      v = pvecConj(v, i * 10)
    check v.count == 40
    check pvecNth(v, 0) == 0
    check pvecNth(v, 31) == 310
    check pvecNth(v, 32) == 320
    check pvecNth(v, 39) == 390

  test "conj across second level (1024)":
    var v = newPersistentVector[int]()
    for i in 0..<1100:
      v = pvecConj(v, i)
    check v.count == 1100
    check pvecNth(v, 0) == 0
    check pvecNth(v, 1023) == 1023
    check pvecNth(v, 1024) == 1024
    check pvecNth(v, 1099) == 1099

  test "conj large (10000)":
    var v = newPersistentVector[int]()
    for i in 0..<10000:
      v = pvecConj(v, i)
    check v.count == 10000
    check pvecNth(v, 0) == 0
    check pvecNth(v, 9999) == 9999
    check pvecNth(v, 5000) == 5000

suite "Persistent Vector - assoc":
  test "assoc in tail":
    var v = newPersistentVector[int](@[1, 2, 3, 4, 5])
    v = pvecAssoc(v, 2, 99)
    check pvecNth(v, 2) == 99
    check pvecNth(v, 0) == 1
    check pvecNth(v, 4) == 5

  test "assoc in tree":
    var v = newPersistentVector[int]()
    for i in 0..<100:
      v = pvecConj(v, i)
    v = pvecAssoc(v, 50, 9999)
    check pvecNth(v, 50) == 9999
    check pvecNth(v, 49) == 49
    check pvecNth(v, 51) == 51

  test "assoc preserves old vector":
    var v1 = newPersistentVector[int](@[1, 2, 3])
    var v2 = pvecAssoc(v1, 1, 99)
    check pvecNth(v1, 1) == 2  # Original unchanged
    check pvecNth(v2, 1) == 99

suite "Persistent Vector - pop":
  test "pop from tail":
    var v = newPersistentVector[int](@[1, 2, 3, 4, 5])
    v = pvecPop(v)
    check v.count == 4
    check pvecNth(v, 3) == 4

  test "pop across tail boundary":
    var v = newPersistentVector[int]()
    for i in 0..<40:
      v = pvecConj(v, i)
    v = pvecPop(v)
    check v.count == 39
    check pvecNth(v, 38) == 38

  test "pop to empty":
    var v = newPersistentVector[int](@[42])
    v = pvecPop(v)
    check v.count == 0
