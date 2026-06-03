(require "lib/core" :as core)

(defn main []
  (let [v (core/range 1 5)]
    (println v)
    (println (count v))
    (println (core/inc 5))
    (println (core/abs -10))
    (println (core/max 3 7))
    (println (core/min 3 7))
    (println (core/even? 4))
    (println (core/odd? 5))
    (println (core/empty? v))
    (println (core/empty? (vector)))
    (println (core/first v))
    (println (core/nth v 2))
    0))
