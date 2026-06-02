(load "lib/core.brs")

(defn main []
  (let [v (range 1 5)]
    (println v)
    (println (count v))
    (println (inc 5))
    (println (abs -10))
    (println (max 3 7))
    (println (min 3 7))
    (println (even? 4))
    (println (odd? 5))
    (println (empty? v))
    (println (empty? (vector)))
    (println (first v))
    (println (nth v 2))
    0))
