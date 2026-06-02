;; Map example in Bars
(defn main []
  (def scores (map))
  (map-set scores 1 100)
  (map-set scores 2 200)
  (println (map-count scores))
  (println (map-get scores 1))
  (println (map-get scores 2)))
