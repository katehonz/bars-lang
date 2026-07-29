;; mapcat / keep / flatten (Phase 17.44)

(defn wrap [x] (vector x (* x 10)))

(defn main []
  ;; mapcat: f returns a vector per element, all concatenated
  (let [m (mapcat wrap (vector 1 2 3))]
    (println (count m))
    (println (get m 0))
    (println (get m 1))
    (println (get m 5)))
  ;; mapcat with inline lambda
  (println (count (mapcat (fn [x] (vector x x)) (vector 7 8))))
  ;; keep: drop the 0 results
  (let [k (keep (fn [x] (if (> x 2) (* x 100) 0)) (vector 1 2 3 4))]
    (println (count k))
    (println (get k 0))
    (println (get k 1)))
  ;; flatten: deep, order preserved
  (let [f (flatten (vector 1 (vector 2 (vector 3 4)) 5))]
    (println (count f))
    (println (get f 0))
    (println (get f 2))
    (println (get f 4)))
  ;; flatten of an already-flat vector is a copy
  (println (count (flatten (vector 9 8))))
  0)
