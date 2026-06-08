;; Bars Macro Expander — Stage 8 of self-hosting
;; Built-in macro expansion: when, unless, cond, ->, ->>
;; Transforms AST before HIR lowering.
;;
;; AST format:
;;   Atom:     [tag value]  (tag 0-5: number, symbol, string, keyword, bool/nil)
;;   Compound: [head args...] where head is an atom [tag value]

;; ---- AST helpers ----

(defn str-eq? [a b]
  (if (!= (count a) (count b)) false
    (= (str-starts-with? a b) 1)))

(defn ast-tag [x] (get x 0))
(defn ast-val [x] (get x 1))
(defn is-atom? [x] (< (ast-tag x) 1000))

;; mk-sym: create a symbol atom  [1 name]
(defn mk-sym [name]
  (let [v (vector)]
    (do (push v 1) (do (push v name) v))))

;; mk-special: create a special form head  [tag name]
(defn mk-special [tag name]
  (let [v (vector)]
    (do (push v tag) (do (push v name) v))))

;; mk-num: create a number atom  [0 n]
(defn mk-num [n]
  (let [v (vector)]
    (do (push v 0) (do (push v n) v))))

;; mk-nil: create nil  [4 "nil"]
(defn mk-nil []
  (let [v (vector)]
    (do (push v 4) (do (push v "nil") v))))

;; mk-bool [b] — create bool [5 1] or [5 0]
(defn mk-bool [b]
  (let [v (vector)]
    (do (push v 5) (do (push v b) v))))

;; mk-do [exprs] — wrap expressions in a do form  [[13 "do"] exprs...]
(defn mk-do [exprs]
  (let [v (vector)]
    (do (push v (mk-special 13 "do"))
        (loop [i 0]
          (if (>= i (count exprs))
            v
            (do (push v (get exprs i))
                (recur (+ i 1))))))))

;; mk-if [cond then else] — create if form  [[12 "if"] cond then else]
(defn mk-if [cond then else]
  (let [v (vector)]
    (do (push v (mk-special 12 "if"))
        (push v cond)
        (push v then)
        (push v else)
        v)))

;; ---- expand an expression ----

(defn expand-expr [expr]
  (if (is-atom? expr)
    expr
    (let [head (get expr 0)
          n (count expr)]
      (if (is-atom? head)
        (let [tag (ast-tag head)
              name (ast-val head)]
          (if (= tag 1)
            ;; Symbol head — check if it's a macro
            (if (str-eq? name "when")
              (expand-when expr)
            (if (str-eq? name "unless")
              (expand-unless expr)
            (if (str-eq? name "cond")
              (expand-cond expr)
            (if (str-eq? name "->")
              (expand-thread expr)
            (if (str-eq? name "->>")
              (expand-thread-last expr)
              ;; Not a macro — expand args recursively
              (let [new-expr (vector)]
                (do (push new-expr (expand-expr head))
                    (loop [i 1]
                      (if (>= i n)
                        new-expr
                        (do (push new-expr (expand-expr (get expr i)))
                            (recur (+ i 1))))))))))))
            ;; Special form or other — expand body recursively
            (let [new-expr (vector)]
              (do (push new-expr head)
                  (loop [i 1]
                    (if (>= i n)
                      new-expr
                      (do (push new-expr (expand-expr (get expr i)))
                          (recur (+ i 1)))))))))
        ;; Head is compound — expand recursively
        (let [new-expr (vector)]
          (do (push new-expr (expand-expr head))
              (loop [i 1]
                (if (>= i n)
                  new-expr
                  (do (push new-expr (expand-expr (get expr i)))
                      (recur (+ i 1)))))))))))

;; ---- built-in macro expansions ----

