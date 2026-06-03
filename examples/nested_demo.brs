;; Nested collections demo
(defn main []
  (def v [1 [2 3] 4])
  (println (count v))
  (println (get (get v 1) 0))

  (def m (map))
  (map-set m 1 [10 20])
  (map-set m 2 [30 40])
  (println (map-count m))
  (println (get (map-get m 1) 0))

  0)
