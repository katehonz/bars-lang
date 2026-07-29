;; comp — function composition (Phase 17.33)
;; (comp f g h) applies h first, then g, then f.

(defn double [n] (* n 2))
(defn square [n] (* n n))
(defn add1 [n] (+ n 1))

(defn main []
  ;; add1 then square then double: 2*((5+1)^2) = 72
  (let [f (comp double square add1)]
    (println (f 5)))
  ;; (comp f) is f
  (let [g (comp double)]
    (println (g 21)))
  ;; (comp) is identity
  (let [h (comp)]
    (println (h 9)))
  0)
