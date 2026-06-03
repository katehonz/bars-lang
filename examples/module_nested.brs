(require "lib/nested_outer" :as outer)

(defn main []
  (println (outer/outer-inc 41)))
