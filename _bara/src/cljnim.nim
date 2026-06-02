# Bara Lang — AI-First Compiler
import os, osproc, strutils, times, tables
import reader, emitter, types, repl, macros, deps, ai_assist, tui, project

var libPathOverride* = ""

proc getLibPath(): string =
  # CLI --lib-path takes highest precedence
  if libPathOverride.len > 0 and dirExists(libPathOverride):
    return libPathOverride
  # Check environment variable
  let envPath = getEnv("CLJNIM_LIB_PATH", "")
  if envPath.len > 0 and dirExists(envPath):
    return envPath
  # Check current directory's lib first (project-local libs)
  let candidate0 = getCurrentDir() / "lib"
  if dirExists(candidate0): return candidate0
  let appDir = getAppDir()
  let candidate1 = appDir / "lib"
  let candidate2 = appDir.parentDir / "lib"
  if dirExists(candidate1): return candidate1
  if dirExists(candidate2): return candidate2
  return "lib"

proc resolveNsToPath(nsName: string, searchPaths: seq[string]): string =
  # Convert namespace name to file path: my.app -> my/app.clj
  # Clojure convention: hyphens in ns names become underscores in filenames
  let relPath = nsName.replace("-", "_").replace(".", "/")
  for sp in searchPaths:
    let candidateClj = sp / (relPath & ".clj")
    if fileExists(candidateClj):
      return candidateClj
    let candidateCljc = sp / (relPath & ".cljc")
    if fileExists(candidateCljc):
      return candidateCljc
  return ""

proc extractRequires(forms: seq[CljVal]): seq[(string, string)] =
  # Extract require declarations: returns (namespace, alias) pairs
  var res: seq[(string, string)] = @[]
  proc walk(form: CljVal) =
    if form.kind == ckList and form.items.len >= 2 and
       form.items[0].kind == ckSymbol:
      let head = form.items[0].symName
      if head == "ns":
        for ri in 2..<form.items.len:
          let clause = form.items[ri]
          let isRequire = (clause.kind == ckList and clause.items.len > 0 and
            ((clause.items[0].kind == ckSymbol and clause.items[0].symName == ":require") or
             (clause.items[0].kind == ckKeyword and clause.items[0].kwName == "require")))
          if isRequire:
            for ci in 1..<clause.items.len:
              let req = clause.items[ci]
              if req.kind == ckVector and req.items.len >= 1 and req.items[0].kind == ckSymbol:
                let libName = req.items[0].symName
                var alias = libName
                if req.items.len >= 3 and req.items[1].kind == ckKeyword and req.items[1].kwName == "as":
                  if req.items[2].kind == ckSymbol:
                    alias = req.items[2].symName
                res.add((libName, alias))
      elif head == "do":
        for item in form.items[1..^1]:
          walk(item)
  for form in forms:
    walk(form)
  return res

