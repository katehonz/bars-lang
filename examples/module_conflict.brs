(require "lib/conflict_a" :as a)
(require "lib/conflict_b" :as b)

(defn main []
  (println (+ (a/foo) (b/foo))))
