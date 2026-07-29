;; group-by / zipmap / select-keys (Phase 17.43)

(defn pos? [n] (> n 0))

(defn main []
  ;; group-by with a named fn
  (let [g (group-by pos? (vector 1 -2 3 -4 5))]
    (println (map-count g))
    (println (count (map-get g 1)))
    (println (count (map-get g 0))))
  ;; group-by with an inline lambda (even/odd buckets)
  (let [g2 (group-by (fn [x] (% x 2)) (vector 1 2 3 4 5 6))]
    (println (count (map-get g2 0)))
    (println (count (map-get g2 1))))
  ;; zipmap stops at the shorter side
  (let [z (zipmap (vector 10 20 30) (vector 1 2))]
    (println (map-count z))
    (println (map-get z 10))
    (println (map-get z 20)))
  ;; select-keys keeps only present keys
  (let [m (zipmap (vector 1 2 3) (vector 100 200 300))
        s (select-keys m (vector 1 3 9))]
    (println (map-count s))
    (println (map-get s 1))
    (println (map-get s 3)))
  0)
