;; Define a Result type with two variants
(deftype Result [Ok i64] [Err i64])

(defn handle [res]
  (match res
    (Ok value) (+ value 1)
    (Err code) (* code -1)))

(println (handle (Ok 41)))
(println (handle (Err 5)))
