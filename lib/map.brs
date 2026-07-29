;; Bars Standard Library — Map functions
(load "lib/core.brs")

(defn map-empty? [^i64 m]
  (= (map-count m) 0))

(defn map-has? [^i64 m ^i64 key]
  "1 if key exists in map (even when mapped to 0), else 0."
  (= (map-contains? m key) 1))

;; Built-in map operations (provided by the C runtime):
;;   (map-contains? m key)  -> 1 if key exists (exact), else 0
;;   (map-keys m)           -> vector of keys
;;   (map-values m)         -> vector of values
