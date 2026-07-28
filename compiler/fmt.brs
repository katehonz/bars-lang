;; Bars Formatter — Phase 14.2
;; Pretty-print AST from the self-hosted reader.
;;
;;   (require "compiler/fmt.brs" :as fmt)
;;   (fmt/format-ast ast) → string (trailing newline)

(defn str-eq? [a b]
  (if (!= (count a) (count b)) false
    (= (str-starts-with? a b) 1)))

(defn ast-tag [x] (get x 0))
(defn ast-val [x] (get x 1))
(defn is-atom? [x] (< (ast-tag x) 1000))

(defn int-str [n] (str-from-i64 n))

(defn spaces [n]
  (loop [i 0 acc ""]
    (if (>= i n) acc
      (recur (+ i 1) (str-concat acc " ")))))

(defn escape-str [s]
  (let [n (count s)]
    (loop [i 0 acc ""]
      (if (>= i n) acc
        (let [c (str-get s i)]
          (if (= c 34)
            (recur (+ i 1) (str-concat acc "\\\""))
            (if (= c 92)
              (recur (+ i 1) (str-concat acc "\\\\"))
              (if (= c 10)
                (recur (+ i 1) (str-concat acc "\\n"))
                (if (= c 13)
                  (recur (+ i 1) (str-concat acc "\\r"))
                  (if (= c 9)
                    (recur (+ i 1) (str-concat acc "\\t"))
                    (recur (+ i 1)
                      (str-concat acc (str-slice s i (+ i 1))))))))))))))

(defn format-atom [a]
  (let [t (ast-tag a)]
    (if (= t 0) (int-str (ast-val a))
      (if (= t 1) (ast-val a)
        (if (= t 2)
          (str-concat "\"" (str-concat (escape-str (ast-val a)) "\""))
          (if (= t 3)
            (str-concat ":" (ast-val a))
            (if (= t 4) "nil"
              (if (= t 5)
                (if (= (ast-val a) 1) "true" "false")
                (if (if (>= t 10) (<= t 27) false)
                  (ast-val a)
                  (if (= t 28) ""
                    "?"))))))))))

(defn is-vec-form? [x]
  (if (is-atom? x) false
    (let [head (get x 0)]
      (if (is-atom? head)
        (= (ast-tag head) 28)
        false))))

(defn multiline-head? [name]
  (if (str-eq? name "defn") true
    (if (str-eq? name "defmacro") true
      (if (str-eq? name "let") true
        (if (str-eq? name "loop") true
          (if (str-eq? name "do") true
            (if (str-eq? name "match") true
              (if (str-eq? name "if") true
                (if (str-eq? name "fn") true
                  false)))))))))

(defn head-name [form]
  (if (is-atom? form) ""
    (let [h (get form 0)]
      (if (is-atom? h)
        (let [t (ast-tag h)]
          (if (if (= t 1) true (if (>= t 10) (<= t 27) false))
            (ast-val h)
            ""))
        ""))))

(defn join-space [parts]
  (let [n (count parts)]
    (loop [i 0 acc ""]
      (if (>= i n) acc
        (let [p (get parts i)]
          (if (= i 0)
            (recur (+ i 1) p)
            (recur (+ i 1) (str-concat acc (str-concat " " p)))))))))

(defn format-expr [expr indent]
  (if (is-atom? expr)
    (format-atom expr)
    (if (is-vec-form? expr)
      (format-vector expr indent)
      (format-list expr indent))))

(defn format-vector [expr indent]
  (let [n (count expr)
        parts (vector)]
    (do (loop [i 1]
          (if (>= i n) 0
            (do (push parts (format-expr (get expr i) indent))
                (recur (+ i 1)))))
        (str-concat "[" (str-concat (join-space parts) "]")))))

(defn format-list-inline [expr indent]
  (let [n (count expr)
        parts (vector)]
    (do (loop [i 0]
          (if (>= i n) 0
            (do (push parts (format-expr (get expr i) indent))
                (recur (+ i 1)))))
        (str-concat "(" (str-concat (join-space parts) ")")))))

(defn format-list-multi [expr indent]
  (let [n (count expr)
        ind2 (+ indent 2)
        pad (spaces ind2)
        head (if (> n 0) (format-expr (get expr 0) indent) "")]
    (if (<= n 1)
      (str-concat "(" (str-concat head ")"))
      (loop [i 1 acc (str-concat "(" head)]
        (if (>= i n)
          (str-concat acc ")")
          (let [piece (format-expr (get expr i) ind2)]
            (recur (+ i 1)
              (str-concat acc (str-concat "\n" (str-concat pad piece))))))))))

;; defn/defmacro/fn: (defn name [params]\n  body...)
(defn format-defn-like [expr indent]
  (let [n (count expr)
        ind2 (+ indent 2)
        pad (spaces ind2)
        head (if (> n 0) (format-expr (get expr 0) indent) "")
        name (if (> n 1) (format-expr (get expr 1) indent) "")
        params (if (> n 2) (format-expr (get expr 2) indent) "[]")
        open (str-concat "("
                (str-concat head
                  (str-concat " "
                    (str-concat name (str-concat " " params)))))]
    (if (<= n 3)
      (str-concat open ")")
      (loop [i 3 acc open]
        (if (>= i n)
          (str-concat acc ")")
          (let [piece (format-expr (get expr i) ind2)]
            (recur (+ i 1)
              (str-concat acc (str-concat "\n" (str-concat pad piece))))))))))

;; if: (if cond\n  then\n  else)
(defn format-if-like [expr indent]
  (let [n (count expr)
        ind2 (+ indent 2)
        pad (spaces ind2)
        head (if (> n 0) (format-expr (get expr 0) indent) "")
        cond (if (> n 1) (format-expr (get expr 1) indent) "")
        open (str-concat "(" (str-concat head (str-concat " " cond)))]
    (if (<= n 2)
      (str-concat open ")")
      (loop [i 2 acc open]
        (if (>= i n)
          (str-concat acc ")")
          (let [piece (format-expr (get expr i) ind2)]
            (recur (+ i 1)
              (str-concat acc (str-concat "\n" (str-concat pad piece))))))))))

(defn format-list [expr indent]
  (let [n (count expr)
        name (head-name expr)]
    (if (if (str-eq? name "defn") true
          (if (str-eq? name "defmacro") true
            (str-eq? name "fn")))
      (format-defn-like expr indent)
      (if (str-eq? name "if")
        (format-if-like expr indent)
        (if (if (multiline-head? name) true (> n 6))
          (format-list-multi expr indent)
          (format-list-inline expr indent))))))

(defn format-program [ast]
  (let [n (count ast)]
    (loop [i 0 acc ""]
      (if (>= i n) acc
        (let [form (format-expr (get ast i) 0)
              next (if (= i 0) form
                     (str-concat acc (str-concat "\n\n" form)))]
          (recur (+ i 1) next))))))

(defn with-final-nl [s]
  (let [n (count s)]
    (if (= n 0) "\n"
      (if (= (str-get s (- n 1)) 10) s
        (str-concat s "\n")))))

(defn format-ast [ast]
  (with-final-nl (format-program ast)))
