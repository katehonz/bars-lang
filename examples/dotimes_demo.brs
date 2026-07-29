;; dotimes (Phase 17.25)

(defn main []
  (dotimes [i 4]
    (println i))
  ;; n evaluated once
  (let [n 3
        acc (vector)]
    (dotimes [k n]
      (push acc (* k k)))
    (println (get acc 0))
    (println (get acc 2))
    (println (count acc)))
  0)
