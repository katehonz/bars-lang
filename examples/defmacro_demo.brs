(defmacro unless [cond body]
  `(if (not ~cond) ~body nil))

(defn main []
  (println (unless false 42))
  (println (unless true 99))
  0)
