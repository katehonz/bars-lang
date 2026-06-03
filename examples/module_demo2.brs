(require "lib/test_module" :as tm)

(defn main []
  (println (tm/use-helper 41)))
