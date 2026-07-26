(require "lib/args" :as args)

(defn main []
  (let [n (args/count-args)
        has (if (args/has-flag? "--demo") 1 0)
        val (args/flag-value "--demo")
        pos (args/positionals)]
    (do (println (if (>= n 1) 1 0))
        (println has)
        (println val)
        (println (count pos))
        0)))
