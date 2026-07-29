;; while (Phase 17.27) — condition re-checked each iteration

(defn main []
  ;; Drain from the end (pop removes last)
  (let [xs (vector 0 1 2 3)]
    (while (> (count xs) 0)
      (println (last xs))
      (pop xs)))
  (let [ys (vector)]
    (push ys 10)
    (push ys 20)
    (push ys 30)
    (while (> (count ys) 0)
      (println (last ys))
      (pop ys)))
  0)
