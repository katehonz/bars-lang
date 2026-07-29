;; map-indexed / take-nth / dedupe (Phase 17.50)

(defn main []
  ;; map-indexed: f sees [idx x]
  (let [m (map-indexed (fn [i x] (* i 10)) (vector 5 6 7))]
    (println (count m))
    (println (get m 0))
    (println (get m 2)))
  ;; take-nth: every n-th from index 0
  (let [t (take-nth 2 (vector 1 2 3 4 5))]
    (println (count t))
    (println (get t 1))
    (println (get t 2)))
  ;; take-nth 0 → empty (guard)
  (println (count (take-nth 0 (vector 1 2 3))))
  ;; dedupe: consecutive only
  (let [d (dedupe (vector 1 1 2 2 2 3 1 1))]
    (println (count d))
    (println (get d 0))
    (println (get d 3)))
  ;; non-consecutive duplicates are kept
  (println (count (dedupe (vector 1 2 1))))
  0)
