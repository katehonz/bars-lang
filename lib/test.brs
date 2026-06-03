;; Bars stdlib — Testing helpers

(defmacro assert [expr]
  `(if (not ~expr)
     (println "FAIL:")
     (println "OK:")))
