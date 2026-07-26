;; Bars Standard Library — Regex (Phase 14.1)
;; Thin wrappers over POSIX extended regex in the C runtime.
;;
;;   (require "lib/regex" :as re)
;;   (re/matches? "abc123" "[a-z]+[0-9]+")  ; full match
;;   (re/find "xx42yy" "[0-9]+")            ; start index or -1

(defn matches? [text pattern]
  (= (bars_re_is_match text pattern) 1))

(defn find [text pattern]
  (bars_re_find text pattern))

;; 1 if pattern occurs anywhere in text.
(defn contains? [text pattern]
  (!= (bars_re_find text pattern) -1))
