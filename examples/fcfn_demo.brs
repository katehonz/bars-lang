;; First-class functions (Phase 17.17–17.18)
;; - Named top-level fns as values (closure vector [fnptr, env])
;; - Closed (fn […] …) lifted to __lamN
;; - Capturing lambdas: free locals packed into env
;; - Call through a local via bars_icallN

(defn apply1 [f x]
  (f x))

(defn double [n]
  (* n 2))

(defn main []
  (println (apply1 double 21))
  (println (apply1 (fn [n] (+ n 1)) 41))
  (let [f double]
    (println (f 3)))
  (println (apply1 (fn [x] (double x)) 7))
  (let [y 10]
    (println (apply1 (fn [x] (+ x y)) 32)))
  0)
