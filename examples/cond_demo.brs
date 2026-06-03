(defn main []
  (let [x 2]
    (println (cond (= x 1) 10 (= x 2) 20 :else 30))
    (println (cond (= x 3) 100 :else 200))
    0))
