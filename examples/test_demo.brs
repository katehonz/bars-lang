(load "lib/test.brs")

(defn main []
  (assert (= (+ 1 2) 3))
  (assert (= (* 6 7) 42))
  (assert false))
