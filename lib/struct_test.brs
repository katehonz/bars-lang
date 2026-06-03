(defstruct Point [x y])

(defn point-sum [p]
  (+ (.x p) (.y p)))
