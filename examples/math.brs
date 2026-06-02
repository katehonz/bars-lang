;; Math example in Bars

(defn add [a b]
  (+ a b))

(defn factorial [n]
  (if (<= n 1)
    1
    (* n (factorial (- n 1)))))

(defn main []
  (println (add 3 4))
  (println (factorial 5)))
