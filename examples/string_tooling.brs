(defn main []
  (let [s "Hello, Bars!"]
    (println (str-get s 0))
    (println (str-get s 7))
    (println (str-starts-with? s "Hello"))
    (println (str-starts-with? s "Bars"))
    (println (str-ends-with? s "Bars!"))
    (println (str-ends-with? s "Hello"))
    (println (str-index-of s "Bars"))
    (println (str-index-of s "Rust"))
    (println (str-index-of s "o"))
    (println (str-slice s 7 11)))
  0)
