;; (apply f args-vec) — call first-class fn with dynamic arity (Phase 17.22)

(defn add2 [a b] (+ a b))
(defn add3 [a b c] (+ (+ a b) c))
(defn six [a b c d e f]
  (+ (+ (+ (+ (+ a b) c) d) e) f))

(defn main []
  (let [f add2]
    (println (apply f [20 22])))
  (let [g add3]
    (println (apply g [10 20 12])))
  ;; capturing closure
  (let [n 100
        h (fn [x y] (+ (+ x y) n))]
    (println (apply h [1 2])))
  (let [s six]
    (println (apply s [1 2 3 4 5 6])))
  0)
