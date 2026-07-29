;; Indirect calls with 5–6 args via bars_icall5/6 (Phase 17.20)

(defn add6 [a b c d e f]
  (+ (+ (+ (+ (+ a b) c) d) e) f))

(defn main []
  (let [f add6]
    (println (f 1 2 3 4 5 6)))
  (let [g (fn [a b c d e] (+ (+ (+ (+ a b) c) d) e))]
    (println (g 10 20 30 40 50)))
  0)
