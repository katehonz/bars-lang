;; Test map with inline lambda

(defn main []
  (let [v [1 2 3 4 5]
        doubled (map (fn [x] (* x 2)) v)]
    (println (get doubled 0))
    (println (get doubled 1))))
