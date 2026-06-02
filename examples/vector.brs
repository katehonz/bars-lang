;; Vector example in Bars
(defn main []
  (def nums (vector 10 20 30))
  (push nums 40)
  (println (count nums))
  (println (get nums 0))
  (println (get nums 3)))
