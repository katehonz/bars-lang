; Math example
(defn square [x]
  (* x x))

(defn factorial [n]
  (if (= n 0)
    1
    (* n (factorial (- n 1)))))

(let [a 5]
  (println (square a))
  (println (factorial a)))
