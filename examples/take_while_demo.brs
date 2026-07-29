;; take-while / drop-while + min/max (Phase 17.38)

(defn pos? [n] (> n 0))
(defn lt3? [n] (< n 3))

(defn main []
  (let [xs [1 2 0 4 5]
        a (take-while pos? xs)
        b (drop-while pos? xs)
        c (take-while lt3? [0 1 2 3 4])]
    (println (count a))
    (println (get a 0))
    (println (get a 1))
    (println (count b))
    (println (get b 0))
    (println (count c)))
  (println (min 3 7))
  (println (max 3 7))
  0)
