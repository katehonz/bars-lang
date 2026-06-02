# Persistent Map — Hash Array Mapped Trie (HAMT)
# Bara Lang-style 32-way branching with structural sharing
# Takes pre-computed hashes and equality functions from callers

import hashes

const
  PMAP_SHIFT* = 5
  PMAP_BRANCH* = 32
  PMAP_MASK* = 31
  PMAP_MAX_SHIFT* = 25  # 6 levels (25,20,15,10,5,0) = 30 bits of hash

type
  PMapNode*[K, V] = ref object
    children*: seq[PMapNode[K, V]]
    keys*: seq[K]
    vals*: seq[V]
    hashes*: seq[Hash]  # stored hashes for leaf nodes, parallel to keys

  PersistentMap*[K, V] = object
    root*: PMapNode[K, V]
    count*: int

proc newPMapLeaf*[K, V](keys: seq[K] = @[], vals: seq[V] = @[], hashes: seq[Hash] = @[]): PMapNode[K, V] =
  PMapNode[K, V](keys: keys, vals: vals, hashes: hashes)

proc newPMapInternal*[K, V](): PMapNode[K, V] =
  PMapNode[K, V](children: @[])

proc pmapCopyNode*[K, V](n: PMapNode[K, V]): PMapNode[K, V] =
  if n.isNil: return nil
  if n.children.len > 0:
    result = newPMapInternal[K, V]()
    result.children = n.children
  else:
    result = newPMapLeaf[K, V](n.keys, n.vals, n.hashes)

proc newPersistentMap*[K, V](): PersistentMap[K, V] =
  PersistentMap[K, V](root: nil, count: 0)

proc pmapGet*[K, V](m: PersistentMap[K, V], key: K, default: V, kh: Hash, eq: proc(a, b: K): bool): V =
  if m.root.isNil: return default
  var node: PMapNode[K, V] = m.root
  var shift = PMAP_MAX_SHIFT
  var h = kh

  while shift >= 0:
    if node.children.len > 0:
      let idx = (h shr shift) and PMAP_MASK
      if idx >= node.children.len or node.children[idx].isNil:
        return default
      node = node.children[idx]
      shift -= PMAP_SHIFT
      continue

    for i in 0..<node.keys.len:
      if eq(node.keys[i], key):
        return node.vals[i]
    return default

  return default

proc pmapContains*[K, V](m: PersistentMap[K, V], key: K, kh: Hash, eq: proc(a, b: K): bool): bool =
  if m.root.isNil: return false
  var node: PMapNode[K, V] = m.root
  var shift = PMAP_MAX_SHIFT
  var h = kh

  while shift >= 0:
    if node.children.len > 0:
      let idx = (h shr shift) and PMAP_MASK
      if idx >= node.children.len or node.children[idx].isNil:
        return false
      node = node.children[idx]
      shift -= PMAP_SHIFT
      continue

    for i in 0..<node.keys.len:
      if eq(node.keys[i], key):
        return true
    return false

  return false

proc pmapAssoc*[K, V](m: PersistentMap[K, V], key: K, val: V, kh: Hash, eq: proc(a, b: K): bool): PersistentMap[K, V] =
  let h = kh
  var added = false

  proc doAssoc(node: PMapNode[K, V], shift: int): PMapNode[K, V] =
    let idx = (h shr shift) and PMAP_MASK

    if node.isNil:
      added = true
      return newPMapLeaf[K, V](@[key], @[val], @[kh])

    if node.children.len > 0:
      result = pmapCopyNode(node)
      if idx >= result.children.len:
        let oldLen = result.children.len
        result.children.setLen(idx + 1)
        for i in oldLen..<idx:
          result.children[i] = nil
      let childNode = if idx < node.children.len: node.children[idx] else: nil
      result.children[idx] = doAssoc(childNode, shift - PMAP_SHIFT)
      return

    # Leaf node
    if shift == 0:
      result = newPMapLeaf[K, V](node.keys, node.vals, node.hashes)
      for i in 0..<result.keys.len:
        if eq(result.keys[i], key):
          result.vals[i] = val
          return
      result.keys.add(key)
      result.vals.add(val)
      result.hashes.add(kh)
      added = true
      return

    # Leaf at non-zero shift — promote to internal
    let existingKeys = node.keys
    let existingHashes = node.hashes
    result = newPMapInternal[K, V]()

    # Place all existing entries into the new internal node
    for ki in 0..<existingKeys.len:
      let ek = existingKeys[ki]
      let ev = node.vals[ki]
      let eh = existingHashes[ki]
      let eidx = (eh shr shift) and PMAP_MASK

      if eidx >= result.children.len:
        let oldLen = result.children.len
        result.children.setLen(eidx + 1)
        for i in oldLen..<eidx:
          result.children[i] = nil

      if result.children[eidx].isNil:
        result.children[eidx] = newPMapLeaf[K, V](@[ek], @[ev], @[eh])
      else:
        result.children[eidx].keys.add(ek)
        result.children[eidx].vals.add(ev)
        result.children[eidx].hashes.add(eh)

    # Now insert the new key
    let ns = max(idx + 1, result.children.len)
    if ns > result.children.len:
      let oldLen = result.children.len
      result.children.setLen(ns)
      for i in oldLen..<ns:
        result.children[i] = nil

    if result.children[idx].isNil:
      result.children[idx] = newPMapLeaf[K, V](@[key], @[val], @[kh])
      added = true
    else:
      result.children[idx] = doAssoc(result.children[idx], shift - PMAP_SHIFT)

  if m.root.isNil:
    result.root = newPMapLeaf[K, V](@[key], @[val], @[kh])
    result.count = 1
  else:
    result.root = doAssoc(m.root, PMAP_MAX_SHIFT)
    result.count = m.count
    if added:
      result.count += 1

