;; Bars Standard Library — String functions
(load "lib/core.brs")

(defn str-empty? [^i64 s]
  (= (count s) 0))

(defn str-count [^i64 s]
  (count s))
