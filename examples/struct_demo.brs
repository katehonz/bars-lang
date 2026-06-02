(defstruct Point [x y])

(defn main []
  (def p (Point 10 20))
  (println (.x p))
  (println (.y p))
  0)