proc compileFileInternal(inputPath: string, outputPath: string, extraPaths: seq[string] = @[], libMode: bool = false, entryProcName: string = "", libs: Table[string, string] = initTable[string, string]()) =
  let source = readFile(inputPath)
  let forms = reader.readAll(source)

  if forms.len == 0:
    stderr.writeLine("Error: No forms found in " & inputPath)
    quit(1)

  # Resolve requires and collect all forms from required files
  let inputDir = inputPath.parentDir
  var searchPaths: seq[string] = @[inputDir, getCurrentDir()]
  # Add common test suite locations when running from temp dirs
  let testSuiteBase = inputDir / "clojure-test-suite" / "test"
  if dirExists(testSuiteBase) and testSuiteBase notin searchPaths:
    searchPaths.add(testSuiteBase)
  for p in extraPaths:
    if p notin searchPaths:
      searchPaths.add(p)
  let requires = extractRequires(forms)
  
  var allForms: seq[CljVal] = @[]
  var visited: seq[string] = @[]
  var nsAliases: seq[(string, string)] = @[]  # (alias, namespace)
  var libImports: seq[string] = @[]
  
  proc resolveFile(nsName: string) =
    if nsName in visited: return
    visited.add(nsName)
    if libs.hasKey(nsName):
      # Use pre-compiled lib module instead of inlining
      let nimModule = libs[nsName]
      if nimModule notin libImports:
        libImports.add(nimModule)
      return
    let path = resolveNsToPath(nsName, searchPaths)
    if path.len == 0:
      stderr.writeLine("Warning: Cannot find file for namespace: " & nsName)
      return
    let src = readFile(path)
    let fileForms = reader.readAll(src)
    # Recursively resolve nested requires
    let nestedRequires = extractRequires(fileForms)
    for (nestedNs, _) in nestedRequires:
      resolveFile(nestedNs)
    # Add non-ns forms (only definitions, not tests/expressions)
    for f in fileForms:
      if not (f.kind == ckList and f.items.len >= 1 and
              f.items[0].kind == ckSymbol and f.items[0].symName == "ns"):
        if f.kind == ckList and f.items.len >= 2 and f.items[0].kind == ckSymbol and
           f.items[0].symName in ["def", "defn", "defn-"]:
          allForms.add(f)
  
  # Collect namespace aliases
  for (nsName, alias) in requires:
    nsAliases.add((alias, nsName))
    resolveFile(nsName)
  
  # Set namespace aliases in emitter
  emitter.setNsAliases(nsAliases)
  
  # Set lib prefixes for qualified name resolution
  var libPrefixes: seq[string] = @[]
  for (alias, nsName) in nsAliases:
    if libs.hasKey(nsName):
      libPrefixes.add(alias)
  emitter.setLibNsPrefixes(libPrefixes)
  
  # Add current file's forms (skip ns declaration)
  for f in forms:
    if not (f.kind == ckList and f.items.len >= 1 and
            f.items[0].kind == ckSymbol and f.items[0].symName == "ns"):
      allForms.add(f)
  
  let oldEntryProc = emitter.emitEntryProcName
  if entryProcName.len > 0:
    emitter.emitEntryProcName = entryProcName
  var nimCode = if libMode: emitter.emitProgramLib(allForms) else: emitter.emitProgram(allForms)
  emitter.emitEntryProcName = oldEntryProc

  # Insert lib imports into generated Nim code
  if libImports.len > 0:
    var lines = nimCode.splitLines()
    var insertIdx = 0
    for i, line in lines:
      if line.startsWith("import "):
        insertIdx = i + 1
    for imp in libImports:
      lines.insert("from " & imp & " import nil", insertIdx)
      insertIdx.inc
    nimCode = lines.join("\n")

  writeFile(outputPath, nimCode)
  echo "Generated: ", outputPath

proc compileFile*(inputPath: string, outputPath: string, extraPaths: seq[string] = @[]) =
  compileFileInternal(inputPath, outputPath, extraPaths, false)

proc compileFileLib*(inputPath: string, outputPath: string, extraPaths: seq[string] = @[]) =
  compileFileInternal(inputPath, outputPath, extraPaths, true)

proc nimCompile(nimPath: string, binPath: string, release: bool = false): tuple[exitCode: int, output: string] =
  let libPath = getLibPath()
  let compilerLib = getAppDir() / "lib"
  var cmd = "nim c"
  if release:
    cmd.add(" -d:release")
  # Always include compiler runtime lib so cljnim_runtime is found
  if dirExists(compilerLib) and compilerLib != libPath:
    cmd.add(" --path:" & quoteShell(compilerLib))
  cmd.add(" --path:" & quoteShell(libPath))
  cmd.add(" -o:" & quoteShell(binPath) & " " & quoteShell(nimPath))
  echo "Compiling: ", cmd
  let (output, exitCode) = execCmdEx(cmd)
  return (exitCode, output)

