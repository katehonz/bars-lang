;; Bars Standard Library — String functions

(defn str-empty? [^i64 s]
  (= (count s) 0))

(defn str-count [^i64 s]
  (count s))

;; Built-in string operations (provided by the C runtime):
;;   (str-trim s)              -> remove leading/trailing whitespace
;;   (str-substring s n m)     -> substring from index n, length m
;;   (str-slice s start end)   -> substring from start (inclusive) to end (exclusive)
;;   (str-split s delim)       -> split string by delimiter, returns vector of strings
;;   (str-join vec delim)      -> join vector of strings with delimiter
;;   (str-get s i)             -> byte value at index i (0-255) or -1
;;   (str-starts-with? s pre)  -> 1 if s starts with prefix, else 0
;;   (str-ends-with? s suf)    -> 1 if s ends with suffix, else 0
;;   (str-index-of s needle)   -> first index of needle, or -1
