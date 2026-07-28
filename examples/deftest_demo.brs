;; deftest macro (lib/test) — requires self-host user defmacro (Phase 17.2)
(require "lib/test" :as t)

(t/deftest test-arithmetic
  (do
    (t/section "arithmetic")
    (t/is ctx (= (+ 1 2) 3) "(+ 1 2)")
    (t/is ctx (= (* 6 7) 42) "(* 6 7)")
    (t/is-eq ctx 10 (- 15 5) "sub")))

(t/deftest test-logic
  (do
    (t/section "logic")
    (t/is ctx true "true")
    (t/is-not ctx false "not false")))

(defn main []
  (let [ctx (t/suite "deftest_demo")]
    (do
      (test-arithmetic ctx)
      (test-logic ctx)
      (t/finish ctx))))
