;; WASI println smoke — prints 7 then 120 (like math.brs without host runtime).
(defn add [a b]
  (+ a b))

(defn factorial [n]
  (if (<= n 1)
    1
    (* n (factorial (- n 1)))))

(defn main []
  (do (println (add 3 4))
      (println (factorial 5))
      0))
