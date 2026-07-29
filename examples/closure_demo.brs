;; Capturing closures (Phase 17.18)
;; Free locals become an env vector; the fn gets [__env, params…].

(defn apply1 [f x]
  (f x))

(defn main []
  (let [y 10]
    (let [f (fn [x] (+ x y))]
      (println (f 32))))
  (let [a 1 b 2]
    (let [g (fn [x] (+ (+ a b) x))]
      (println (g 10))))
  (let [n 5]
    (println (apply1 (fn [x] (* x n)) 3)))
  0)
