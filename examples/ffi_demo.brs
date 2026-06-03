;; FFI demo: calling C functions from Bars
;; putchar takes one int and prints a character

(extern "putchar" [c i64] -> i64)

(defn main []
  (putchar 65))  ;; Should print 'A'
