(defmacro my-or [a b]
  `(if ~a ~a ~b))

(defn main []
  (println (my-or false 42))
  (println (my-or 10 20))
  0)
