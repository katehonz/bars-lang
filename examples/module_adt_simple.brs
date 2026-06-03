(require "lib/adt" :as adt)

(defn main []
  (println (adt/unwrap-or (adt/Some 42) 0))
  (println (adt/unwrap-or (adt/None) 99)))
