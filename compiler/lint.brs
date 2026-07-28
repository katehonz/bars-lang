;; Bars Linter — Phase 14.2
;; Lightweight style + structure checks on source text and AST.
;;
;;   (require "compiler/lint.brs" :as lint)
;;   (lint/lint-file path src ast) → issue count (prints diagnostics)

(defn str-eq? [a b]
  (if (!= (count a) (count b)) false
    (= (str-starts-with? a b) 1)))

(defn ast-tag [x] (get x 0))
(defn ast-val [x] (get x 1))
(defn is-atom? [x] (< (ast-tag x) 1000))

(defn int-str [n] (str-from-i64 n))

(defn issue [path line kind msg]
  (do (println (str-concat path
                (str-concat ":"
                  (str-concat (int-str line)
                    (str-concat ": "
                      (str-concat kind
                        (str-concat ": " msg)))))))
      1))

;; ---- source-level checks (line-based) ----

(defn line-at [src idx]
  ;; 1-based line number of byte index
  (loop [i 0 line 1]
    (if (>= i idx) line
      (if (= (str-get src i) 10)
        (recur (+ i 1) (+ line 1))
        (recur (+ i 1) line)))))

(defn check-source [path src]
  (let [n (count src)]
    (loop [i 0 line 1 col 0 issues 0]
      (if (>= i n) issues
        (let [c (str-get src i)]
          (if (= c 10)
            ;; end of line: trailing spaces?
            (let [tr (if (if (if (> i 0) (> col 0) false)
                            (if (= (str-get src (- i 1)) 32) true
                              (= (str-get src (- i 1)) 9))
                            false)
                       (issue path line "style" "trailing whitespace")
                       0)]
              (recur (+ i 1) (+ line 1) 0 (+ issues tr)))
            (if (= c 9)
              (let [t (issue path line "style" "tab character (use spaces)")]
                (recur (+ i 1) line (+ col 1) (+ issues t)))
              (if (if (= c 13)
                    (if (< (+ i 1) n) (!= (str-get src (+ i 1)) 10) true)
                    false)
                (let [t (issue path line "style" "bare CR (use LF)")]
                  (recur (+ i 1) line (+ col 1) (+ issues t)))
                ;; long line: check when we see newline or EOF later — track col
                (if (if (= col 100) true false)
                  ;; only report once per line at col 101
                  (let [t (issue path line "style" "line longer than 100 columns")]
                    (recur (+ i 1) line (+ col 1) (+ issues t)))
                  (recur (+ i 1) line (+ col 1) issues))))))))))

;; ---- AST checks ----

(defn is-vec-form? [x]
  (if (is-atom? x) false
    (let [head (get x 0)]
      (if (is-atom? head) (= (ast-tag head) 28) false))))

(defn form-line [form]
  (if (is-atom? form)
    (if (>= (count form) 3)
      ;; offset present but we don't have src here — return 1; caller uses path only
      1
      1)
    (if (> (count form) 0)
      (form-line (get form 0))
      1)))

(defn head-tag [form]
  (if (is-atom? form) -1
    (let [h (get form 0)]
      (if (is-atom? h) (ast-tag h) -1))))

(defn head-name [form]
  (if (is-atom? form) ""
    (let [h (get form 0)]
      (if (is-atom? h) (ast-val h) ""))))

;; defn shape: (defn name [params...] body...)
(defn check-defn [path form]
  (let [n (count form)]
    (if (< n 3)
      (issue path 1 "lint" "defn has too few forms (need name + params)")
      (let [name-a (get form 1)
            params (get form 2)
            issues 0
            i1 (if (if (is-atom? name-a) (= (ast-tag name-a) 1) false)
                 0
                 (issue path 1 "lint" "defn name must be a symbol"))
            i2 (if (is-vec-form? params) 0
                 (issue path 1 "lint" "defn params must be a vector"))]
        (+ i1 i2)))))

(defn check-top [path form]
  (if (is-atom? form)
    (issue path 1 "lint" "bare atom at top level")
    (let [t (head-tag form)
          name (head-name form)]
      (if (= t 10) (check-defn path form)
        (if (= t 21) 0  ;; defmacro
          (if (= t 18) 0  ;; defstruct
            (if (= t 19) 0  ;; deftype
              (if (= t 20) 0  ;; extern
                (if (str-eq? name "require") 0
                  (if (str-eq? name "def") 0
                    ;; allow other top-level calls (e.g. load in older libs)
                    0))))))))))

(defn check-ast [path ast]
  (let [n (count ast)]
    (loop [i 0 issues 0]
      (if (>= i n) issues
        (recur (+ i 1) (+ issues (check-top path (get ast i))))))))

;; Returns total issue count. Prints each issue.
(defn lint-all [path src ast]
  (let [s (check-source path src)
        a (if (= ast 0) 0 (check-ast path ast))]
    (+ s a)))
