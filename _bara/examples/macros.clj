; Macro test
(println "=== Threading macros ===")

; ->
(println (-> 5 (+ 3) (* 2)))
; => (* (+ 5 3) 2) = 16

; ->>
(println (->> [1 2 3] (map (fn [x] (* x x))) (reduce + 0)))
; => 14

(println "=== defmacro ===")

(defmacro unless [condition & body]
  (list 'if condition nil (cons 'do body)))

(unless false
  (println "unless works!"))

(unless true
  (println "this should NOT print"))

(println "=== when macro ===")

(when true
  (println "when works!"))

(println "=== and/or ===")

(println (and true true))
(println (and true false))
(println (or false true))
(println (or false false))
