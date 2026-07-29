;; if-let / when-let + when / unless / threading (Phase 17.21)

(defn maybe-pos [n]
  (if (> n 0) n 0))

(defn main []
  (when 1 (println 1))
  (unless 0 (println 2))
  (if-let [x (maybe-pos 7)]
    (println x)
    (println 0))
  (if-let [y (maybe-pos 0)]
    (println 99)
    (println 3))
  (when-let [z (maybe-pos 4)]
    (println z))
  (println (-> 1 (+ 2) (* 3)))
  (println (->> 5 (+ 1) (* 2)))
  0)
