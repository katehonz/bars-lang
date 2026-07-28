;; let destructuring examples
;; Wildcard, vector, and nested patterns

(defn main []
  ;; Simple binding (unchanged)
  (let [x 42]
    (println x))

  ;; Wildcard: discard value
  (let [_ 99]
    (println "wildcard discard works"))

  ;; Vector destructuring
  (let [[a b c] (vector 10 20 30)]
    (do (println a)  ;; 10
        (println b)  ;; 20
        (println c)  ;; 30
        0))

  ;; Vector destructuring with wildcard
  (let [[x _ z] (vector 1 2 3)]
    (do (println x)  ;; 1
        (println z)  ;; 3
        0))

  ;; Nested vector destructuring
  (let [[a [b c] d] (vector 7 (vector 8 9) 10)]
    (do (println a)  ;; 7
        (println b)  ;; 8
        (println c)  ;; 9
        (println d)  ;; 10
        0))

  ;; Single element vector pattern
  (let [[x] (vector 42)]
    (println x))

  0)
