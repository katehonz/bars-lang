;; Generic ADT demo — Option and Result with type variables
(require "lib/adt" :as adt)

(defn safe-div [a b]
  (if (= b 0)
    (adt/None)
    (adt/Some (/ a b))))

(defn parse-number [s]
  (if (= (count s) 0)
    (adt/Err "empty string")
    (adt/Ok (count s))))  ; dummy parse: return length as number

(defn main []
  (let [result1 (safe-div 10 2)
        result2 (safe-div 10 0)]
    (println (adt/unwrap-or result1 0))
    (println (adt/unwrap-or result2 0)))

  (let [n1 (parse-number "hello")
        n2 (parse-number "")]
    (println (adt/unwrap-ok n1))
    (println (adt/unwrap-ok n2)))

  ;; Option works with any type
  (let [opt-str (adt/Some "bars")
        opt-vec (adt/Some [1 2 3])]
    (println (adt/unwrap-or opt-str "default"))
    (println (count (adt/unwrap-or opt-vec [0]))))

  0)
