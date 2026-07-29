;; Bars Macro Expander — Stage 8 of self-hosting
;; Built-in + user defmacro expansion (syntax-quote templates + expand-time eval)
;; Built-ins: when, unless, cond, ->, ->>, traits, defconst
;; User macros: template `` ` `` / ~ / ~@, or full interpreter (list/cons/if/let/…)
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

;; ===========================================================================
;; User defmacro (Phase 17.2)
;; Registry entry: [name param-names-vec body-ast]
;; Body is usually [23 template] (syntax-quote). Expansion is template-only
;; (unquote / splice) — enough for typical macros like twice/unless/assert.
;; ===========================================================================

(defn is-reader-form? [x tag]
  (if (not (is-atom? x)) false
    (= (ast-tag x) tag)))

(defn is-defmacro-form? [expr]
  (if (is-atom? expr) false
    (let [h (get expr 0)]
      (if (not (is-atom? h)) false
        (if (= (ast-tag h) 21) true
          (if (= (ast-tag h) 1) (str-eq? (ast-val h) "defmacro") false))))))

(defn parse-macro-params [params-ast]
  (let [plain (unwrap-vec params-ast)
        n (count plain)
        out (vector)]
    (do (loop [i 0]
          (if (>= i n) 0
            (let [p (get plain i)]
              (if (if (is-atom? p) (= (ast-tag p) 1) false)
                (do (push out (ast-val p))
                    (recur (+ i 1)))
                (recur (+ i 1))))))
        out)))

(defn parse-defmacro-form [expr]
  ;; (defmacro name [params...] body) → [name params body] or 0
  (if (< (count expr) 4) 0
    (let [name-a (get expr 1)
          params-a (get expr 2)
          body (get expr 3)]
      (if (not (is-atom? name-a)) 0
        (let [name (ast-val name-a)
              params (parse-macro-params params-a)
              entry (vector)]
          (do (push entry name)
              (push entry params)
              (push entry body)
              entry))))))

(defn collect-macros [ast-list]
  (let [n (count ast-list)
        out (vector)]
    (do (loop [i 0]
          (if (>= i n) 0
            (let [expr (get ast-list i)]
              (if (is-defmacro-form? expr)
                (let [e (parse-defmacro-form expr)]
                  (if (= e 0)
                    (recur (+ i 1))
                    (do (push out e)
                        (recur (+ i 1)))))
                (recur (+ i 1))))))
        out)))

(defn macro-lookup [macs name]
  (let [n (count macs)]
    (loop [i 0]
      (if (>= i n) 0
        (let [e (get macs i)]
          (if (str-eq? (get e 0) name) e
            (recur (+ i 1))))))))

(defn env-lookup [env name]
  ;; env: vector of [name-str ast]
  (let [n (count env)]
    (loop [i 0]
      (if (>= i n) 0
        (let [p (get env i)]
          (if (str-eq? (get p 0) name) (get p 1)
            (recur (+ i 1))))))))

(defn env-bind [params args]
  (let [n (count params)
        env (vector)]
    (do (loop [i 0]
          (if (>= i n) 0
            (let [pair (vector)
                  arg (if (< i (count args)) (get args i) (mk-nil))]
              (do (push pair (get params i))
                  (push pair arg)
                  (push env pair)
                  (recur (+ i 1))))))
        env)))

(defn env-extend [env name val]
  (let [pair (vector)]
    (do (push pair name)
        (push pair val)
        (push env pair)
        env)))

;; ===========================================================================
;; Macro interpreter (Phase 17.2 leftover → 17.12)
;; Evaluate non-template defmacro bodies at expand-time (list/cons/if/let/…).
;; Values are AST nodes (homoiconic). Special-form heads are re-tagged so HIR
;; sees tag 12/13/… rather than a bare symbol call.
;; ===========================================================================

(defn promote-special-head [head]
  (if (if (is-atom? head) (= (ast-tag head) 1) false)
    (let [name (ast-val head)]
      (if (str-eq? name "if") (mk-special 12 "if")
        (if (str-eq? name "do") (mk-special 13 "do")
          (if (str-eq? name "let") (mk-special 11 "let")
            (if (str-eq? name "loop") (mk-special 14 "loop")
              (if (str-eq? name "quote") (mk-special 22 "quote")
                (if (str-eq? name "fn") (mk-special 16 "fn")
                  head)))))))
    head))

(defn macro-truthy? [v]
  (if (is-atom? v)
    (let [tag (ast-tag v)]
      (if (= tag 4) false
        (if (= tag 5) (!= (ast-val v) 0)
          true)))
    true))

(defn macro-num? [v]
  (if (is-atom? v) (= (ast-tag v) 0) false))

(defn macro-as-num [v]
  (if (macro-num? v) (ast-val v) 0))

(defn is-vec-marker? [x]
  (if (is-atom? x) false
    (let [head (get x 0)]
      (if (is-atom? head)
        (= (ast-tag head) 28)
        false))))

(defn list-elems [v]
  ;; Strip vector marker if present; otherwise compound is already a list.
  (if (is-atom? v) (vector)
    (if (is-vec-marker? v)
      (let [n (count v) out (vector)]
        (do (loop [i 1]
              (if (>= i n) 0
                (do (push out (get v i)) (recur (+ i 1)))))
            out))
      v)))

(defn mk-list-from [elems]
  (let [out (vector)
        n (count elems)]
    (do (loop [i 0]
          (if (>= i n) out
            (do (if (= i 0)
                  (push out (promote-special-head (get elems i)))
                  (push out (get elems i)))
                (recur (+ i 1))))))))

;; Forward: macro-eval defined below; expand-synquote uses it for ~expr.

(defn macro-eval-args [args env]
  (let [n (count args)
        out (vector)]
    (do (loop [i 0]
          (if (>= i n) out
            (do (push out (macro-eval (get args i) env))
                (recur (+ i 1))))))))

(defn macro-builtin-list [args env]
  (mk-list-from (macro-eval-args args env)))

(defn macro-builtin-cons [args env]
  (if (< (count args) 2) (mk-nil)
    (let [h (macro-eval (get args 0) env)
          t (macro-eval (get args 1) env)
          elems (list-elems t)
          out (vector)]
      (do (push out (promote-special-head h))
          (loop [i 0]
            (if (>= i (count elems)) out
              (do (push out (get elems i))
                  (recur (+ i 1)))))))))

(defn macro-builtin-first [args env]
  (if (< (count args) 1) (mk-nil)
    (let [v (macro-eval (get args 0) env)
          elems (list-elems v)]
      (if (= (count elems) 0) (mk-nil) (get elems 0)))))

(defn macro-builtin-rest [args env]
  (if (< (count args) 1) (mk-list-from (vector))
    (let [v (macro-eval (get args 0) env)
          elems (list-elems v)
          out (vector)
          n (count elems)]
      (do (loop [i 1]
            (if (>= i n) (mk-list-from out)
              (do (push out (get elems i))
                  (recur (+ i 1)))))))))

(defn macro-builtin-nth [args env idx]
  (if (< (count args) 1) (mk-nil)
    (let [v (macro-eval (get args 0) env)
          elems (list-elems v)]
      (if (>= idx (count elems)) (mk-nil) (get elems idx)))))

(defn macro-builtin-count [args env]
  (if (< (count args) 1) (mk-num 0)
    (let [v (macro-eval (get args 0) env)]
      (if (is-atom? v)
        (if (= (ast-tag v) 2) (mk-num (count (ast-val v))) (mk-num 0))
        (mk-num (count (list-elems v)))))))

(defn macro-builtin-eq [args env]
  (if (< (count args) 2) (mk-bool 0)
    (let [a (macro-eval (get args 0) env)
          b (macro-eval (get args 1) env)]
      (if (if (macro-num? a) (macro-num? b) false)
        (mk-bool (if (= (ast-val a) (ast-val b)) 1 0))
        (if (if (is-atom? a) (is-atom? b) false)
          (if (if (= (ast-tag a) (ast-tag b)) true false)
            (if (= (ast-tag a) 1)
              (mk-bool (if (str-eq? (ast-val a) (ast-val b)) 1 0))
              (if (= (ast-tag a) 2)
                (mk-bool (if (str-eq? (ast-val a) (ast-val b)) 1 0))
                (mk-bool (if (= (ast-val a) (ast-val b)) 1 0))))
            (mk-bool 0))
          (mk-bool 0))))))

(defn macro-builtin-arith [op args env]
  (let [n (count args)]
    (if (= n 0) (mk-num (if (str-eq? op "*") 1 0))
      (let [first (macro-as-num (macro-eval (get args 0) env))]
        (if (= n 1)
          (if (str-eq? op "-") (mk-num (- 0 first)) (mk-num first))
          (loop [i 1 acc first]
            (if (>= i n) (mk-num acc)
              (let [x (macro-as-num (macro-eval (get args i) env))]
                (if (str-eq? op "+") (recur (+ i 1) (+ acc x))
                  (if (str-eq? op "-") (recur (+ i 1) (- acc x))
                    (if (str-eq? op "*") (recur (+ i 1) (* acc x))
                      (recur (+ i 1) acc))))))))))))

(defn macro-builtin-not [args env]
  (if (< (count args) 1) (mk-bool 1)
    (mk-bool (if (macro-truthy? (macro-eval (get args 0) env)) 0 1))))

(defn macro-builtin-pred [kind args env]
  (if (< (count args) 1) (mk-bool 0)
    (let [v (macro-eval (get args 0) env)]
      (if (str-eq? kind "symbol?")
        (mk-bool (if (if (is-atom? v) (= (ast-tag v) 1) false) 1 0))
        (if (str-eq? kind "list?")
          (mk-bool (if (if (not (is-atom? v)) (not (is-vec-marker? v)) false) 1 0))
          (if (str-eq? kind "vector?")
            (mk-bool (if (is-vec-marker? v) 1 0))
            (mk-bool 0)))))))

(defn macro-eval-let [expr env]
  ;; (let [n1 v1 n2 v2 ...] body...) — bindings may be vec-marker or flat.
  (let [binds-raw (get expr 1)
        plain (if (is-vec-marker? binds-raw)
                (let [n (count binds-raw) out (vector)]
                  (do (loop [i 1]
                        (if (>= i n) 0
                          (do (push out (get binds-raw i)) (recur (+ i 1)))))
                      out))
                binds-raw)
        nb (count plain)
        env2 (loop [i 0 e env]
               (if (>= i nb) e
                 (let [name-a (get plain i)
                       val-a (if (< (+ i 1) nb) (get plain (+ i 1)) (mk-nil))
                       nm (if (if (is-atom? name-a) (= (ast-tag name-a) 1) false)
                            (ast-val name-a) "")
                       vv (macro-eval val-a e)]
                   (recur (+ i 2) (env-extend e nm vv)))))
        n (count expr)]
    (if (<= n 2) (mk-nil)
      (loop [i 2 last (mk-nil)]
        (if (>= i n) last
          (recur (+ i 1) (macro-eval (get expr i) env2)))))))

(defn macro-eval-if [expr env]
  (let [c (macro-eval (get expr 1) env)]
    (if (macro-truthy? c)
      (macro-eval (get expr 2) env)
      (if (>= (count expr) 4)
        (macro-eval (get expr 3) env)
        (mk-nil)))))

(defn macro-eval-do [expr env]
  (let [n (count expr)]
    (loop [i 1 last (mk-nil)]
      (if (>= i n) last
        (recur (+ i 1) (macro-eval (get expr i) env))))))

(defn collect-from [expr start]
  (let [n (count expr)
        out (vector)]
    (do (loop [i start]
          (if (>= i n) 0
            (do (push out (get expr i))
                (recur (+ i 1)))))
        out)))

(defn macro-rebuild-call [head args env]
  (let [ev (macro-eval-args args env)
        all (vector)
        n (count ev)]
    (do (push all head)
        (loop [i 0]
          (if (>= i n) (mk-list-from all)
            (do (push all (get ev i))
                (recur (+ i 1))))))))

(defn macro-eval-symbol-call [name expr args env]
  (if (str-eq? name "list") (macro-builtin-list args env)
    (if (str-eq? name "cons") (macro-builtin-cons args env)
      (if (str-eq? name "first") (macro-builtin-first args env)
        (if (str-eq? name "rest") (macro-builtin-rest args env)
          (if (str-eq? name "second") (macro-builtin-nth args env 1)
            (if (str-eq? name "third") (macro-builtin-nth args env 2)
          (if (str-eq? name "count") (macro-builtin-count args env)
            (if (str-eq? name "=") (macro-builtin-eq args env)
              (if (str-eq? name "+") (macro-builtin-arith "+" args env)
                (if (str-eq? name "-") (macro-builtin-arith "-" args env)
                  (if (str-eq? name "*") (macro-builtin-arith "*" args env)
                    (if (str-eq? name "not") (macro-builtin-not args env)
                      (if (str-eq? name "symbol?") (macro-builtin-pred "symbol?" args env)
                        (if (str-eq? name "list?") (macro-builtin-pred "list?" args env)
                          (if (str-eq? name "vector?") (macro-builtin-pred "vector?" args env)
                            (if (str-eq? name "if") (macro-eval-if expr env)
                              (if (str-eq? name "do") (macro-eval-do expr env)
                                (if (str-eq? name "let") (macro-eval-let expr env)
                                  (if (str-eq? name "quote")
                                    (if (>= (count expr) 2) (get expr 1) (mk-nil))
                                    (macro-rebuild-call (get expr 0) args env)))))))))))))))))))))

(defn macro-eval-call [expr env]
  (let [head (get expr 0)
        n (count expr)
        args (collect-from expr 1)]
    (if (not (is-atom? head))
      ;; Data list — evaluate every element
      (let [all (collect-from expr 0)]
        (mk-list-from (macro-eval-args all env)))
      (let [tag (ast-tag head)
            name (ast-val head)]
        (if (= tag 12) (macro-eval-if expr env)
          (if (= tag 13) (macro-eval-do expr env)
            (if (= tag 11) (macro-eval-let expr env)
              (if (= tag 22)
                (if (>= n 2) (get expr 1) (mk-nil))
                (if (= tag 1)
                  (macro-eval-symbol-call name expr args env)
                  expr)))))))))

(defn macro-eval [expr env]
  (if (is-atom? expr)
    (let [tag (ast-tag expr)]
      (if (= tag 1)
        (let [found (env-lookup env (ast-val expr))]
          (if (= found 0) expr found))
        (if (= tag 22)
          ;; bare quote atom shouldn't happen; return as-is
          expr
          (if (= tag 23)
            (expand-synquote (ast-val expr) env)
            (if (= tag 24)
              (macro-eval (ast-val expr) env)
              expr)))))
    (if (is-vec-marker? expr)
      (let [n (count expr)
            out (vector)]
        (do (push out (get expr 0))
            (loop [i 1]
              (if (>= i n) out
                (do (push out (macro-eval (get expr i) env))
                    (recur (+ i 1)))))))
      (macro-eval-call expr env))))

;; Expand syntax-quote template with unquote/splice under env.
(defn expand-synquote [expr env]
  (if (is-atom? expr)
    (let [tag (ast-tag expr)]
      (if (= tag 24)
        ;; ~x — eval (symbol lookup or full macro-eval)
        (macro-eval (ast-val expr) env)
        (if (= tag 25)
          ;; bare splice outside list — treat as unquote
          (macro-eval (ast-val expr) env)
          (if (= tag 23)
            (expand-synquote (ast-val expr) env)
            expr))))
    ;; compound / vector form
    (let [n (count expr)
          out (vector)]
      (do (loop [i 0]
            (if (>= i n) out
              (let [child (get expr i)]
                (if (is-reader-form? child 25)
                  ;; splice elements of looked-up list/vector into out
                  (let [val (macro-eval (ast-val child) env)]
                    (if (is-atom? val)
                      (do (push out val)
                          (recur (+ i 1)))
                      (let [elems (list-elems val)
                            vn (count elems)]
                        (do (loop [j 0]
                              (if (>= j vn) 0
                                (do (push out (get elems j))
                                    (recur (+ j 1)))))
                            (recur (+ i 1))))))
                  (do (push out (expand-synquote child env))
                      (recur (+ i 1)))))))
          out))))

(defn apply-user-macro [entry args]
  (let [params (get entry 1)
        body (get entry 2)
        env (env-bind params args)]
    (if (is-reader-form? body 23)
      (expand-synquote (ast-val body) env)
      ;; Full expand-time evaluation (list/cons/if/let/…)
      (macro-eval body env))))

(defn expand-call-args [expr macs]
  ;; expand args of (f a b c) → vector of expanded args (skip head)
  (let [n (count expr)
        out (vector)]
    (do (loop [i 1]
          (if (>= i n) out
            (do (push out (expand-expr (get expr i) macs))
                (recur (+ i 1))))))))

;; ---- expand helpers for special forms ----
;; Vector marker tag 28: [[28] e0 e1 ...] from reader
;; (is-vec-marker? defined above with macro interpreter)

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
(defn expand-bindings [binds macs]
  (let [plain (unwrap-vec binds)
        n (count plain)
        new-b (vector)]
    (loop [i 0]
      (if (>= i n) (wrap-vec new-b)
        (do (push new-b (get plain i))
            (if (< (+ i 1) n)
              (push new-b (expand-expr (get plain (+ i 1)) macs))
              0)
            (recur (+ i 2)))))))

(defn expand-children-from [expr start macs]
  (let [n (count expr)
        new-expr (vector)]
    (do (push new-expr (get expr 0))
        (loop [i 1]
          (if (>= i n) new-expr
            (if (< i start)
              (do (push new-expr (get expr i))
                  (recur (+ i 1)))
              (do (push new-expr (expand-expr (get expr i) macs))
                  (recur (+ i 1)))))))))

(defn expand-special [expr tag macs]
  ;; 10=defn: keep name+params (unwrap params), expand body
  ;; 11=let / 14=loop: expand binding values + body
  ;; 28=vector literal: expand elements
  ;; 12=if / 13=do / others: expand all children
  (if (= tag 28)
    (expand-children-from expr 1 macs)
  (if (= tag 10)
    (let [n (count expr)
          new-expr (vector)]
      (do (push new-expr (get expr 0))
          (push new-expr (get expr 1))
          (push new-expr (get expr 2))
          (loop [i 3]
            (if (>= i n) new-expr
              (do (push new-expr (expand-expr (get expr i) macs))
                  (recur (+ i 1)))))))
    (if (if (= tag 11) true (= tag 14))
      (let [n (count expr)
            new-expr (vector)]
        (do (push new-expr (get expr 0))
            (push new-expr (expand-bindings (get expr 1) macs))
            (loop [i 2]
              (if (>= i n) new-expr
                (do (push new-expr (expand-expr (get expr i) macs))
                    (recur (+ i 1)))))))
      (expand-children-from expr 1 macs)))))

;; ---- expand an expression ----

(defn expand-symbol-call [expr name macs]
  ;; Built-in macros, then user defmacro, else plain call.
  (if (str-eq? name "when")
    (expand-when expr macs)
    (if (str-eq? name "unless")
      (expand-unless expr macs)
      (if (str-eq? name "when-not")
        (expand-unless expr macs)
        (if (str-eq? name "if-let")
          (expand-if-let expr macs)
          (if (str-eq? name "when-let")
            (expand-when-let expr macs)
            (if (str-eq? name "partial")
              (expand-partial expr macs)
              (if (str-eq? name "doseq")
                (expand-doseq expr macs)
                (if (str-eq? name "for")
                  (expand-for expr macs)
                  (if (str-eq? name "dotimes")
                    (expand-dotimes expr macs)
                    (if (str-eq? name "while")
                      (expand-while expr macs)
                      (if (str-eq? name "case")
                        (expand-case expr macs)
                        (if (str-eq? name "cond")
                          (expand-cond expr macs)
                          (if (str-eq? name "and")
                            (expand-and expr macs)
                            (if (str-eq? name "or")
                              (expand-or expr macs)
                              (if (str-eq? name "->")
                                (expand-thread expr macs)
                                (if (str-eq? name "->>")
                                  (expand-thread-last expr macs)
                                  (if (str-eq? name "deftrait")
                                    (expand-deftrait expr)
                                    (if (str-eq? name "impl")
                                      (expand-impl expr (vector) macs)
                                      (if (str-eq? name "defconst")
                                        (expand-defconst expr macs)
                                        (if (str-eq? name "trait-call")
                                          (expand-trait-call expr macs)
                                          (if (str-eq? name "tcall")
                                            (expand-trait-call expr macs)
                                            (let [entry (macro-lookup macs name)]
                                              (if (= entry 0)
                                                (expand-children-from expr 0 macs)
                                                (let [args (expand-call-args expr macs)
                                                      expanded (apply-user-macro entry args)]
                                                  (expand-expr expanded macs))))))))))))))))))))))))))

(defn expand-expr [expr macs]
  (if (is-atom? expr)
    expr
    (let [head (get expr 0)]
      (if (is-atom? head)
        (let [tag (ast-tag head)
              name (ast-val head)]
          (if (= tag 1)
            (expand-symbol-call expr name macs)
            (if (if (>= tag 10) true (= tag 28))
              (expand-special expr tag macs)
              (expand-children-from expr 0 macs))))
        (expand-children-from expr 0 macs)))))

;; ---- built-in macro expansions ----

;; (when cond body...) => (if cond (do body...) nil)
(defn expand-when [expr macs]
  (let [n (count expr)]
    (if (< n 2)
      (mk-nil)
      (let [cond (expand-expr (get expr 1) macs)]
        (if (<= n 2)
          (mk-if cond (mk-nil) (mk-nil))
          ;; Build do body from args[1..]
          (let [body-exprs (vector)]
            (do (loop [i 2]
                  (if (>= i n) 0
                    (do (push body-exprs (expand-expr (get expr i) macs))
                        (recur (+ i 1)))))
                (mk-if cond (mk-do body-exprs) (mk-nil)))))))))

;; (unless cond body...) => (if (not cond) (do body...) nil)
(defn expand-unless [expr macs]
  (let [n (count expr)]
    (if (< n 2)
      (mk-nil)
      (let [cond-expr (get expr 1)
            not-call (vector)]
        (do (push not-call (mk-sym "not"))
            (push not-call (expand-expr cond-expr macs))
            (let [cond not-call]
              (if (<= n 2)
                (mk-if cond (mk-nil) (mk-nil))
                (let [body-exprs (vector)]
                  (do (loop [i 2]
                        (if (>= i n) 0
                          (do (push body-exprs (expand-expr (get expr i) macs))
                              (recur (+ i 1)))))
                      (mk-if cond (mk-do body-exprs) (mk-nil)))))))))))

;; (if-let [x init] then else?) => (let [x init] (if x then else))
;; One binding only (Clojure-style). else defaults to nil.
(defn expand-if-let [expr macs]
  (let [n (count expr)]
    (if (< n 3)
      (mk-nil)
      (let [binds (unwrap-vec (get expr 1))
            then-e (expand-expr (get expr 2) macs)
            else-e (if (>= n 4) (expand-expr (get expr 3) macs) (mk-nil))]
        (if (< (count binds) 2)
          (mk-nil)
          (let [name (get binds 0)
                init (expand-expr (get binds 1) macs)
                nstr (if (is-atom? name) (ast-val name) "x")]
            (mk-let1 nstr init (mk-if (mk-sym nstr) then-e else-e))))))))

;; (when-let [x init] body...) => (let [x init] (when x body...))
(defn expand-when-let [expr macs]
  (let [n (count expr)]
    (if (< n 3)
      (mk-nil)
      (let [binds (unwrap-vec (get expr 1))
            body-exprs (vector)
            _ (loop [i 2]
                (if (>= i n) 0
                  (do (push body-exprs (expand-expr (get expr i) macs))
                      (recur (+ i 1)))))]
        (if (< (count binds) 2)
          (mk-nil)
          (let [name (get binds 0)
                init (expand-expr (get binds 1) macs)
                nstr (if (is-atom? name) (ast-val name) "x")
                body (if (= (count body-exprs) 1)
                       (get body-exprs 0)
                       (mk-do body-exprs))]
            (mk-let1 nstr init (mk-if (mk-sym nstr) body (mk-nil)))))))))

;; (partial f a b) => (fn [__px] (apply f a b [__px]))  — one more arg
;; (partial f) => f
(defn expand-partial [expr macs]
  (let [n (count expr)]
    (if (< n 2)
      (mk-nil)
      (if (= n 2)
        (expand-expr (get expr 1) macs)
        (let [x (mk-sym "__px")
              call (vector)
              _ (push call (mk-sym "apply"))
              _ (loop [i 1]
                  (if (>= i n) 0
                    (do (push call (expand-expr (get expr i) macs))
                        (recur (+ i 1)))))
              xvec (wrap-vec (vector x))
              _ (push call xvec)
              out (vector)]
          (do (push out (mk-special 16 "fn"))
              (push out (wrap-vec (vector x)))
              (push out call)
              out))))))

;; ---- AST builders for doseq/for ----

(defn mk-call [name args]
  (let [out (vector)
        n (count args)]
    (do (push out (mk-sym name))
        (loop [i 0]
          (if (>= i n) out
            (do (push out (get args i))
                (recur (+ i 1))))))))

(defn mk-letn [flat-binds body]
  ;; flat-binds: [name1 val1 name2 val2 ...] as AST nodes
  (let [out (vector)]
    (do (push out (mk-special 11 "let"))
        (push out (wrap-vec flat-binds))
        (push out body)
        out)))

(defn mk-loop1 [binds body]
  (let [out (vector)]
    (do (push out (mk-special 14 "loop"))
        (push out binds)
        (push out body)
        out)))

(defn mk-recur1 [args]
  (let [out (vector)
        n (count args)]
    (do (push out (mk-special 15 "recur"))
        (loop [i 0]
          (if (>= i n) out
            (do (push out (get args i))
                (recur (+ i 1))))))))

(defn expand-body-exprs [expr start macs]
  (let [n (count expr)
        body-exprs (vector)]
    (do (loop [j start]
          (if (>= j n) 0
            (do (push body-exprs (expand-expr (get expr j) macs))
                (recur (+ j 1)))))
        (if (= (count body-exprs) 0) (mk-nil)
          (if (= (count body-exprs) 1) (get body-exprs 0)
            (mk-do body-exprs))))))

;; Single-binding doseq core: x may be atom (name); coll + body already expanded ASTs.
(defn expand-doseq-1 [x coll body]
  (let [xname (if (is-atom? x) (ast-val x) "x")
        v (str-concat "__dv_" xname)
        i (str-concat "__di_" xname)
        cn (str-concat "__dn_" xname)
        getc (mk-call "get" (vector (mk-sym v) (mk-sym i)))
        rec (mk-recur1 (vector (mk-call "+" (vector (mk-sym i) (mk-num 1)))))
        step (mk-do (vector body rec))
        inner (mk-let1 xname getc step)
        test (mk-call ">=" (vector (mk-sym i) (mk-sym cn)))
        lbody (mk-if test (mk-nil) inner)
        lbinds (wrap-vec (vector (mk-sym i) (mk-num 0)))
        loopf (mk-loop1 lbinds lbody)
        cnt (mk-call "count" (vector (mk-sym v)))]
    (mk-letn (vector (mk-sym v) coll (mk-sym cn) cnt) loopf)))

;; Nest doseq pairs right-to-left: [x xs y ys] body => (doseq [x xs] (doseq [y ys] body))
(defn nest-doseq-binds [binds body]
  (let [nb (count binds)]
    (loop [i (- nb 2) b body]
      (if (< i 0) b
        (let [x (get binds i)
              coll (get binds (+ i 1))
              nested (expand-doseq-1 x coll b)]
          (recur (- i 2) nested))))))

;; (doseq [x coll] body...) / (doseq [x xs y ys] body...) => nested index loops; nil
(defn expand-doseq [expr macs]
  (let [n (count expr)]
    (if (< n 3)
      (mk-nil)
      (let [binds (unwrap-vec (get expr 1))
            nb (count binds)]
        (if (< nb 2)
          (mk-nil)
          (if (!= (% nb 2) 0)
            (mk-nil)
            (let [body (expand-body-exprs expr 2 macs)
                  exp-binds (vector)
                  _ (loop [i 0]
                      (if (>= i nb) 0
                        (do (push exp-binds (get binds i))
                            (push exp-binds (expand-expr (get binds (+ i 1)) macs))
                            (recur (+ i 2)))))]
              (nest-doseq-binds exp-binds body))))))))

;; Single-binding for: collect body results into a vector
(defn expand-for-1 [x coll body]
  (let [xname (if (is-atom? x) (ast-val x) "x")
        v (str-concat "__fv_" xname)
        i (str-concat "__fi_" xname)
        cn (str-concat "__fn_" xname)
        acc (str-concat "__fa_" xname)
        getc (mk-call "get" (vector (mk-sym v) (mk-sym i)))
        pushed (mk-call "push" (vector (mk-sym acc) body))
        rec (mk-recur1 (vector
              (mk-call "+" (vector (mk-sym i) (mk-num 1)))
              (mk-sym acc)))
        step (mk-let1 acc pushed rec)
        inner (mk-let1 xname getc step)
        test (mk-call ">=" (vector (mk-sym i) (mk-sym cn)))
        lbody (mk-if test (mk-sym acc) inner)
        lbinds (wrap-vec (vector
                  (mk-sym i) (mk-num 0)
                  (mk-sym acc) (mk-sym acc)))
        loopf (mk-loop1 lbinds lbody)
        cnt (mk-call "count" (vector (mk-sym v)))
        empty (mk-call "vector" (vector))]
    (mk-letn (vector (mk-sym v) coll
                     (mk-sym cn) cnt
                     (mk-sym acc) empty)
             loopf)))

;; (for [x coll] body) / (for [x xs y ys] body) — multi flattens via nested doseq + push
(defn expand-for [expr macs]
  (let [n (count expr)]
    (if (< n 3)
      (mk-call "vector" (vector))
      (let [binds (unwrap-vec (get expr 1))
            nb (count binds)]
        (if (< nb 2)
          (mk-call "vector" (vector))
          (if (!= (% nb 2) 0)
            (mk-call "vector" (vector))
            (let [body (expand-body-exprs expr 2 macs)
                  exp-binds (vector)
                  _ (loop [i 0]
                      (if (>= i nb) 0
                        (do (push exp-binds (get binds i))
                            (push exp-binds (expand-expr (get binds (+ i 1)) macs))
                            (recur (+ i 2)))))]
              (if (= nb 2)
                (expand-for-1 (get exp-binds 0) (get exp-binds 1) body)
                ;; Multi: (let [acc []] (doseq … (push acc body)) acc)
                (let [acc "__facc"
                      push-step (mk-call "push" (vector (mk-sym acc) body))
                      nested (nest-doseq-binds exp-binds push-step)]
                  (mk-let1 acc (mk-call "vector" (vector))
                    (mk-do (vector nested (mk-sym acc)))))))))))))

;; (dotimes [i n] body...) => (let [__dn n] (loop [i 0] (if (>= i __dn) nil (do body (recur (+ i 1))))))
(defn expand-dotimes [expr macs]
  (let [n (count expr)]
    (if (< n 3)
      (mk-nil)
      (let [binds (unwrap-vec (get expr 1))]
        (if (< (count binds) 2)
          (mk-nil)
          (let [ivar (get binds 0)
                nexp (expand-expr (get binds 1) macs)
                iname (if (is-atom? ivar) (ast-val ivar) "i")
                cn (str-concat "__dtn_" iname)
                body (expand-body-exprs expr 2 macs)
                rec (mk-recur1 (vector
                      (mk-call "+" (vector (mk-sym iname) (mk-num 1)))))
                step (mk-do (vector body rec))
                test (mk-call ">=" (vector (mk-sym iname) (mk-sym cn)))
                lbody (mk-if test (mk-nil) step)
                lbinds (wrap-vec (vector (mk-sym iname) (mk-num 0)))
                loopf (mk-loop1 lbinds lbody)]
            (mk-let1 cn nexp loopf)))))))

;; (while cond body...) => (loop [__w 0] (if cond (do body (recur 0)) nil))
(defn expand-while [expr macs]
  (let [n (count expr)]
    (if (< n 2)
      (mk-nil)
      (let [cnd (expand-expr (get expr 1) macs)
            body (if (<= n 2) (mk-nil) (expand-body-exprs expr 2 macs))
            rec (mk-recur1 (vector (mk-num 0)))
            step (mk-do (vector body rec))
            lbody (mk-if cnd step (mk-nil))
            lbinds (wrap-vec (vector (mk-sym "__w") (mk-num 0)))]
        (mk-loop1 lbinds lbody)))))

;; (case e c1 r1 c2 r2 default?)
;; => (let [__case e] (if (= __case c1) r1 (if (= __case c2) r2 default)))
;; Scrutinee evaluated once. Odd trailing form is the default (else nil).
(defn expand-case [expr macs]
  (let [n (count expr)]
    (if (< n 2)
      (mk-nil)
      (if (= n 2)
        (mk-nil)
        (if (= n 3)
          ;; (case e default) — only default
          (expand-expr (get expr 2) macs)
          (let [scrut (expand-expr (get expr 1) macs)
                m (- n 2)
                has-def (= (% m 2) 1)
                default (if has-def
                          (expand-expr (get expr (- n 1)) macs)
                          (mk-nil))
                pair-end (if has-def (- n 1) n)
                nested (loop [i (- pair-end 2) res default]
                         (if (< i 2)
                           res
                           (let [cst (expand-expr (get expr i) macs)
                                 body (expand-expr (get expr (+ i 1)) macs)
                                 test (mk-call "=" (vector (mk-sym "__case") cst))]
                             (recur (- i 2) (mk-if test body res)))))]
            (mk-let1 "__case" scrut nested)))))))

;; (and) => true; (and x) => x; (and a b c) => (if a (if b c false) false)
(defn expand-and [expr macs]
  (let [n (count expr)]
    (if (< n 2)
      (mk-bool 1)
      (if (= n 2)
        (expand-expr (get expr 1) macs)
        (loop [i (- n 2) res (expand-expr (get expr (- n 1)) macs)]
          (if (< i 1)
            res
            (recur (- i 1)
              (mk-if (expand-expr (get expr i) macs) res (mk-bool 0)))))))))

;; (let [name val] body) single binding — for or short-circuit without double-eval
(defn mk-let1 [name val body]
  (let [binds (vector)
        out (vector)]
    (do (push binds (mk-sym name))
        (push binds val)
        (push out (mk-special 11 "let"))
        (push out (wrap-vec binds))
        (push out body)
        out)))

;; (or) => false; (or x) => x; (or a b c) => (let [t a] (if t t (or b c…)))
(defn expand-or [expr macs]
  (let [n (count expr)]
    (if (< n 2)
      (mk-bool 0)
      (if (= n 2)
        (expand-expr (get expr 1) macs)
        (loop [i (- n 2) res (expand-expr (get expr (- n 1)) macs) k 0]
          (if (< i 1)
            res
            (let [arg (expand-expr (get expr i) macs)
                  tname (str-concat "__or" (str-from-i64 k))
                  tsym (mk-sym tname)]
              (recur (- i 1)
                (mk-let1 tname arg (mk-if tsym tsym res))
                (+ k 1)))))))))

;; Flat cond (host style):
;;   (cond test1 expr1 test2 expr2 :else default)
;; => nested ifs.  Pairs are alternating args, not sublists.
(defn is-else-atom? [x]
  (if (not (is-atom? x)) false
    (if (str-eq? (ast-val x) "else") true false)))

(defn expand-cond [expr macs]
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
              (recur (- i 2) (expand-expr body macs))
              (recur (- i 2)
                (mk-if (expand-expr test macs) (expand-expr body macs) res)))))))))

;; (-> x (f a) (g b))  =>  (g (f x a) b)
(defn expand-thread [expr macs]
  (let [n (count expr)]
    (if (< n 2)
      (mk-nil)
      (let [result (expand-expr (get expr 1) macs)]
        (loop [i 2 res result phase 0 j 1 new-expr (vector)]
          (if (>= i n)
            res
            (if (= phase 0)
              (let [form (get expr i)]
                (if (is-atom? form)
                  (let [v (vector)]
                    (do (push v form) (push v res)
                        (recur (+ i 1) v 0 1 (vector))))
                  (let [head (get form 0)
                        v (vector)]
                    (do (push v head)
                        (push v res)
                        (recur i res 1 1 v)))))
              (let [form (get expr i)]
                (if (>= j (count form))
                  (recur (+ i 1) new-expr 0 1 (vector))
                  (do (push new-expr (get form j))
                      (recur i res 1 (+ j 1) new-expr)))))))))))

;; (->> x (f a) (g b))  =>  (g b (f a x))
(defn expand-thread-last [expr macs]
  (let [n (count expr)]
    (if (< n 2)
      (mk-nil)
      (let [result (expand-expr (get expr 1) macs)]
        (loop [i 2 res result phase 0 j 1 new-expr (vector)]
          (if (>= i n)
            res
            (if (= phase 0)
              (let [form (get expr i)]
                (if (is-atom? form)
                  (let [v (vector)]
                    (do (push v form) (push v res)
                        (recur (+ i 1) v 0 1 (vector))))
                  (let [head (get form 0)
                        v (vector)]
                    (do (push v head)
                        (recur i res 1 1 v)))))
              (let [form (get expr i)]
                (if (>= j (count form))
                  (do (push new-expr res)
                      (recur (+ i 1) new-expr 0 1 (vector)))
                  (do (push new-expr (get form j))
                      (recur i res 1 (+ j 1) new-expr)))))))))))

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
(defn mangle-impl-defn [defn-form trait type-name macs]
  (if (not (is-defn-form? defn-form)) (expand-expr defn-form macs)
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
                  (do (push out (expand-expr (get defn-form i) macs))
                      (recur (+ i 1)))))))))))

;; Instantiate a default method for Type: subst Self, mangle, expand body.
(defn instantiate-default [default trait type-name macs]
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
            (do (push out (expand-expr (subst-self (get bodies i) type-name) macs))
                (recur (+ i 1))))))))

;; (impl Trait for Type method-defns...) + fill defaults from registry
(defn expand-impl [expr traits macs]
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
                            (push defs (mangle-impl-defn el trait type-name macs))
                            (recur (+ i 1)))
                        (do (push defs (expand-expr el macs))
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
                            (do (push defs (instantiate-default d trait type-name macs))
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
(defn expand-defconst [expr macs]
  (let [n (count expr)]
    (if (< n 3)
      (mk-num 0)
      (let [name-a (get expr 1)
            val (expand-expr (get expr 2) macs)
            name (if (is-atom? name-a) (ast-val name-a) "CONST")
            out (vector)]
        (do (push out (mk-special 10 "defn"))
            (push out (mk-sym name))
            (push out (empty-params-vec))
            (push out val)
            out)))))

;; (trait-call Trait method Type args...) / (tcall ...) → (Trait_method_Type args...)
(defn expand-trait-call [expr macs]
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
                (do (push out (expand-expr (get expr i) macs))
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
;; Multi-pass: collect deftrait + defmacro, skip defmacro forms, expand rest.
(defn expand-program [ast-list]
  (let [traits (collect-traits ast-list)
        macs (collect-macros ast-list)
        new-list (vector)
        n (count ast-list)]
    (loop [i 0]
      (if (>= i n)
        new-list
        (let [raw (get ast-list i)]
          (if (is-defmacro-form? raw)
            (recur (+ i 1))
            (let [head (form-head-name raw)
                  e (if (str-eq? head "impl")
                      (expand-impl raw traits macs)
                      (if (str-eq? head "deftrait")
                        (expand-deftrait raw)
                        (expand-expr raw macs)))]
              (do (push-expanded new-list e)
                  (recur (+ i 1))))))))))
