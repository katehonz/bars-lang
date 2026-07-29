;; Nested capturing closures (Phase 17.19)
;; Outer free `a` and param `x` are visible to the inner lambda.

(defn main []
  (let [a 1]
    (let [f (fn [x]
              (let [g (fn [y] (+ (+ a x) y))]
                (g 10)))]
      (println (f 2))))
  0)
