;; if-not + complement (Phase 17.30)

(defn zero? [n] (= n 0))

(defn main []
  (println (if-not 0 1 2))
  (println (if-not 1 1 2))
  (let [nz? (complement zero?)]
    (println (if (nz? 0) 1 0))
    (println (if (nz? 5) 1 0)))
  0)
