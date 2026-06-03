;; String operations demo: trim, substring, split, join

(defn main []
  (let [s "  Hello, Bars!  "]
    (println (str-trim s))
    (println (str-substring "Hello, Bars!" 7 5)))

  (let [parts (str-split "a,b,c,d" ",")]
    (println (count parts))
    (println parts)
    (println (str-join parts "-")))

  0)
