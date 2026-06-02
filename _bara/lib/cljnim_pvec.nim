# Persistent Vector — Hash Array Mapped Trie
# Bara Lang-style 32-way branching with structural sharing

type
  PVecNode*[T] = ref object
    isLeaf*: bool
    # Using seq instead of array for flexibility during building
    children*: seq[PVecNode[T]]  # internal nodes
    values*: seq[T]              # leaf nodes (max 32)

  PersistentVector*[T] = object
    root*: PVecNode[T]
    tail*: seq[T]
    count*: int
    shift*: int  # tree depth * 5 bits

const
  BRANCHING_BITS = 5
  BRANCHING_FACTOR = 1 shl BRANCHING_BITS  # 32
  BRANCHING_MASK = BRANCHING_FACTOR - 1    # 0x1F

# ---- Node helpers ----

proc newLeafNode[T](vals: seq[T] = @[]): PVecNode[T] =
  PVecNode[T](isLeaf: true, values: vals)

proc newInternalNode[T](children: seq[PVecNode[T]] = @[]): PVecNode[T] =
  PVecNode[T](isLeaf: false, children: children)

proc copyNode[T](n: PVecNode[T]): PVecNode[T] =
  if n.isNil: return nil
  if n.isLeaf:
    newLeafNode[T](n.values)
  else:
    newInternalNode[T](n.children)

# ---- Debug ----

proc `$`*[T](v: PersistentVector[T]): string =
  result = "PersistentVector(count=" & $v.count & ", shift=" & $v.shift & ", tail=["
  for i in 0..<v.tail.len:
    if i > 0: result.add(", ")
    result.add($v.tail[i])
  result.add("])")

# ---- nth: Get element at index ----

proc pvecNth*[T](v: PersistentVector[T], index: int): T =
  if index < 0 or index >= v.count:
    raise newException(IndexDefect, "Index out of bounds: " & $index & " (count: " & $v.count & ")")
  
  # Check tail first
  let tailOffset = v.count - v.tail.len
  if index >= tailOffset:
    return v.tail[index - tailOffset]
  
  # Walk the trie
  var node = v.root
  var level = v.shift
  while level > 0:
    let childIdx = (index shr level) and BRANCHING_MASK
    if childIdx >= node.children.len:
      raise newException(IndexDefect, "Corrupt vector: child index " & $childIdx & " at level " & $level)
    node = node.children[childIdx]
    if node.isNil:
      raise newException(IndexDefect, "Corrupt vector: nil node at level " & $level)
    level -= BRANCHING_BITS
  
  let leafIdx = index and BRANCHING_MASK
  if leafIdx >= node.values.len:
    raise newException(IndexDefect, "Corrupt vector: leaf index " & $leafIdx)
  return node.values[leafIdx]

# ---- conj: Append element ----

proc pushLeaf[T](node: PVecNode[T], index: int, shift: int, val: seq[T]): PVecNode[T] =
  # Push a full leaf (seq of up to 32 values) into the tree at position 'index'
  result = copyNode(node)
  if shift == 0:
    result = newLeafNode[T](val)
  else:
    let childIdx = (index shr shift) and BRANCHING_MASK
    # Grow children array and fill any gaps with empty internal nodes
    while result.children.len <= childIdx:
      result.children.add(newInternalNode[T]())

    var child = result.children[childIdx]
    if child.isNil:
      if shift == BRANCHING_BITS:
        child = newLeafNode[T](val)
      else:
        child = pushLeaf(newInternalNode[T](), index, shift - BRANCHING_BITS, val)
    else:
      child = pushLeaf(child, index, shift - BRANCHING_BITS, val)

    result.children[childIdx] = child