proc makeTempDir(): string =
  let pid = getCurrentProcessId()
  let ts = epochTime().int
  result = getTempDir() / "cljnim_build_" & $pid & "_" & $ts
  createDir(result)

proc sanitizeNimIdent(name: string): string =
  ## Sanitize a project/bin name to valid Nim module name
  result = ""
  for c in name:
    case c
    of '-': result.add('_')
    of 'a'..'z', 'A'..'Z', '0'..'9', '_': result.add(c)
    else: result.add('_')
  if result.len == 0:
    result = "bin"

proc buildLibs(proj: Project, includeExamples: bool, nimDir: string): Table[string, string] =
  ## Discover and compile all project-local libraries required by bin files.
  ## Returns mapping: namespace -> nim module name
  result = initTable[string, string]()
  var entries = proj.bins
  if includeExamples:
    entries.add(proj.examples)

  var visited: seq[string] = @[]
  var queue: seq[string] = @[]
  let searchPaths = @[proj.rootDir, proj.rootDir / "lib"]

  # Collect all required namespaces from bin files
  for entry in entries:
    let inputPath = proj.rootDir / entry.path
    if not fileExists(inputPath): continue
    let forms = reader.readAll(readFile(inputPath))
    let requires = extractRequires(forms)
    for (nsName, _) in requires:
      if nsName notin queue:
        queue.add(nsName)

  # Iteratively process queue, adding transitive dependencies
  var i = 0
  while i < queue.len:
    let nsName = queue[i]
    i.inc
    if nsName in visited: continue
    visited.add(nsName)

    let path = resolveNsToPath(nsName, searchPaths)
    if path.len == 0 or not path.startsWith(proj.rootDir):
      continue  # External dependency, skip

    let forms = reader.readAll(readFile(path))
    let requires = extractRequires(forms)
    for (depNs, _) in requires:
      if depNs notin queue:
        queue.add(depNs)

  # Compile libs in dependency order (simple topological sort)
  var remaining = visited
  while remaining.len > 0:
    var madeProgress = false
    var nextRemaining: seq[string] = @[]

    for nsName in remaining:
      let path = resolveNsToPath(nsName, searchPaths)
      if path.len == 0 or not path.startsWith(proj.rootDir):
        continue

      let forms = reader.readAll(readFile(path))
      let requires = extractRequires(forms)

      var allDepsReady = true
      var depLibs = initTable[string, string]()
      for (depNs, _) in requires:
        if depNs == nsName: continue
        if result.hasKey(depNs):
          depLibs[depNs] = result[depNs]
        else:
          let depPath = resolveNsToPath(depNs, searchPaths)
          if depPath.len > 0 and depPath.startsWith(proj.rootDir):
            allDepsReady = false
            break

      if allDepsReady:
        madeProgress = true
        let nimName = "lib_" & sanitizeNimIdent(nsName.replace(".", "_").replace("-", "_"))
        let nimPath = nimDir / nimName & ".nim"
        if not fileExists(nimPath):
          echo "Building lib: ", nsName, " → ", nimPath
          compileFileInternal(path, nimPath, @[], true, "", depLibs)
        result[nsName] = nimName
      else:
        nextRemaining.add(nsName)

    if not madeProgress and nextRemaining.len > 0:
      # Circular dependency or bug, force compile first remaining
      let nsName = nextRemaining[0]
      nextRemaining.delete(0)
      let path = resolveNsToPath(nsName, searchPaths)
      if path.len > 0 and path.startsWith(proj.rootDir):
        let nimName = "lib_" & sanitizeNimIdent(nsName.replace(".", "_").replace("-", "_"))
        let nimPath = nimDir / nimName & ".nim"
        if not fileExists(nimPath):
          echo "Building lib (forced): ", nsName, " → ", nimPath
          compileFileInternal(path, nimPath, @[], true, "", initTable[string, string]())
        result[nsName] = nimName

    remaining = nextRemaining

