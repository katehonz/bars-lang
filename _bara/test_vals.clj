(do
  (defmacro is [form]
    `(let [result# ~form]
       (if result# nil (println "FAIL:" (quote ~form)))))
  (println [1 2 (is true) 3])
)
