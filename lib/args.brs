;; Bars Standard Library — CLI argument helpers (Phase 14.1)
;; Built on args-count / args-get (argv). Index 0 is the program name.
;;
;;   (require "lib/args" :as args)
;;   (args/has-flag? "--verbose")
;;   (args/flag-value "--out")   ; next token, or ""
;;   (args/count)

(defn str-eq? [a b]
  (if (!= (count a) (count b)) false
    (= (str-starts-with? a b) 1)))

(defn count-args []
  (args-count))

(defn get-arg [i]
  (args-get i))

;; True if any argv element equals flag exactly.
(defn has-flag? [flag]
  (let [n (args-count)]
    (loop [i 1]
      (if (>= i n) false
        (if (str-eq? (args-get i) flag) true
          (recur (+ i 1)))))))

;; Value after flag (e.g. --out path). Empty string if missing.
(defn flag-value [flag]
  (let [n (args-count)]
    (loop [i 1]
      (if (>= i n) ""
        (if (str-eq? (args-get i) flag)
          (if (>= (+ i 1) n) ""
            (args-get (+ i 1)))
          (recur (+ i 1)))))))

;; Collect non-flag positionals (tokens not starting with '-').
(defn positionals []
  (let [n (args-count)
        out (vector)]
    (loop [i 1]
      (if (>= i n) out
        (let [a (args-get i)
              c (str-get a 0)]
          (if (= c 45)
            ;; skip flag; if --key value form, skip value when next doesn't start with -
            (if (if (< (+ i 1) n)
                  (!= (str-get (args-get (+ i 1)) 0) 45)
                  false)
              (recur (+ i 2))
              (recur (+ i 1)))
            (do (push out a)
                (recur (+ i 1)))))))))
