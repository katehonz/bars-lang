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

;; ---- expand helpers for special forms ----
;; Vector marker tag 28: [[28] e0 e1 ...] from reader

(defn is-vec-marker? [x]
  (if (is-atom? x) false
    (let [head (get x 0)]
      (if (is-atom? head)
        (= (ast-tag head) 28)
        false))))

(defn unwrap-vec [v]
  (if (is-vec-marker? v)
    (let [n (count v)
          out (vector)]
      (do (loop [i 1]
            (if (>= i n) 0
              (do (push out (get v i))
                  (recur (+ i 1)))))
          out))
    v))

(defn wrap-vec [elems]
  (let [out (vector)
        n (count elems)]
    (do (push out (mk-special 28 "vec"))
        (loop [i 0]
          (if (>= i n) out
            (do (push out (get elems i))
                (recur (+ i 1))))))))

;; let/loop bindings: [name1 val1 name2 val2 ...] — expand only values
(defn expand-bindings [binds]
  (let [plain (unwrap-vec binds)
        n (count plain)
        new-b (vector)]
    (loop [i 0]
      (if (>= i n) (wrap-vec new-b)
        (do (push new-b (get plain i))
            (if (< (+ i 1) n)
              (push new-b (expand-expr (get plain (+ i 1))))
              0)
            (recur (+ i 2)))))))

(defn expand-children-from [expr start]
  (let [n (count expr)
        new-expr (vector)]
    (do (push new-expr (get expr 0))
        (loop [i 1]
          (if (>= i n) new-expr
            (if (< i start)
              (do (push new-expr (get expr i))
                  (recur (+ i 1)))
              (do (push new-expr (expand-expr (get expr i)))
                  (recur (+ i 1)))))))))

(defn expand-special [expr tag]
  ;; 10=defn: keep name+params (unwrap params), expand body
  ;; 11=let / 14=loop: expand binding values + body
  ;; 28=vector literal: expand elements
  ;; 12=if / 13=do / others: expand all children
  (if (= tag 28)
    (expand-children-from expr 1)
  (if (= tag 10)
    (let [n (count expr)
          new-expr (vector)]
      (do (push new-expr (get expr 0))
          (push new-expr (get expr 1))
          (push new-expr (get expr 2))
          (loop [i 3]
            (if (>= i n) new-expr
              (do (push new-expr (expand-expr (get expr i)))
                  (recur (+ i 1)))))))
    (if (if (= tag 11) true (= tag 14))
      (let [n (count expr)
            new-expr (vector)]
        (do (push new-expr (get expr 0))
            (push new-expr (expand-bindings (get expr 1)))
            (loop [i 2]
              (if (>= i n) new-expr
                (do (push new-expr (expand-expr (get expr i)))
                    (recur (+ i 1)))))))
      (expand-children-from expr 1)))))

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
            ;; Symbol head — macros or plain call
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
                      (expand-children-from expr 0))))))
            ;; Special form tags (>=10) or vector marker (28)
            (if (if (>= tag 10) true (= tag 28))
              (expand-special expr tag)
              (expand-children-from expr 0))))
        ;; Head is compound — data vector, expand elements
        (expand-children-from expr 0)))))

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

;; Flat cond (host style):
;;   (cond test1 expr1 test2 expr2 :else default)
;; => nested ifs.  Pairs are alternating args, not sublists.
(defn is-else-atom? [x]
  (if (not (is-atom? x)) false
    (if (str-eq? (ast-val x) "else") true false)))

(defn expand-cond [expr]
  (let [n (count expr)]
    (if (< n 2)
      (mk-nil)
      ;; Walk pairs from the end: indices (n-2, n-1), (n-4, n-3), ...
      (loop [i (- n 2) res (mk-nil)]
        (if (< i 1)
          res
          (let [test (get expr i)
                body (get expr (+ i 1))]
            (if (is-else-atom? test)
              (recur (- i 2) (expand-expr body))
              (recur (- i 2)
                (mk-if (expand-expr test) (expand-expr body) res)))))))))

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
