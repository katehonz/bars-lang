;; get-in / update / sort-by (Phase 17.45)

(defn main []
  ;; get-in: mixed map + vector walk
  (let [m (zipmap (vector 1 2) (vector (vector 10 20) (vector 30 40)))]
    (println (get-in m (vector 1 0)))
    (println (get-in m (vector 2 1))))
  ;; get-in on a plain map + missing key → 0
  (let [m2 (zipmap (vector 7) (vector 77))]
    (println (get-in m2 (vector 7)))
    (println (get-in m2 (vector 9 9))))
  ;; update: f over the current value
  (let [m3 (zipmap (vector 5) (vector 3))
        u (update m3 5 (fn [x] (* x 10)))]
    (println (map-get u 5)))
  ;; update a missing key starts from 0
  (println (map-get (update (map) 9 (fn [x] (+ x 1))) 9))
  ;; sort-by negation → descending
  (let [s (sort-by (fn [x] (- 0 x)) (vector 1 4 2 3))]
    (println (get s 0))
    (println (get s 3)))
  ;; sort-by abs
  (println (get (sort-by abs (vector -3 1 -2)) 0))
  0)
