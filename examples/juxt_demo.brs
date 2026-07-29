;; juxt (Phase 17.32)

(defn double [n] (* n 2))
(defn square [n] (* n n))
(defn add1 [n] (+ n 1))

(defn main []
  (let [j (juxt double square add1)]
    (let [r (j 5)]
      (println (get r 0))
      (println (get r 1))
      (println (get r 2))
      (println (count r))))
  (let [k (juxt identity)]
    (println (get (k 42) 0)))
  0)
