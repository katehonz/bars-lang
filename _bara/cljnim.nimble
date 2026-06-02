# Package
version       = "0.1.0"
author        = "Bara Lang Team"
description   = "Clojure dialect compiling to Nim"
license       = "MIT"
srcDir        = "src"
bin           = @["cljnim"]

# Dependencies
requires "nim >= 2.0.0"
requires "illwill >= 0.4.0"
