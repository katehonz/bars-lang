; C FFI — Достъп до C функции директно от Bara Lang
; (c-fn sin "math.h" :double [:double])
; Това генерира Nim proc с {.importc.} pragma

(println "=== C FFI ===")
; Ползваме Nim interop към math вместо директен C FFI за демонстрация
(println (nim/math/sin 1.5708))  ; sin(pi/2) ≈ 1.0
(println (nim/math/cos 0.0))     ; cos(0) = 1.0
(println (nim/math/sqrt 144.0))  ; sqrt(144) = 12.0
