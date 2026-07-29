;; First-class closed functions (Phase 17.17)
;; - Named top-level fns as values (funcref)
;; - Closed (fn […] …) lifted to __lamN + funcref
;; - Call through a local via icall
;; Captures of outer locals are not supported yet.

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
  0)
