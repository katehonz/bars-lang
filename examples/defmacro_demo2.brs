(defmacro twice [x]
  `(+ ~x ~x))

(defn main []
  (println (twice 21))
  (println (twice 5))
  0)
