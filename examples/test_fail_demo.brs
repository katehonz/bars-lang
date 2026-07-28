;; Intentional failure demo — exit code 1 (not in self-test suite)
(require "lib/test" :as t)

(defn main []
  (let [ctx (t/suite "expected-failures")]
    (do
      (t/is ctx false "this should FAIL")
      (t/is-eq ctx 1 2 "1 != 2")
      ;; report only — we still want non-zero exit via finish
      (t/finish ctx))))
