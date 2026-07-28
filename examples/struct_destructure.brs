;; struct destructuring in let
(defstruct Point [x y])

(defn main []
  ;; struct destructuring in let
  (let [(Point a b) (Point 100 200)]
    (do (println a)
        (println b)
        0)))
