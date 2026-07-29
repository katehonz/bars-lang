;; Multi-binding doseq/for + when-not (Phase 17.26)

(defn main []
  ;; nested doseq (cartesian)
  (doseq [x [1 2]
          y [10 20]]
    (println (+ x y)))
  ;; multi for flattens into one vector
  (let [ps (for [a [1 2]
                 b [3 4]]
             (* a b))]
    (println (count ps))
    (println (get ps 0))
    (println (get ps 3)))
  (when-not 0 (println 99))
  (when-not 1 (println 0))
  0)
