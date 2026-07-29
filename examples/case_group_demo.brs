;; case multi-const groups (Phase 17.29)

(defn kind [n]
  (case n
    (1 2 3) 1
    (4 5) 2
    9 3
    0))

(defn main []
  (println (kind 1))
  (println (kind 3))
  (println (kind 5))
  (println (kind 9))
  (println (kind 7))
  ;; vector group also works
  (println (case 2
             [1 2 3] 42
             0))
  0)
