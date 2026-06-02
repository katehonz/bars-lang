(defn main []
  (let [result (loop [i 0 acc 0]
                 (if (= i 10)
                   acc
                   (recur (+ i 1) (+ acc i))))]
    (println result)
    0))
