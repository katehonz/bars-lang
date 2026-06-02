;; Bars Standard Library — Map functions
(load "lib/core.brs")

(defn map-empty? [^i64 m]
  (= (map-count m) 0))

(defn map-has? [^i64 m ^i64 key]
  (not (= (map-get m key) 0)))
