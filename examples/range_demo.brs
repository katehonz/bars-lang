;; range (Phase 17.39)

(defn main []
  (let [a (range 4)
        b (range 2 6)
        c (range 0 10 3)
        d (range 5 0 -2)]
    (println (count a))
    (println (get a 0))
    (println (get a 3))
    (println (count b))
    (println (get b 0))
    (println (get b 3))
    (println (count c))
    (println (get c 2))
    (println (count d))
    (println (get d 0))
    (println (get d 2)))
  ;; with for
  (let [xs (for [i (range 3)] (* i 10))]
    (println (get xs 2)))
  0)
