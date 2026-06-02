;; Macro example in Bars

(defn add [a b]
  (+ a b))

(defn mul [a b]
  (* a b))

(defn main []
  ;; when macro
  (when true
    (println 1))

  ;; unless macro
  (unless false
    (println 2))

  ;; -> thread-first
  (println (-> 5 (add 3) (mul 2)))

  ;; ->> thread-last
  (println (->> 5 (add 3) (mul 2))))
