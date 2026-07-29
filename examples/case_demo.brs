;; case (Phase 17.28)

(defn label [n]
  (case n
    1 10
    2 20
    3 30
    0))

(defn main []
  (println (label 1))
  (println (label 2))
  (println (label 3))
  (println (label 9))
  ;; scrutinee once
  (let [v (vector 1 2)]
    (println (case (get v 1)
               1 100
               2 200
               300)))
  0)