proc buildBin(proj: Project, bin: project.BinEntry, outputDir: string, nimDir: string, nimcacheDir: string, release: bool, libs: Table[string, string]) =
  let inputPath = proj.rootDir / bin.path
  let nimName = "bin_" & sanitizeNimIdent(bin.name)
  let nimPath = nimDir / nimName & ".nim"
  let binPath = outputDir / bin.name

  if not fileExists(inputPath):
    stderr.writeLine("Warning: Bin file not found: " & inputPath)
    return

  echo "Building bin: ", bin.name, " → ", binPath

  # Set entry proc name so mono can call it later
  let oldEntryProc = emitter.emitEntryProcName
  emitter.emitEntryProcName = "clj_main_" & sanitizeNimIdent(bin.name)
  defer: emitter.emitEntryProcName = oldEntryProc

  compileFileInternal(inputPath, nimPath, @[], false, "", libs)

  let libPath = getLibPath()
  let compilerLib = getAppDir() / "lib"
  var cmd = "nim c"
  if release:
    cmd.add(" -d:release")
  if dirExists(compilerLib) and compilerLib != libPath:
    cmd.add(" --path:" & quoteShell(compilerLib))
  cmd.add(" --path:" & quoteShell(libPath))
  cmd.add(" --path:" & quoteShell(nimDir))
  cmd.add(" --nimcache:" & quoteShell(nimcacheDir))
  cmd.add(" -o:" & quoteShell(binPath) & " " & quoteShell(nimPath))
  echo "  ", cmd
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    stderr.writeLine("Compilation failed for ", bin.name)
    stderr.writeLine(output)
    quit(1)
  echo "  ✓ ", binPath

proc buildProject(proj: Project, release: bool, includeExamples: bool) =
  let targetDir = proj.rootDir / "target"
  let nimDir = targetDir / "nim"
  let binDir = targetDir / "bin"
  let nimcacheDir = targetDir / "nimcache"
  createDir(nimDir)
  createDir(binDir)
  createDir(nimcacheDir)

  echo "Building project: ", proj.name, " v", proj.version
  echo "  Root: ", proj.rootDir
  echo "  Bins: ", proj.bins.len

  let libs = buildLibs(proj, includeExamples, nimDir)
  if libs.len > 0:
    echo "  Libs: ", libs.len

  for bin in proj.bins:
    buildBin(proj, bin, binDir, nimDir, nimcacheDir, release, libs)

  if includeExamples:
    echo "  Examples: ", proj.examples.len
    for ex in proj.examples:
      buildBin(proj, ex, binDir, nimDir, nimcacheDir, release, libs)

