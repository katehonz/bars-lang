; Nim Interop — Достъп до Nim стандартната библиотека
(println "=== Nim Math Interop ===")

; math.sin, math.cos, math.sqrt
(println (nim/math/sin 0.0))
(println (nim/math/cos 0.0))
(println (nim/math/sqrt 4.0))
(println (nim/math/pow 2.0 10.0))

(println "=== Nim String Interop ===")

; strutils functions
(println (nim/strutils/endsWith? "hello world" "world"))
(println (nim/strutils/startsWith? "hello" "hel"))
(println (nim/strutils/toUpper "clojure"))
(println (nim/strutils/toLower "NIM"))
(println (nim/strutils/repeat "ha" 3))