proc pmapDissoc*[K, V](m: PersistentMap[K, V], key: K, kh: Hash, eq: proc(a, b: K): bool): PersistentMap[K, V] =
  if m.root.isNil or m.count == 0: return m
  var removed = false
  let h = kh

  proc doDissoc(node: PMapNode[K, V], shift: int): PMapNode[K, V] =
    let idx = (h shr shift) and PMAP_MASK

    if node.isNil:
      return nil

    if node.children.len > 0:
      result = pmapCopyNode(node)
      if idx < result.children.len and not result.children[idx].isNil:
        result.children[idx] = doDissoc(result.children[idx], shift - PMAP_SHIFT)
      return

    # Leaf node
    result = newPMapLeaf[K, V]()
    for i in 0..<node.keys.len:
      if eq(node.keys[i], key):
        removed = true
      else:
        result.keys.add(node.keys[i])
        result.vals.add(node.vals[i])
        result.hashes.add(node.hashes[i])
    if result.keys.len == 0:
      return nil

  result = m
  result.root = doDissoc(m.root, PMAP_MAX_SHIFT)
  if removed:
    result.count -= 1
  if result.count == 0:
    result.root = nil

proc pmapKeys*[K, V](m: PersistentMap[K, V]): seq[K] =
  result = @[]
  if m.root.isNil: return
  var stack: seq[PMapNode[K, V]] = @[m.root]
  while stack.len > 0:
    let node = stack.pop()
    if node.isNil: continue
    if node.children.len > 0:
      for i in countdown(node.children.len - 1, 0):
        if not node.children[i].isNil:
          stack.add(node.children[i])
    else:
      result.add(node.keys)

proc pmapVals*[K, V](m: PersistentMap[K, V]): seq[V] =
  result = @[]
  if m.root.isNil: return
  var stack: seq[PMapNode[K, V]] = @[m.root]
  while stack.len > 0:
    let node = stack.pop()
    if node.isNil: continue
    if node.children.len > 0:
      for i in countdown(node.children.len - 1, 0):
        if not node.children[i].isNil:
          stack.add(node.children[i])
    else:
      result.add(node.vals)

proc pmapEntries*[K, V](m: PersistentMap[K, V]): seq[(K, V)] =
  result = @[]
  if m.root.isNil: return
  var stack: seq[PMapNode[K, V]] = @[m.root]
  while stack.len > 0:
    let node = stack.pop()
    if node.isNil: continue
    if node.children.len > 0:
      for i in countdown(node.children.len - 1, 0):
        if not node.children[i].isNil:
          stack.add(node.children[i])
    else:
      for i in 0..<node.keys.len:
        result.add((node.keys[i], node.vals[i]))

proc pmapBuild*[K, V](pairs: seq[(K, V)], eq: proc(a, b: K): bool): PersistentMap[K, V] =
  for (k, v) in pairs:
    result = pmapAssoc(result, k, v, hash(k), eq)

iterator pmapItems*[K, V](m: PersistentMap[K, V]): (K, V) =
  if not m.root.isNil:
    var stack: seq[PMapNode[K, V]] = @[m.root]
    while stack.len > 0:
      let node = stack.pop()
      if node.isNil: continue
      if node.children.len > 0:
        for i in countdown(node.children.len - 1, 0):
          if not node.children[i].isNil:
            stack.add(node.children[i])
      else:
        for i in 0..<node.keys.len:
          yield (node.keys[i], node.vals[i])

proc `$`*[K, V](m: PersistentMap[K, V]): string =
  var parts: seq[string] = @[]
  for (k, v) in pmapItems(m):
    parts.add($k & " " & $v)
  "{" & parts.join(", ") & "}"
