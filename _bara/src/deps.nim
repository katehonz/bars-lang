# Dependency Resolution — reads deps.edn, downloads Git deps
import os, osproc, strutils
import types, reader

type
  DepKind* = enum
    dkGit, dkLocal

  Dependency* = object
    name*: string          # e.g. "org.clojure/core.async"
    case kind*: DepKind
    of dkGit:
      gitUrl*: string      # :git/url
      sha*: string         # :sha or :rev
    of dkLocal:
      localRoot*: string   # :local/root

  DepsFile* = object
    deps*: seq[Dependency]
    paths*: seq[string]

  DepsError* = object of CatchableError

proc findDepsFile*(startDir: string = getCurrentDir()): string =
  ## Walk up from startDir looking for deps.edn or project.clj
  var dir = startDir
  while true:
    let depsEdn = dir / "deps.edn"
    if fileExists(depsEdn): return depsEdn
    let projectClj = dir / "project.clj"
    if fileExists(projectClj): return projectClj
    let parent = dir.parentDir
    if parent == dir: break
    dir = parent
  return ""

proc extractMapPairs(form: CljVal): seq[(string, CljVal)] =
  ## Extract keyword->value pairs from a map CljVal
  if form.kind != ckMap:
    return @[]
  for i in 0..<form.mapKeys.len:
    let key = form.mapKeys[i]
    let val = form.mapVals[i]
    if key.kind == ckKeyword:
      result.add((key.kwName, val))
    elif key.kind == ckSymbol:
      result.add((key.symName, val))

proc parseDepsMap(depsMap: CljVal): seq[Dependency] =
  ## Parse {:deps {lib-name {:git/url "..." :sha "..."} ...}} map
  result = @[]
  if depsMap.kind != ckMap:
    raise newException(DepsError, "deps value must be a map")

  for i in 0..<depsMap.mapKeys.len:
    let depKey = depsMap.mapKeys[i]
    let depVal = depsMap.mapVals[i]

    var depName = ""
    if depKey.kind == ckSymbol:
      depName = depKey.symName
    elif depKey.kind == ckKeyword:
      depName = depKey.kwName
    else:
      continue

    if depVal.kind != ckMap:
      raise newException(DepsError, "Dependency spec for " & depName & " must be a map")

    let pairs = extractMapPairs(depVal)

    var gitUrl = ""
    var sha = ""
    var localRoot = ""

    for (pk, pv) in pairs:
      case pk
      of "git/url":
        if pv.kind == ckString: gitUrl = pv.strVal
      of "sha", "rev":
        if pv.kind == ckString: sha = pv.strVal
      of "local/root":
        if pv.kind == ckString: localRoot = pv.strVal

    if gitUrl.len > 0 and sha.len > 0:
      result.add(Dependency(name: depName, kind: dkGit, gitUrl: gitUrl, sha: sha))
    elif localRoot.len > 0:
      result.add(Dependency(name: depName, kind: dkLocal, localRoot: localRoot))
    else:
      raise newException(DepsError, "Dependency " & depName & " needs :git/url+:sha or :local/root")

proc parseDepsFile*(filePath: string): DepsFile =
  ## Parse a deps.edn file and return structured deps
  let source = readFile(filePath)
  let forms = reader.readAll(source)
  if forms.len == 0:
    raise newException(DepsError, "Empty deps.edn")

  let topMap = forms[0]
  if topMap.kind != ckMap:
    raise newException(DepsError, "deps.edn must contain a map at top level")

  let pairs = extractMapPairs(topMap)
  for (pk, pv) in pairs:
    if pk == "deps":
      result.deps = parseDepsMap(pv)
    elif pk == "paths":
      if pv.kind == ckVector:
        for p in pv.items:
          if p.kind == ckString:
            result.paths.add(p.strVal)

proc depsDir*(projectDir: string): string =
  ## Return the .deps directory path for a project
  return projectDir / ".deps"

proc depLocalPath*(projectDir: string, dep: Dependency): string =
  ## Return the local filesystem path for a dependency
  case dep.kind
  of dkLocal:
    let root = dep.localRoot
    if root.isAbsolute:
      return root
    return projectDir / root
  of dkGit:
    # Sanitize name for directory: org.clojure/core.async -> org_clojure_core_async
    let dirName = dep.name.replace("/", "_").replace(".", "_")
    return depsDir(projectDir) / dirName

proc gitClone*(url, targetDir: string): bool =
  ## Clone a git repo to targetDir. Returns true on success.
  createDir(targetDir.parentDir)
  if dirExists(targetDir):
    return true  # already cloned
  let cmd = "git clone --quiet " & quoteShell(url) & " " & quoteShell(targetDir)
  let exitCode = execCmd(cmd)
  return exitCode == 0

proc gitCheckout*(repoDir, sha: string): bool =
  ## Checkout a specific commit in a repo
  let cmd = "git -C " & quoteShell(repoDir) & " checkout --quiet " & sha
  let exitCode = execCmd(cmd)
  return exitCode == 0

proc resolveDeps*(depsFile: DepsFile, projectDir: string): seq[string] =
  ## Download/resolve all dependencies and return search paths
  result = @[]
  # Add :paths from deps.edn
  for p in depsFile.paths:
    let absPath = if p.isAbsolute: p else: projectDir / p
    if dirExists(absPath):
      result.add(absPath)
  for dep in depsFile.deps:
    case dep.kind
    of dkLocal:
      let path = depLocalPath(projectDir, dep)
      if dirExists(path):
        result.add(path)
      else:
        stderr.writeLine("Warning: Local dependency not found: " & path)
    of dkGit:
      let path = depLocalPath(projectDir, dep)
      if not dirExists(path):
        echo "Cloning ", dep.name, " from ", dep.gitUrl, "..."
        if not gitClone(dep.gitUrl, path):
          stderr.writeLine("Warning: Failed to clone " & dep.name)
          continue
      if not gitCheckout(path, dep.sha):
        stderr.writeLine("Warning: Failed to checkout " & dep.sha & " for " & dep.name)
      else:
        echo "Checked out ", dep.name, " @ ", dep.sha
      if dirExists(path):
        result.add(path)

proc loadAndResolve*(projectDir: string): seq[string] =
  ## Find deps.edn, parse it, resolve deps, return search paths
  let depsPath = findDepsFile(projectDir)
  if depsPath.len == 0:
    return @[]
  let depsFile = parseDepsFile(depsPath)
  return resolveDeps(depsFile, projectDir.parentDir)
