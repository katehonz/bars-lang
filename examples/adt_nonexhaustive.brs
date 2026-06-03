(deftype Option [Some i64] [None])

(defn broken [opt]
  (match opt
    (Some n) n))

(broken (Some 42))
