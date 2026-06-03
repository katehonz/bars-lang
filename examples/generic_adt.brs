;; Generic ADT demo — Option and Result with type variables
(load "lib/adt.brs")

(defn safe-div [a b]
  (if (= b 0)
    (None)
    (Some (/ a b))))

(defn parse-number [s]
  (if (= (count s) 0)
    (Err "empty string")
    (Ok (count s))))  ; dummy parse: return length as number

(defn main []
  (let [result1 (safe-div 10 2)
        result2 (safe-div 10 0)]
    (println (unwrap-or result1 0))
    (println (unwrap-or result2 0)))

  (let [n1 (parse-number "hello")
        n2 (parse-number "")]
    (println (unwrap-ok n1))
    (println (unwrap-ok n2)))

  ;; Option works with any type
  (let [opt-str (Some "bars")
        opt-vec (Some [1 2 3])]
    (println (unwrap-or opt-str "default"))
    (println (count (unwrap-or opt-vec [0]))))

  0)
