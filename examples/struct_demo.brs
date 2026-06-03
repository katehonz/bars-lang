(defstruct Point [x y])

(defn main []
  (let [p (Point 10 20)]
    (println (.x p))
    (println (.y p))
    0))
