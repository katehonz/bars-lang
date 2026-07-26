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
                      (if (str-eq? name "deftrait")
                        (expand-deftrait expr)
                        (if (str-eq? name "impl")
                          (expand-impl expr (vector))
                          (if (str-eq? name "defconst")
                            (expand-defconst expr)
                            (if (str-eq? name "trait-call")
                              (expand-trait-call expr)
                              (if (str-eq? name "tcall")
                                (expand-trait-call expr)
                                (expand-children-from expr 0)))))))))))
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

;; ===========================================================================
;; Phase 14.4+ — traits & const
;;
;; (deftrait Show [show]
;;   (default display [x] (tcall Show show Self x)))
;;
;; (impl Show for Point
;;   (defn show [self] ...))     ; display filled from default; Self → Point
;;
;; (trait-call Show show Point arg...)  or  (tcall Show show Point arg...)
;; (defconst MAX 100) → (defn MAX [] 100)
;; ===========================================================================

;; Mangled method name: Trait_method_Type
(defn trait-method-name [trait method type-name]
  (str-concat trait
    (str-concat "_"
      (str-concat method (str-concat "_" type-name)))))

(defn is-vec-form? [x]
  (if (is-atom? x) false
    (let [head (get x 0)]
      (if (is-atom? head) (= (ast-tag head) 28) false))))

(defn form-head-name [expr]
  (if (is-atom? expr) ""
    (let [h (get expr 0)]
      (if (is-atom? h) (ast-val h) ""))))

;; Replace symbol Self with type-name everywhere in an AST.
(defn subst-self [expr type-name]
  (if (is-atom? expr)
    (if (if (= (ast-tag expr) 1) (str-eq? (ast-val expr) "Self") false)
      (mk-sym type-name)
      expr)
    (let [n (count expr)
          out (vector)]
      (do (loop [i 0]
            (if (>= i n) out
              (do (push out (subst-self (get expr i) type-name))
                  (recur (+ i 1)))))))))

;; ---- deftrait registry ----
;; Entry: [trait-name required-vec defaults-vec]
;; required-vec: vector of method name strings
;; defaults-vec: vector of [method-name params-ast body-exprs-vec]

(defn parse-required-methods [vec-form]
  (let [out (vector)]
    (if (not (is-vec-form? vec-form)) out
      (let [n (count vec-form)]
        (do (loop [i 1]
              (if (>= i n) 0
                (let [el (get vec-form i)]
                  (if (if (is-atom? el) (= (ast-tag el) 1) false)
                    (do (push out (ast-val el))
                        (recur (+ i 1)))
                    (recur (+ i 1))))))
            out)))))

(defn is-default-form? [expr]
  (if (is-atom? expr) false
    (str-eq? (form-head-name expr) "default")))

(defn parse-default-form [expr]
  ;; (default name [params] body...) → [name params bodies] or 0
  (let [n (count expr)]
    (if (< n 3) 0
      (let [name-a (get expr 1)
            params (get expr 2)]
        (if (not (is-atom? name-a)) 0
          (let [method (ast-val name-a)
                bodies (vector)
                entry (vector)]
            (do (loop [i 3]
                  (if (>= i n) 0
                    (do (push bodies (get expr i))
                        (recur (+ i 1)))))
                (push entry method)
                (push entry params)
                (push entry bodies)
                entry)))))))

;; Parse (deftrait Name [methods...] (default ...)...) → registry entry or 0
(defn parse-deftrait-form [expr]
  (let [n (count expr)]
    (if (< n 2) 0
      (let [name-a (get expr 1)]
        (if (not (is-atom? name-a)) 0
          (let [trait (ast-val name-a)
                required (vector)
                defaults (vector)
                start (if (if (>= n 3) (is-vec-form? (get expr 2)) false)
                        (do (let [r (parse-required-methods (get expr 2))]
                              (loop [j 0]
                                (if (>= j (count r)) 0
                                  (do (push required (get r j))
                                      (recur (+ j 1))))))
                            3)
                        2)
                entry (vector)]
            (do (loop [i start]
                  (if (>= i n) 0
                    (let [el (get expr i)]
                      (if (is-default-form? el)
                        (let [d (parse-default-form el)]
                          (if (= d 0)
                            (recur (+ i 1))
                            (do (push defaults d)
                                (recur (+ i 1)))))
                        (recur (+ i 1))))))
                (push entry trait)
                (push entry required)
                (push entry defaults)
                entry)))))))

(defn collect-traits [ast-list]
  (let [n (count ast-list)
        out (vector)]
    (do (loop [i 0]
          (if (>= i n) 0
            (let [expr (get ast-list i)]
              (if (str-eq? (form-head-name expr) "deftrait")
                (let [e (parse-deftrait-form expr)]
                  (if (= e 0)
                    (recur (+ i 1))
                    (do (push out e)
                        (recur (+ i 1)))))
                (recur (+ i 1))))))
        out)))

(defn trait-lookup [traits name]
  (let [n (count traits)]
    (loop [i 0]
      (if (>= i n) 0
        (let [e (get traits i)]
          (if (str-eq? (get e 0) name) e
            (recur (+ i 1))))))))

(defn name-in-vec? [names name]
  (let [n (count names)]
    (loop [i 0]
      (if (>= i n) false
        (if (str-eq? (get names i) name) true
          (recur (+ i 1)))))))

;; (deftrait ...) erased at runtime (registry used only during expand-program).
(defn expand-deftrait [expr]
  (mk-num 0))

(defn is-defn-form? [expr]
  (if (is-atom? expr) false
    (let [h (get expr 0)]
      (if (not (is-atom? h)) false
        (if (= (ast-tag h) 10) true
          (if (= (ast-tag h) 1) (str-eq? (ast-val h) "defn") false))))))

