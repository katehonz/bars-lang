(require "lib/test" :as test)

(defn main []
  (test/assert (= (+ 1 2) 3))
  (test/assert (= (* 6 7) 42))
  (test/assert false))
