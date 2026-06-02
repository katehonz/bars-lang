(defn describe [n]
  (match n
    0 100
    1 101
    x x))

(defn main []
  (println (describe 0))
  (println (describe 1))
  (println (describe 42))
  0)
