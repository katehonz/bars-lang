;; Bars Standard Library — String functions
(load "lib/core.brs")

(defn str-empty? [^i64 s]
  (= (count s) 0))

(defn str-count [^i64 s]
  (count s))

;; Built-in string operations (provided by the C runtime):
;;   (str-trim s)           -> remove leading/trailing whitespace
;;   (str-substring s n m)  -> substring from index n, length m
;;   (str-split s delim)    -> split string by delimiter, returns vector of strings
;;   (str-join vec delim)   -> join vector of strings with delimiter