proc pvecConj*[T](v: PersistentVector[T], val: T): PersistentVector[T] =
  result = v
  result.count += 1
  
  # Case 1: Room in tail
  if v.tail.len < BRANCHING_FACTOR:
    result.tail.add(val)
    return
  
  # Case 2: Tail is full — promote it into tree
  let tailOffset = v.count - v.tail.len
  let oldTail = v.tail
  result.tail = @[val]  # New tail with just the new element
  
  if v.root.isNil:
    # First tail promotion — root becomes the old tail
    result.root = newLeafNode[T](oldTail)
    result.shift = 0
    return
  
  # Check if tree needs to grow deeper
  # A tree at shift S can hold up to 32^(S/5 + 1) leaves
  # If tailOffset >> shift has bits beyond shift, we need a new root
  let needsNewRoot = (tailOffset shr v.shift) > 0
  
  if needsNewRoot:
    # Create new root pointing to old root
    let newRoot = newInternalNode[T](@[v.root])
    result.root = pushLeaf(newRoot, tailOffset, v.shift + BRANCHING_BITS, oldTail)
    result.shift += BRANCHING_BITS
  else:
    result.root = pushLeaf(v.root, tailOffset, v.shift, oldTail)

# ---- assoc: Set element at index ----

proc doAssoc[T](node: PVecNode[T], index: int, shift: int, val: T): PVecNode[T] =
  result = copyNode(node)
  if shift == 0:
    # Leaf level
    let leafIdx = index and BRANCHING_MASK
    if leafIdx >= result.values.len:
      raise newException(IndexDefect, "assoc leaf index out of bounds: " & $leafIdx)
    result.values[leafIdx] = val
  else:
    let childIdx = (index shr shift) and BRANCHING_MASK
    if childIdx >= result.children.len or result.children[childIdx].isNil:
      raise newException(IndexDefect, "assoc: nil child at index " & $childIdx)
    result.children[childIdx] = doAssoc(result.children[childIdx], index, shift - BRANCHING_BITS, val)

proc pvecAssoc*[T](v: PersistentVector[T], index: int, val: T): PersistentVector[T] =
  if index < 0 or index >= v.count:
    raise newException(IndexDefect, "Index out of bounds: " & $index)
  
  result = v
  let tailOffset = v.count - v.tail.len
  
  if index >= tailOffset:
    # In tail — copy-on-write
    result.tail[index - tailOffset] = val
    return
  
  # In tree — path copy
  result.root = doAssoc(v.root, index, v.shift, val)

# ---- pop: Remove last element ----

proc pvecPop*[T](v: PersistentVector[T]): PersistentVector[T] =
  if v.count == 0:
    raise newException(IndexDefect, "Can't pop empty vector")
  
  result = v
  result.count -= 1
  
  if v.tail.len > 1:
    result.tail.setLen(v.tail.len - 1)
    return
  
  if v.tail.len == 1:
    # Tail had exactly 1 element. Pull previous leaf from tree into tail.
    if v.count == 1:
      # Now empty
      result = PersistentVector[T]()
      return
    
    let tailOffset = v.count - v.tail.len - BRANCHING_FACTOR
    if tailOffset < 0:
      # Only tail existed
      result.tail = @[]
      return
    
    # Walk to the leaf that becomes the new tail
    var node = v.root
    var level = v.shift
    while level > 0:
      let childIdx = (tailOffset shr level) and BRANCHING_MASK
      if childIdx < node.children.len:
        node = node.children[childIdx]
      else:
        node = nil
        break
      level -= BRANCHING_BITS
    
    if not node.isNil and node.isLeaf:
      result.tail = node.values
    else:
      result.tail = @[]
    
    # If tree is now empty, clear it
    if result.count <= BRANCHING_FACTOR:
      result.root = nil
      result.shift = 0
    return
  
  # tail was empty (shouldn't happen with correct invariants)
  result.tail = @[]

# ---- Builders ----

proc newPersistentVector*[T](items: seq[T] = @[]): PersistentVector[T] =
  for item in items:
    result = pvecConj(result, item)

proc toSeq*[T](v: PersistentVector[T]): seq[T] =
  result = newSeq[T](v.count)
  for i in 0..<v.count:
    result[i] = pvecNth(v, i)

iterator items*[T](v: PersistentVector[T]): T =
  for i in 0..<v.count:
    yield pvecNth(v, i)

# Compatibility helpers (seq-like interface)
proc len*[T](v: PersistentVector[T]): int = v.count
proc `[]`*[T](v: PersistentVector[T], idx: int): T = pvecNth(v, idx)
proc `[]`*[T](v: PersistentVector[T], idx: BackwardsIndex): T = pvecNth(v, v.count - int(idx))
