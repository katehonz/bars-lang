(deftype Option [Some i64] [None])

(defn describe [opt]
  (match opt
    (Some n) (println n)
    None (println 0)))

(describe (Some 42))
(describe (None))
