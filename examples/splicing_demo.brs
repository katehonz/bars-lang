(defmacro my-do [exprs]
  `(do ~@exprs))

(defn main []
  (my-do (list (quote (println 1)) (quote (println 2))))
  0)
