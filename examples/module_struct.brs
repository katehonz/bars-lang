(require "lib/struct_test" :as geo)

(defn main []
  (println (geo/point-sum (geo/Point 10 20))))
