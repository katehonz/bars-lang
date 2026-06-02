(defn square [x]
  (* x x))

(def numbers [1 2 3 4 5])

(println (map square numbers))
(println (filter (fn [x] (> x 2)) numbers))
(println (reduce + 0 numbers))
