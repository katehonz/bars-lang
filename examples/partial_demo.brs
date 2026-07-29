;; Multi-arg apply + partial (Phase 17.23)
;; partial freezes leading args; result is a 1-arg fn.

(defn add3 [a b c] (+ (+ a b) c))
(defn mul-add [a b c] (+ (* a b) c))

(defn main []
  ;; (apply f fixed… rest-vec) — last arg is always the vector to spread
  (println (apply add3 10 [20 12]))
  (println (apply add3 1 2 [3]))
  ;; partial → one more argument
  (let [p (partial add3 10 20)]
    (println (p 12)))
  (let [q (partial mul-add 3 4)]
    (println (q 5)))
  ;; still works with plain apply on a vector
  (let [f add3]
    (println (apply f [7 8 9])))
  0)
