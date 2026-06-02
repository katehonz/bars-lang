import unittest, os, strutils
import ../src/deps

let testDir = getCurrentDir() / "tests" / "tmp_deps"

proc setup() =
  createDir(testDir)

proc teardown() =
  removeDir(testDir)

suite "Deps - Parsing":
  setup()
  teardown()

  test "parse deps.edn with git deps":
    let edn = """{:deps {org.clojure/core.async {:git/url "https://github.com/clojure/core.async.git" :sha "abc123"}}}"""
    let tmpFile = testDir / "deps.edn"
    createDir(testDir)
    writeFile(tmpFile, edn)
    let depsFile = parseDepsFile(tmpFile)
    check depsFile.deps.len == 1
    check depsFile.deps[0].name == "org.clojure/core.async"
    check depsFile.deps[0].kind == dkGit
    check depsFile.deps[0].gitUrl == "https://github.com/clojure/core.async.git"
    check depsFile.deps[0].sha == "abc123"
    removeFile(tmpFile)
    removeDir(testDir)

  test "parse deps.edn with local deps":
    let edn = """{:deps {mylib/local {:local/root "../mylib"}}}"""
    let tmpFile = testDir / "deps.edn"
    createDir(testDir)
    writeFile(tmpFile, edn)
    let depsFile = parseDepsFile(tmpFile)
    check depsFile.deps.len == 1
    check depsFile.deps[0].name == "mylib/local"
    check depsFile.deps[0].kind == dkLocal
    check depsFile.deps[0].localRoot == "../mylib"
    removeFile(tmpFile)
    removeDir(testDir)

  test "parse deps.edn with multiple deps":
    let edn = """{:deps {org.clojure/core.async {:git/url "https://github.com/clojure/core.async.git" :sha "abc123"}
        mylib/local {:local/root "./lib"}}}"""
    let tmpFile = testDir / "deps.edn"
    createDir(testDir)
    writeFile(tmpFile, edn)
    let depsFile = parseDepsFile(tmpFile)
    check depsFile.deps.len == 2
    removeFile(tmpFile)
    removeDir(testDir)

  test "parse deps.edn with :rev instead of :sha":
    let edn = """{:deps {some/lib {:git/url "https://example.com/lib.git" :rev "def456"}}}"""
    let tmpFile = testDir / "deps.edn"
    createDir(testDir)
    writeFile(tmpFile, edn)
    let depsFile = parseDepsFile(tmpFile)
    check depsFile.deps.len == 1
    check depsFile.deps[0].sha == "def456"
    removeFile(tmpFile)
    removeDir(testDir)

  test "parse empty deps map":
    let edn = """{:deps {}}"""
    let tmpFile = testDir / "deps.edn"
    createDir(testDir)
    writeFile(tmpFile, edn)
    let depsFile = parseDepsFile(tmpFile)
    check depsFile.deps.len == 0
    removeFile(tmpFile)
    removeDir(testDir)

suite "Deps - Path Resolution":
  test "depLocalPath for git dep":
    let dep = Dependency(name: "org.clojure/core.async", kind: dkGit, gitUrl: "https://example.com", sha: "abc")
    let path = depLocalPath("/project", dep)
    check path == "/project/.deps/org_clojure_core_async"

  test "depLocalPath for local dep relative":
    let dep = Dependency(name: "mylib", kind: dkLocal, localRoot: "../mylib")
    let path = depLocalPath("/project", dep)
    check path == "/mylib"

  test "depLocalPath for local dep absolute":
    let dep = Dependency(name: "mylib", kind: dkLocal, localRoot: "/abs/path/mylib")
    let path = depLocalPath("/project", dep)
    check path == "/abs/path/mylib"

  test "depsDir returns correct path":
    check depsDir("/project") == "/project/.deps"

suite "Deps - findDepsFile":
  test "findDepsFile returns empty when no deps file":
    let tmpSubdir = testDir / "subdir"
    createDir(tmpSubdir)
    let result = findDepsFile(tmpSubdir)
    check result.len == 0
    removeDir(testDir)

  test "findDepsFile finds deps.edn":
    createDir(testDir)
    writeFile(testDir / "deps.edn", "{:deps {}}")
    let tmpSubdir = testDir / "subdir"
    createDir(tmpSubdir)
    let result = findDepsFile(tmpSubdir)
    check result.len > 0
    check result.endsWith("deps.edn")
    removeDir(testDir)
