;; Test framework demo — context suite + hard assert
(require "lib/test" :as t)

(defn test-arithmetic [ctx]
  (do
    (t/section "arithmetic")
    (t/is ctx (= (+ 1 2) 3) "(+ 1 2) = 3")
    (t/is ctx (= (* 6 7) 42) "(* 6 7) = 42")
    (t/is-eq ctx 10 (- 15 5) "(- 15 5)")
    (t/is-not ctx (= 1 2) "1 != 2")))

(defn test-logic [ctx]
  (do
    (t/section "logic")
    (t/is ctx true "true is true")
    (t/is-zero ctx 0 "zero")
    (t/is-truthy ctx 7 "non-zero is truthy")))

(defn main []
  (t/assert! (= 1 1) "sanity")
  (let [ctx (t/suite "test_demo")]
    (do
      (test-arithmetic ctx)
      (test-logic ctx)
      (t/finish ctx))))