(defn defn-method-name [defn-form]
  (if (< (count defn-form) 2) ""
    (let [name-a (get defn-form 1)]
      (if (is-atom? name-a) (ast-val name-a) ""))))

;; Rewrite a defn's name to Trait_method_Type; leave body expanded.
(defn mangle-impl-defn [defn-form trait type-name]
  (if (not (is-defn-form? defn-form)) (expand-expr defn-form)
    (let [n (count defn-form)]
      (if (< n 3) defn-form
        (let [method (defn-method-name defn-form)
              mangled (trait-method-name trait method type-name)
              out (vector)]
          (do (push out (mk-special 10 "defn"))
              (push out (mk-sym mangled))
              (push out (get defn-form 2))
              (loop [i 3]
                (if (>= i n) out
                  (do (push out (expand-expr (get defn-form i)))
                      (recur (+ i 1)))))))))))

;; Instantiate a default method for Type: subst Self, mangle, expand body.
(defn instantiate-default [default trait type-name]
  (let [method (get default 0)
        params (get default 1)
        bodies (get default 2)
        mangled (trait-method-name trait method type-name)
        out (vector)
        nb (count bodies)]
    (do (push out (mk-special 10 "defn"))
        (push out (mk-sym mangled))
        (push out (subst-self params type-name))
        (loop [i 0]
          (if (>= i nb) out
            (do (push out (expand-expr (subst-self (get bodies i) type-name)))
                (recur (+ i 1))))))))

;; (impl Trait for Type method-defns...) + fill defaults from registry
(defn expand-impl [expr traits]
  (let [n (count expr)]
    (if (< n 5)
      (mk-num 0)
      (let [trait-a (get expr 1)
            for-a (get expr 2)
            type-a (get expr 3)
            trait (if (is-atom? trait-a) (ast-val trait-a) "Trait")
            type-name (if (is-atom? type-a) (ast-val type-a) "T")
            ok-for (if (is-atom? for-a) (str-eq? (ast-val for-a) "for") false)]
        (if (not ok-for)
          (mk-num 0)
          (let [defs (vector)
                provided (vector)
                entry (trait-lookup traits trait)]
            (do ;; user-provided methods
                (loop [i 4]
                  (if (>= i n) 0
                    (let [el (get expr i)]
                      (if (is-defn-form? el)
                        (do (push provided (defn-method-name el))
                            (push defs (mangle-impl-defn el trait type-name))
                            (recur (+ i 1)))
                        (do (push defs (expand-expr el))
                            (recur (+ i 1)))))))
                ;; fill defaults not provided
                (if (= entry 0) 0
                  (let [defaults (get entry 2)
                        nd (count defaults)]
                    (loop [j 0]
                      (if (>= j nd) 0
                        (let [d (get defaults j)
                              m (get d 0)]
                          (if (name-in-vec? provided m)
                            (recur (+ j 1))
                            (do (push defs (instantiate-default d trait type-name))
                                (recur (+ j 1)))))))))
                (if (= (count defs) 0)
                  (mk-num 0)
                  (if (= (count defs) 1)
                    (get defs 0)
                    (mk-do defs))))))))))

;; Build empty vector AST [[28]] for params []
(defn empty-params-vec []
  (let [marker (vector)
        v (vector)]
    (do (push marker 28)
        (push v marker)
        v)))

;; (defconst Name value) → (defn Name [] value)
(defn expand-defconst [expr]
  (let [n (count expr)]
    (if (< n 3)
      (mk-num 0)
      (let [name-a (get expr 1)
            val (expand-expr (get expr 2))
            name (if (is-atom? name-a) (ast-val name-a) "CONST")
            out (vector)]
        (do (push out (mk-special 10 "defn"))
            (push out (mk-sym name))
            (push out (empty-params-vec))
            (push out val)
            out)))))

;; (trait-call Trait method Type args...) / (tcall ...) → (Trait_method_Type args...)
(defn expand-trait-call [expr]
  (let [n (count expr)]
    (if (< n 4)
      (mk-num 0)
      (let [trait-a (get expr 1)
            method-a (get expr 2)
            type-a (get expr 3)
            trait (if (is-atom? trait-a) (ast-val trait-a) "T")
            method (if (is-atom? method-a) (ast-val method-a) "m")
            type-name (if (is-atom? type-a) (ast-val type-a) "X")
            fname (trait-method-name trait method type-name)
            out (vector)]
        (do (push out (mk-sym fname))
            (loop [i 4]
              (if (>= i n) out
                (do (push out (expand-expr (get expr i)))
                    (recur (+ i 1))))))))))

;; ---- top-level: expand a program (list of expressions) ----

(defn is-do-form? [expr]
  (if (is-atom? expr) false
    (let [h (get expr 0)]
      (if (is-atom? h) (= (ast-tag h) 13) false))))

(defn push-expanded [new-list e]
  (if (is-do-form? e)
    (do (loop [j 1]
          (if (>= j (count e)) 0
            (do (push new-list (get e j))
                (recur (+ j 1)))))
        new-list)
    (do (push new-list e) new-list)))

;; Two-pass: collect deftrait defaults, then expand (impl fills defaults).
(defn expand-program [ast-list]
  (let [traits (collect-traits ast-list)
        new-list (vector)
        n (count ast-list)]
    (loop [i 0]
      (if (>= i n)
        new-list
        (let [raw (get ast-list i)
              head (form-head-name raw)
              e (if (str-eq? head "impl")
                  (expand-impl raw traits)
                  (if (str-eq? head "deftrait")
                    (expand-deftrait raw)
                    (expand-expr raw)))]
          (do (push-expanded new-list e)
              (recur (+ i 1))))))))
