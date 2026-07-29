;; interpose / partition / frequencies (Phase 17.41)

(defn main []
  (let [s (interpose 0 (vector 1 2 3))]
    (println (count s))
    (println (get s 0))
    (println (get s 1))
    (println (get s 4)))
  ;; single element → no separator
  (println (count (interpose 9 (vector 7))))
  (let [p (partition 2 (vector 1 2 3 4 5))]
    (println (count p))
    (println (get (get p 0) 1))
    (println (get (get p 1) 0)))
  ;; partition size 3 + size 0 guard
  (println (count (partition 3 (vector 1 2 3 4 5 6 7))))
  (println (count (partition 0 (vector 1 2 3))))
  (let [f (frequencies (vector 1 2 1 3 1 2))]
    (println (map-count f))
    (println (map-get f 1))
    (println (map-get f 2))
    (println (map-get f 3)))
  0)
