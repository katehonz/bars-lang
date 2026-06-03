;; Higher-order function demo: map, filter, reduce

(defn inc [x] (+ x 1))
(defn even? [x] (= (% x 2) 0))
(defn add [a b] (+ a b))

(defn main []
  (let [v [1 2 3 4 5]]
    (println (count (map inc v)))
    (println (count (filter even? v)))
    (println (reduce add 0 v))))
