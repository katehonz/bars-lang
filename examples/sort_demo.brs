;; sort (Phase 17.42) — insertion sort on a clone, ascending

(defn main []
  (let [s (sort (vector 4 1 3 1 5 2))]
    (println (count s))
    (println (get s 0))
    (println (get s 1))
    (println (get s 2))
    (println (get s 5)))
  ;; input vector is not mutated (sort works on a clone)
  (let [orig (vector 3 1 2)
        sorted (sort orig)]
    (println (get orig 0))
    (println (get sorted 0)))
  ;; already sorted / single element / negatives
  (println (get (sort (vector 1 2 3)) 2))
  (println (count (sort (vector 9))))
  (println (get (sort (vector 2 -5 0)) 0))
  ;; pipeline with other seq ops
  (let [p (sort (distinct (vector 3 1 3 2 1)))]
    (println (count p))
    (println (get p 0))
    (println (get p 2)))
  0)
