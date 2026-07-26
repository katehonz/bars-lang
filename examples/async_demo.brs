(require "lib/async" :as async)

;; Poll a shared cell: first two polls pending, then ready 99.
(defn step-cell [cell]
  (let [n (get cell 0)]
    (if (< n 2)
      (do (pop cell)
          (push cell (+ n 1))
          (async/pending))
      (async/ready 99))))

(defn main []
  (let [cell (vector)
        _ (push cell 0)
        r0 (step-cell cell)
        r1 (step-cell cell)
        r2 (step-cell cell)
        r7 (async/ready 7)]
    (do (println (if (async/pending? r0) 1 0))
        (println (if (async/pending? r1) 1 0))
        (println (if (async/ready? r2) 1 0))
        (println (async/unwrap r2))
        (println (async/unwrap r7))
        0)))
