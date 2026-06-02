(defstruct Point [x y])

(defn describe [p]
  (match p
    (Point 0 0) 0
    (Point x y) (+ x y)))

(defn main []
  (println (describe (Point 0 0)))
  (println (describe (Point 3 4)))
  0)
