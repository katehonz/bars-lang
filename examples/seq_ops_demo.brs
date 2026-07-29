;; reverse / concat / distinct (Phase 17.40)

(defn main []
  (let [r (reverse (vector 1 2 3 4))]
    (println (count r))
    (println (get r 0))
    (println (get r 3)))
  (let [c (concat (vector 1 2) (vector 3 4 5))]
    (println (count c))
    (println (get c 0))
    (println (get c 4)))
  ;; variadic concat (left fold)
  (let [c4 (concat (vector 1) (vector 2) (vector 3) (vector 4))]
    (println (count c4))
    (println (get c4 3)))
  (let [d (distinct (vector 1 2 2 3 1 4 3))]
    (println (count d))
    (println (get d 0))
    (println (get d 3)))
  ;; pipeline: distinct + reverse + concat
  (let [p (reverse (distinct (concat (vector 1 2 1) (vector 3 2 4))))]
    (println (count p))
    (println (get p 0))
    (println (get p 3)))
  0)
