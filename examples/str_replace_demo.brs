;; str-replace demo — replace all occurrences of a substring
;; Expected output:
;;   hi world hi
;;   bbbbbb
;;   nothing here
;;   abc
;;   one-one-one
(defn main []
  (do
    (println (str-replace "hello world hello" "hello" "hi"))
    (println (str-replace "aaa" "a" "bb"))
    (println (str-replace "nothing here" "x" "y"))
    (println (str-replace "abc" "" "z"))
    (println (str-replace "one one one" " " "-"))))
