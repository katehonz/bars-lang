;; Set demo
(defn main []
  (def s (set))
  (set-add s 1)
  (set-add s 2)
  (set-add s 3)
  (println (set-count s))
  (println (set-contains? s 2))
  (println (set-contains? s 99))
  (def s2 (set 7 7 8 9))
  (println (set-count s2))
  (println (set-contains? s2 7))
  0)