;; (when cond body...) => (if cond (do body...) nil)
(defn expand-when [expr]
  (let [n (count expr)]
    (if (< n 2)
      (mk-nil)
      (let [cond (expand-expr (get expr 1))]
        (if (<= n 2)
          (mk-if cond (mk-nil) (mk-nil))
          ;; Build do body from args[1..]
          (let [body-exprs (vector)]
            (do (loop [i 2]
                  (if (>= i n) 0
                    (do (push body-exprs (expand-expr (get expr i)))
                        (recur (+ i 1)))))
                (mk-if cond (mk-do body-exprs) (mk-nil)))))))))

;; (unless cond body...) => (if (not cond) (do body...) nil)
(defn expand-unless [expr]
  (let [n (count expr)]
    (if (< n 2)
      (mk-nil)
      (let [cond-expr (get expr 1)
            not-call (vector)]
        (do (push not-call (mk-sym "not"))
            (push not-call (expand-expr cond-expr))
            (let [cond not-call]
              (if (<= n 2)
                (mk-if cond (mk-nil) (mk-nil))
                (let [body-exprs (vector)]
                  (do (loop [i 2]
                        (if (>= i n) 0
                          (do (push body-exprs (expand-expr (get expr i)))
                              (recur (+ i 1)))))
                      (mk-if cond (mk-do body-exprs) (mk-nil)))))))))))

;; (cond (p1 e1) (p2 e2) ...)  =>  (if p1 e1 (if p2 e2 ... nil))
(defn expand-cond [expr]
  (let [n (count expr)]
    (if (< n 2)
      (mk-nil)
      ;; Build nested ifs from the last pair to the first
      (let [result (mk-nil)]  ;; fallback: nil
        (loop [i (- n 1) res result]
          (if (< i 1)
            res
            (let [pair (get expr i)
                  is-else (str-eq? (ast-val (get pair 0)) "else")
                  then-val (expand-expr (get pair 1))]
              (if is-else
                (recur (- i 1) then-val)  ;; :else is fallback, continue wrapping
                (let [cond-val (expand-expr (get pair 0))]
                  (recur (- i 1) (mk-if cond-val then-val res)))))))))))

;; (-> x (f a) (g b))  =>  (g (f x a) b)
(defn expand-thread [expr]
  (let [n (count expr)]
    (if (< n 2)
      (mk-nil)
      (let [result (expand-expr (get expr 1))]
        (loop [i 2 res result]
          (if (>= i n)
            res
            (let [form (get expr i)
                  new-expr (vector)]
              (if (is-atom? form)
                ;; Just a symbol: (sym x)
                (do (push new-expr form)
                    (push new-expr res)
                    (recur (+ i 1) new-expr))
                ;; Compound: (fun args...) or (fun)
                (let [head (get form 0)]
                  (do (push new-expr head)
                      (push new-expr res)
                      (loop [j 1]
                        (if (>= j (count form))
                          (recur (+ i 1) new-expr)
                          (do (push new-expr (get form j))
                              (recur (+ j 1)))))))))))))))

;; (->> x (f a) (g b))  =>  (g b (f a x))
(defn expand-thread-last [expr]
  (let [n (count expr)]
    (if (< n 2)
      (mk-nil)
      (let [result (expand-expr (get expr 1))]
        (loop [i 2 res result]
          (if (>= i n)
            res
            (let [form (get expr i)
                  new-expr (vector)]
              (if (is-atom? form)
                (do (push new-expr form)
                    (push new-expr res)
                    (recur (+ i 1) new-expr))
                (let [head (get form 0)]
                  (do (push new-expr head)
                      (loop [j 1]
                        (if (>= j (count form))
                          0
                          (do (push new-expr (get form j))
                              (recur (+ j 1)))))
                      (push new-expr res)
                      (recur (+ i 1) new-expr)))))))))))

;; ---- top-level: expand a program (list of expressions) ----

(defn expand-program [ast-list]
  (let [new-list (vector)
        n (count ast-list)]
    (loop [i 0]
      (if (>= i n)
        new-list
        (do (push new-list (expand-expr (get ast-list i)))
            (recur (+ i 1)))))))