proc buildMono(proj: Project, release: bool, includeExamples: bool) =
  let targetDir = proj.rootDir / "target"
  let nimDir = targetDir / "nim"
  let binDir = targetDir / "bin"
  let nimcacheDir = targetDir / "nimcache"
  createDir(nimDir)
  createDir(binDir)
  createDir(nimcacheDir)

  var entries: seq[project.BinEntry] = proj.bins
  if includeExamples:
    entries.add(proj.examples)

  echo "Building mono binary: ", proj.name
  echo "  Entries: ", entries.len

  let libs = buildLibs(proj, includeExamples, nimDir)
  if libs.len > 0:
    echo "  Libs: ", libs.len

  # First compile each entry to a Nim module with exported entry proc
  var imports: seq[string] = @[]
  var cases: seq[string] = @[]

  for entry in entries:
    let inputPath = proj.rootDir / entry.path
    let nimName = "bin_" & sanitizeNimIdent(entry.name)
    let nimPath = nimDir / nimName & ".nim"

    if not fileExists(inputPath):
      stderr.writeLine("Warning: Entry file not found: " & inputPath)
      continue

    echo "  Generating module: ", nimName

    let oldEntryProc = emitter.emitEntryProcName
    emitter.emitEntryProcName = "clj_main_" & sanitizeNimIdent(entry.name)
    defer: emitter.emitEntryProcName = oldEntryProc

    compileFileInternal(inputPath, nimPath, @[], false, "", libs)
    imports.add(nimName)
    cases.add("  of \"" & entry.name & "\": discard " & "clj_main_" & sanitizeNimIdent(entry.name) & "()")

  if imports.len == 0:
    stderr.writeLine("Error: No valid entries to build")
    quit(1)

  # Generate mono wrapper
  let monoName = sanitizeNimIdent(proj.name)
  let monoNimPath = nimDir / "mono.nim"
  var monoCode = "# Generated by Bara Lang — Mono Binary Wrapper\n"
  monoCode.add("import os\n")
  monoCode.add("import cljnim_runtime\n")
  for imp in imports:
    monoCode.add("import " & imp & "\n")
  monoCode.add("\nproc main() =\n")
  monoCode.add("  if paramCount() < 1:\n")
  monoCode.add("    echo \"Usage: " & proj.name & " <command>\"\n")
  monoCode.add("    echo \"Commands:\"\n")
  for entry in entries:
    if fileExists(proj.rootDir / entry.path):
      monoCode.add("    echo \"  " & entry.name & "\"\n")
  monoCode.add("    quit(1)\n")
  monoCode.add("  let cmd = paramStr(1)\n")
  monoCode.add("  case cmd\n")
  for c in cases:
    monoCode.add(c & "\n")
  monoCode.add("  else:\n")
  monoCode.add("    echo \"Unknown command: \" & cmd\n")
  monoCode.add("    quit(1)\n")
  monoCode.add("\nwhen isMainModule:\n")
  monoCode.add("  main()\n")

  writeFile(monoNimPath, monoCode)
  echo "  Generated: ", monoNimPath

  # Compile mono wrapper
  let monoBinPath = binDir / monoName
  let libPath = getLibPath()
  let compilerLib = getAppDir() / "lib"
  var cmd = "nim c"
  if release:
    cmd.add(" -d:release")
  if dirExists(compilerLib) and compilerLib != libPath:
    cmd.add(" --path:" & quoteShell(compilerLib))
  cmd.add(" --path:" & quoteShell(libPath))
  cmd.add(" --path:" & quoteShell(nimDir))
  cmd.add(" --nimcache:" & quoteShell(nimcacheDir))
  cmd.add(" -o:" & quoteShell(monoBinPath) & " " & quoteShell(monoNimPath))
  echo "  Compiling mono: ", cmd
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    stderr.writeLine("Compilation failed for mono binary")
    stderr.writeLine(output)
    quit(1)
  echo "  ✓ ", monoBinPath

proc runFile*(inputPath: string) =
  let baseName = inputPath.splitFile.name
  let buildDir = makeTempDir()
  let nimPath = buildDir / baseName & ".nim"
  let binPath = buildDir / baseName

  # Resolve project dependencies
  let inputDir = inputPath.parentDir
  let depPaths = deps.loadAndResolve(if inputDir.len > 0: inputDir else: getCurrentDir())

  # Check nimcache for cached output
  let projectDir = inputPath.parentDir
  let cacheDir = projectDir / "nimcache"
  let cacheSubDir = cacheDir / baseName
  let cacheNimPath = cacheSubDir / baseName & ".nim"
  let cacheBinPath = cacheSubDir / baseName

  var useCache = false
  if fileExists(cacheNimPath) and fileExists(cacheBinPath):
    let srcTime = getLastModificationTime(inputPath).toUnix
    let cacheTime = getLastModificationTime(cacheNimPath).toUnix
    if srcTime <= cacheTime:
      useCache = true

  if useCache:
    echo "Using cached: ", cacheNimPath
    let (compileResult, compileOut) = nimCompile(cacheNimPath, cacheBinPath)
    if compileResult != 0:
      stderr.writeLine("Compilation failed (cached)")
      stderr.writeLine(compileOut)
      if ai_assist.hasAiConfig():
        let source = readFile(inputPath)
        let aiRes = ai_assist.explainError(compileOut, source, inputPath)
        stderr.writeLine(ai_assist.formatSuggestion(aiRes))
      quit(1)
    # try: removeDir(buildDir) except: discard
    let runResult = execCmd(cacheBinPath)
    quit(runResult)

  compileFile(inputPath, nimPath, depPaths)

  let (compileResult, compileOut) = nimCompile(nimPath, binPath)
  if compileResult != 0:
    stderr.writeLine("Compilation failed")
    stderr.writeLine(compileOut)
    if ai_assist.hasAiConfig():
      let source = readFile(inputPath)
      let aiRes = ai_assist.explainError(compileOut, source, inputPath)
      stderr.writeLine(ai_assist.formatSuggestion(aiRes))
    # try: removeDir(buildDir) except: discard
    quit(1)

  # Save to cache
  try:
    createDir(cacheSubDir)
    copyFile(nimPath, cacheNimPath)
    copyFile(binPath, cacheBinPath)
    echo "Cached: ", cacheNimPath
  except:
    discard

  let runResult = execCmd(binPath)
  # try: removeDir(buildDir) except: discard
  if runResult != 0:
    stderr.writeLine("Execution failed")
    quit(1)

