;; doseq + for over vectors (Phase 17.24)

(defn main []
  ;; doseq — side effects only
  (doseq [x [1 2 3]]
    (println x))
  ;; for — collect results into a vector
  (let [xs (for [n [1 2 3 4]]
             (* n 10))]
    (println (get xs 0))
    (println (get xs 3))
    (println (count xs)))
  ;; nested-style: for then doseq print
  (let [ys (for [k [5 6]]
             (+ k 1))]
    (doseq [y ys]
      (println y)))
  0)
