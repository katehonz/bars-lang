;; take / drop (Phase 17.37)

(defn main []
  (let [xs [1 2 3 4 5]
        a (take 3 xs)
        b (drop 2 xs)
        c (take 10 xs)
        d (drop 10 xs)]
    (println (count a))
    (println (get a 0))
    (println (get a 2))
    (println (count b))
    (println (get b 0))
    (println (count c))
    (println (count d)))
  0)
