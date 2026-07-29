;; identity + constantly (Phase 17.31)

(defn main []
  (println (identity 42))
  (println (identity 0))
  (let [f (constantly 7)]
    (println (f 1))
    (println (f 99)))
  ;; value captured once
  (let [n 10
        g (constantly (+ n 1))]
    (println (g 0)))
  0)
