; FizzBuzz — classic programming challenge
; Tests: cond, mod, map, range, str, println

(defn fizzbuzz [n]
  (cond
    (= (mod n 15) 0) "FizzBuzz"
    (= (mod n 3) 0) "Fizz"
    (= (mod n 5) 0) "Buzz"
    :else (str n)))

(println "=== FizzBuzz 1-30 ===")
(doseq [i (range 1 31)]
  (println (fizzbuzz i)))
