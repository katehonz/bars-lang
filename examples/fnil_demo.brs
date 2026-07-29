;; fnil — replace nil/0 args with defaults (Phase 17.34)
;; Arity of the result = number of defaults (1–3).

(defn add2 [a b] (+ a b))
(defn add3 [a b c] (+ (+ a b) c))

(defn main []
  (let [f (fnil identity 42)]
    (println (f 7))
    (println (f 0)))
  (let [g (fnil add2 1 2)]
    (println (g 10 20))
    (println (g 0 0))
    (println (g 7 0)))
  (let [h (fnil add3 1 2 3)]
    (println (h 0 0 0)))
  0)