proc main() =
  initBuiltinMacros()
  var args = commandLineParams()

  # Strip leading global flags
  if args.len >= 2 and args[0] == "--lib-path":
    libPathOverride = args[1]
    args = args[2..^1]

  if args.len == 0:
    echo "Bara Lang — AI-First Compiler"
    echo ""
    echo "Usage:"
    echo "  cljnim [--lib-path <dir>] compile <file.clj> [output.nim]"
    echo "  cljnim [--lib-path <dir>] run <file.clj>"
    echo "  cljnim [--lib-path <dir>] read <file.clj>"
    echo "  cljnim build [--mono] [--release] [--examples]"
    echo "  cljnim repl [--json]"
    echo "  cljnim deps"
    echo "  cljnim -e '<code>'"
    echo "  cljnim ai '<description>'"
    echo "  cljnim tui"
    echo ""
    echo "Global Options:"
    echo "  --lib-path <dir>    Additional Nim library search path"
    echo "                      (also via CLJNIM_LIB_PATH env var)"
    echo ""
    echo "REPL Commands:"
    echo "  :quit, :q       Exit REPL"
    echo "  :defs           List defined vars"
    echo "  :clear          Clear definitions"
    echo "  :ns             Show current namespace"
    echo ""
    echo "AI Mode (JSON):"
    echo "  cljnim repl --json"
    echo "  Input:  {\"op\":\"eval\",\"form\":\"(+ 1 2)\"}"
    echo "  Output: {\"status\":\"ok\",\"result\":{...},\"meta\":{...}}"
    quit(0)

  let cmd = args[0]
  
  # Handle -e flag
  if cmd == "-e":
    if args.len < 2:
      stderr.writeLine("Error: Missing expression after -e")
      quit(1)
    let code = args[1]
    let buildDir = makeTempDir()
    let nimPath = buildDir / "expr.nim"
    let binPath = buildDir / "expr"
    let forms = reader.readAll(code)
    emitter.emitEntryProcName = ""
    let nimCode = emitter.emitProgram(forms)
    writeFile(nimPath, nimCode)
    let (compileResult, compileOut) = nimCompile(nimPath, binPath)
    if compileResult != 0:
      stderr.writeLine("Compilation failed")
      stderr.writeLine(compileOut)
      if ai_assist.hasAiConfig():
        let aiRes = ai_assist.explainError(compileOut, code, "-e expression")
        stderr.writeLine(ai_assist.formatSuggestion(aiRes))
      # try: removeDir(buildDir) except: discard
      quit(1)
    let runResult = execCmd(binPath)
    # try: removeDir(buildDir) except: discard
    quit(runResult)

  case cmd
  of "compile":
    if args.len < 2:
      stderr.writeLine("Error: Missing input file")
      quit(1)
    let inputPath = args[1]
    let outputPath = if args.len >= 3: args[2] else: inputPath.changeFileExt("nim")
    compileFile(inputPath, outputPath)

  of "build":
    var monoMode = false
    var releaseMode = false
    var includeExamples = false
    for i in 1..<args.len:
      if args[i] == "--mono":
        monoMode = true
      elif args[i] == "--release":
        releaseMode = true
      elif args[i] == "--examples":
        includeExamples = true
    let proj = project.loadProject()
    if monoMode:
      buildMono(proj, releaseMode, includeExamples)
    else:
      buildProject(proj, releaseMode, includeExamples)

  of "compile-lib":
    if args.len < 2:
      stderr.writeLine("Error: Missing input file")
      quit(1)
    let inputPath = args[1]
    let outputPath = if args.len >= 3: args[2] else: inputPath.changeFileExt("nim")
    compileFileLib(inputPath, outputPath)
  
  of "run":
    if args.len < 2:
      stderr.writeLine("Error: Missing input file")
      quit(1)
    runFile(args[1])
  
  of "read":
    if args.len < 2:
      stderr.writeLine("Error: Missing input file")
      quit(1)
    let source = readFile(args[1])
    let forms = reader.readAll(source)
    for form in forms:
      echo $form
  
  of "repl":
    var mode = rmHuman
    var tcpPort = -1
    for i in 1..<args.len:
      if args[i] == "--json":
        mode = rmJson
      elif args[i] == "--edn":
        mode = rmEdn
      elif args[i] == "--tcp":
        if i + 1 < args.len:
          try:
            tcpPort = parseInt(args[i+1])
          except ValueError:
            stderr.writeLine("Invalid TCP port: " & args[i+1])
            quit(1)
      elif args[i].startsWith("--tcp="):
        try:
          tcpPort = parseInt(args[i][6..^1])
        except ValueError:
          stderr.writeLine("Invalid TCP port: " & args[i][6..^1])
          quit(1)
    var state = initReplState(mode)
    try:
      if tcpPort > 0:
        runTcpRepl(state, tcpPort)
      else:
        case mode
        of rmHuman: runHumanRepl(state)
        of rmJson: runJsonRepl(state)
        of rmEdn: runJsonRepl(state)
    finally:
      state.cleanup()
  
  of "deps":
    let projectDir = getCurrentDir()
    let depsPath = deps.findDepsFile(projectDir)
    if depsPath.len == 0:
      echo "No deps.edn or project.clj found"
      quit(0)
    echo "Found: ", depsPath
    let depsFile = deps.parseDepsFile(depsPath)
    echo "Dependencies: ", depsFile.deps.len
    let paths = deps.resolveDeps(depsFile, depsPath.parentDir)
    if paths.len > 0:
      echo "Resolved paths:"
      for p in paths:
        echo "  ", p
    else:
      echo "No dependencies to resolve"

  of "ai":
    if not ai_assist.hasAiConfig():
      stderr.writeLine("Error: No AI API key configured.")
      stderr.writeLine("Set DEEPSEEK_API_KEY, OPENAI_API_KEY, or MIMO_API_KEY environment variable.")
      quit(1)
    if args.len < 2:
      stderr.writeLine("Error: Missing description for AI generation")
      stderr.writeLine("Usage: cljnim ai 'function that reverses a list'")
      quit(1)
    let description = args[1]
    echo "🤖 Asking AI to generate code..."
    let aiRes = ai_assist.generateCode(description)
    if aiRes.ok:
      echo aiRes.suggestion
    else:
      stderr.writeLine(aiRes.suggestion)
      quit(1)

  of "tui":
    runTui()

  else:
    stderr.writeLine("Unknown command: " & cmd)
    quit(1)

when isMainModule:
  main()
