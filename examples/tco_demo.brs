;; Automatic TCO demo — self-tail-recursive defns run in constant stack.
;; Expected output:
;;   0        (count-down 1000000 — would stack-overflow without TCO)
;;   3628800  (fact 10 — non-tail self-recursion, stays a real call)
;;   42       (add — no self-call, untouched)
;;   0        (let/do tail positions)
;;   0        (match arm tail position)

;; (a) deep tail recursion: if-branch tail position
(defn count-down [n]
  (if (= n 0) 0 (count-down (- n 1))))

;; (b) non-tail self-recursion: stays an ordinary recursive call
(defn fact [n]
  (if (= n 0) 1 (* n (fact (- n 1)))))

;; (c) no self-calls: left unchanged
(defn add [a b] (+ a b))

;; tail call through let + do
(defn let-count [n]
  (do 0
    (let [m (- n 1)]
      (if (= n 0) 0 (let-count m)))))

;; tail call in a match arm
(defn match-count [n]
  (match n
    0 0
    _ (match-count (- n 1))))

(defn main []
  (do (println (count-down 1000000))
      (println (fact 10))
      (println (add 40 2))
      (println (let-count 500000))
      (println (match-count 500000))
      0))
