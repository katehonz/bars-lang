# Bara Lang Project Manifest Reader
# Reads bara.edn (Clojure/EDN format) for project configuration
import os
import types, reader

type
  BinEntry* = object
    name*: string
    path*: string

  LibEntry* = object
    name*: string
    path*: string

  Project* = object
    name*: string
    version*: string
    rootDir*: string
    lib*: LibEntry
    bins*: seq[BinEntry]
    examples*: seq[BinEntry]

proc findProjectRoot*(startDir: string = getCurrentDir()): string =
  ## Walk up from startDir looking for bara.edn
  var dir = absolutePath(startDir)
  while true:
    let baraEdn = dir / "bara.edn"
    if fileExists(baraEdn):
      return dir
    let parent = parentDir(dir)
    if parent == dir:
      break
    dir = parent
  return ""

proc extractMapString(form: CljVal, key: string, defaultVal: string = ""): string =
  if form.kind != ckMap: return defaultVal
  for i in 0..<form.mapKeys.len:
    let k = form.mapKeys[i]
    if (k.kind == ckKeyword and k.kwName == key) or (k.kind == ckSymbol and k.symName == key):
      let v = form.mapVals[i]
      if v.kind == ckString: return v.strVal
  return defaultVal

proc extractMapVector(form: CljVal, key: string): seq[CljVal] =
  if form.kind != ckMap: return @[]
  for i in 0..<form.mapKeys.len:
    let k = form.mapKeys[i]
    if (k.kind == ckKeyword and k.kwName == key) or (k.kind == ckSymbol and k.symName == key):
      let v = form.mapVals[i]
      if v.kind == ckVector: return v.items
      if v.kind == ckList: return v.items
  return @[]

proc parseBinEntry(form: CljVal): BinEntry =
  result.name = extractMapString(form, "name")
  result.path = extractMapString(form, "path")

proc parseLibEntry(form: CljVal): LibEntry =
  result.name = extractMapString(form, "name")
  result.path = extractMapString(form, "path")

proc loadProject*(dir: string = getCurrentDir()): Project =
  let root = findProjectRoot(dir)
  if root.len == 0:
    raise newException(ValueError, "bara.edn not found in " & dir & " or parent directories")

  let path = root / "bara.edn"
  let source = readFile(path)
  let forms = reader.readAll(source)
  if forms.len == 0:
    raise newException(ValueError, "Empty bara.edn")

  let map = forms[0]
  if map.kind != ckMap:
    raise newException(ValueError, "bara.edn must contain a map at top level")

  result.rootDir = root
  result.name = extractMapString(map, "name", "unknown")
  result.version = extractMapString(map, "version", "0.1.0")

  let libVal = extractMapVector(map, "lib")
  if libVal.len > 0:
    result.lib = parseLibEntry(libVal[0])
  elif true:
    # Also check for single :lib map (not vector)
    for i in 0..<map.mapKeys.len:
      let k = map.mapKeys[i]
      if (k.kind == ckKeyword and k.kwName == "lib") or (k.kind == ckSymbol and k.symName == "lib"):
        let v = map.mapVals[i]
        if v.kind == ckMap:
          result.lib = parseLibEntry(v)
          break

  for item in extractMapVector(map, "bins"):
    result.bins.add(parseBinEntry(item))

  for item in extractMapVector(map, "examples"):
    result.examples.add(parseBinEntry(item))
