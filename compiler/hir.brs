;; Bars HIR Lowering — Stage 2 + loop/recur + deftype/match
;;
;; ADT runtime: variant = vector [discriminant, field0, field1, ...]
;; match: chain of tag checks; bindings via get
;;
;; loops: vector of frames [label vars-vector]
;; adt:   vector of entries [name disc nfields]

(defn str-eq? [a b]
  (if (!= (str-count a) (str-count b))
    false
    (= (str-starts-with? a b) 1)))

(defn int-str [n] (str-from-i64 n))

(defn fresh-temp [t] (str-concat "t" (int-str t)))
(defn fresh-label [l p] (str-concat p (int-str l)))
(defn put [lines s] (do (push lines s) lines))

(defn op-fmt [s]
  (let [c (str-get s 0)]
    (if (if (>= c 48) (<= c 57) false)
      (str-concat "const " s)
      (if (= c 45)
        (str-concat "const " s)
        (if (str-eq? s "true")
          "const 1"
          (if (str-eq? s "false")
            "const 0"
            (if (str-eq? s "nil")
              "const 0"
              (str-concat "var " s))))))))

(defn ret-op [r] (get r 0)) (defn ret-st [r] (get r 1))
(defn st-t [r] (get (ret-st r) 0)) (defn st-l [r] (get (ret-st r) 1))
(defn mk-ret [op t l] [op [t l]])

(defn is-atom? [x] (< (get x 0) 1000))
(defn tag-of [x] (get x 0))
(defn val-of [x] (get x 1))
(defn list-head [x] (get x 0))

;; Unwrap [[28] e0 e1 ...] vector marker → plain vector of elements
(defn unwrap-vec [v]
  (if (is-atom? v) v
    (let [head (list-head v)]
      (if (if (is-atom? head) (= (tag-of head) 28) false)
        (let [n (count v)
              out (vector)]
          (do (loop [i 1]
                (if (>= i n) 0
                  (do (push out (get v i))
                      (recur (+ i 1)))))
              out))
        v))))

(defn is-dead-op? [op]
  (if (str-eq? op "<dead>") true
    (if (str-eq? op "<done>") true false)))

;; ---- loop stack ----

(defn loops-push [loops label vars]
  (let [frame (vector)
        out (vector)
        n (count loops)]
    (do (push frame label)
        (push frame vars)
        (loop [i 0]
          (if (>= i n) 0
            (do (push out (get loops i))
                (recur (+ i 1)))))
        (push out frame)
        out)))

(defn loops-top [loops]
  (get loops (- (count loops) 1)))

;; ---- ADT registry: entry = [name disc nfields] ----

(defn adt-lookup [adt name]
  (let [n (count adt)]
    (loop [i 0]
      (if (>= i n) 0
        (let [e (get adt i)]
          (if (str-eq? (get e 0) name) e
            (recur (+ i 1))))))))

(defn adt-found? [entry]
  (> (count entry) 0))

(defn is-deftype-form? [expr]
  (if (is-atom? expr) false
    (let [head (list-head expr)]
      (if (is-atom? head)
        (= (tag-of head) 19)
        false))))

;; Register variants from (deftype Name [V0 f…] [V1] …)
;; Mutates adt vector, returns adt.
(defn register-deftype [adt expr]
  (let [n (count expr)]
    (loop [i 2 disc 0]
      (if (>= i n) adt
        (let [variant (unwrap-vec (get expr i))]
          (if (is-atom? variant)
            (recur (+ i 1) disc)
            (let [head (get variant 0)]
              (if (not (is-atom? head))
                (recur (+ i 1) disc)
                (let [vname (val-of head)
                      nfields (- (count variant) 1)
                      entry (vector)]
                  (do (push entry vname)
                      (push entry disc)
                      (push entry nfields)
                      (push adt entry)
                      (recur (+ i 1) (+ disc 1))))))))))))

(defn collect-adt [ast-list]
  (let [n (count ast-list)
        adt (vector)]
    (loop [i 0]
      (if (>= i n) adt
        (let [expr (get ast-list i)]
          (if (is-deftype-form? expr)
            (do (register-deftype adt expr)
                (recur (+ i 1)))
            (recur (+ i 1))))))))

;; Emit HIR for one constructor function
(defn emit-ctor [lines name disc nfields]
  (let [params (loop [i 0 acc ""]
                 (if (>= i nfields) acc
                   (let [p (str-concat "p" (int-str i))]
                     (if (= i 0)
                       (recur (+ i 1) p)
                       (recur (+ i 1) (str-concat acc (str-concat " " p)))))))
        plist (if (= nfields 0) "[]"
                (str-concat "[" (str-concat params "]")))]
    (do (put lines (str-concat "func " (str-concat name (str-concat " " (str-concat plist ":")))))
        (put lines "  entry_ctor:")
        (put lines "    call t0 vector")
        (put lines (str-concat "    call t1 push var t0 const " (int-str disc)))
        (loop [i 0]
          (if (>= i nfields) 0
            (do (put lines (str-concat "    call t"
                  (str-concat (int-str (+ i 2))
                    (str-concat " push var t0 var p" (int-str i)))))
                (recur (+ i 1)))))
        (put lines "    return var t0")
        lines)))

(defn emit-all-ctors [lines adt]
  (let [n (count adt)]
    (loop [i 0]
      (if (>= i n) lines
        (let [e (get adt i)]
          (do (emit-ctor lines (get e 0) (get e 1) (get e 2))
              (recur (+ i 1))))))))

;; ---- struct registry: entry = [name field0 field1 ...] ----

(defn is-defstruct-form? [expr]
  (if (is-atom? expr) false
    (let [head (list-head expr)]
      (if (is-atom? head)
        (= (tag-of head) 18)
        false))))

(defn collect-structs [ast-list]
  (let [n (count ast-list)
        structs (vector)]
    (loop [i 0]
      (if (>= i n) structs
        (let [expr (get ast-list i)]
          (if (is-defstruct-form? expr)
            (let [entry (vector)
                  fields (unwrap-vec (get expr 2))
                  nf (count fields)]
              (do (push entry (val-of (get expr 1)))
                  (loop [j 0]
                    (if (>= j nf) 0
                      (do (push entry (val-of (get fields j)))
                          (recur (+ j 1)))))
                  (push structs entry)
                  (recur (+ i 1))))
            (recur (+ i 1))))))))

(defn struct-lookup [structs name]
  (let [n (count structs)]
    (loop [i 0]
      (if (>= i n) 0
        (let [e (get structs i)]
          (if (str-eq? (get e 0) name) e
            (recur (+ i 1))))))))

(defn struct-field-offset [structs field-name]
  (let [n (count structs)]
    (loop [i 0]
      (if (>= i n) 0
        (let [e (get structs i)
              nf (count e)]
          (loop [j 1]
            (if (>= j nf)
              (recur (+ i 1))
              (if (str-eq? (get e j) field-name) (- j 1)
                (recur (+ j 1))))))))))

(defn emit-struct-ctor [lines name nfields]
  (let [params (loop [i 0 acc ""]
                 (if (>= i nfields) acc
                   (let [p (str-concat "p" (int-str i))]
                     (if (= i 0)
                       (recur (+ i 1) p)
                       (recur (+ i 1) (str-concat acc (str-concat " " p)))))))
        plist (if (= nfields 0) "[]"
                (str-concat "[" (str-concat params "]")))
        size (* nfields 8)]
    (do (put lines (str-concat "func " (str-concat name (str-concat " " (str-concat plist ":")))))
        (put lines "  entry_ctor:")
        (put lines (str-concat "    alloc t0 " (int-str size)))
        (loop [i 0]
          (if (>= i nfields) 0
            (do (put lines (str-concat "    fieldstore var t0 " (str-concat (int-str i)
                  (str-concat " var p" (int-str i)))))
                (recur (+ i 1)))))
        (put lines "    return var t0")
        lines)))

(defn emit-all-struct-ctors [lines structs]
  (let [n (count structs)]
    (loop [i 0]
      (if (>= i n) lines
        (let [e (get structs i)
              nfields (- (count e) 1)]
          (do (emit-struct-ctor lines (get e 0) nfields)
              (recur (+ i 1))))))))

;; ============================================================
;; lower-expr [ast t l lines loops adt structs]
;; ============================================================
(defn lower-atom [ast t l lines]
  (let [tag (tag-of ast)]
    (if (= tag 0)
      (mk-ret (int-str (val-of ast)) t l)
      (if (= tag 1)
        (mk-ret (val-of ast) t l)
        (if (= tag 2)
          (let [dest (fresh-temp t)]
            (do (put lines (str-concat "    stringlit " (str-concat dest (str-concat " " (val-of ast)))))
                (mk-ret dest (+ t 1) l)))
          (if (= tag 3)
            ;; Keywords → string ":name" (host-compatible)
            (let [dest (fresh-temp t)
                  content (str-concat ":" (val-of ast))]
              (do (put lines (str-concat "    stringlit " (str-concat dest (str-concat " " content))))
                  (mk-ret dest (+ t 1) l)))
            (if (= tag 4)
              (mk-ret "0" t l)
              (if (= tag 5)
                (mk-ret (int-str (val-of ast)) t l)
                (mk-ret "<unk>" t l)))))))))

;; Lower vector elements from index `start` → vector + push
(defn lower-vector-from [ast start t l lines loops adt structs]
  (let [n (count ast)
        dest (fresh-temp t)
        t1 (+ t 1)
        _ (put lines (str-concat "    call " (str-concat dest " vector")))]
    (loop [i start tcur t1 lcur l]
      (if (>= i n)
        (mk-ret dest tcur lcur)
        (let [res (lower-expr (get ast i) tcur lcur lines loops adt structs)
              op (ret-op res)
              t2 (st-t res)
              l2 (st-l res)
              tmp (fresh-temp t2)
              _ (put lines (str-concat "    call " (str-concat tmp
                    (str-concat " push var " (str-concat dest
                      (str-concat " " (op-fmt op)))))))]
          (recur (+ i 1) (+ t2 1) l2))))))

;; Lower set elements from index `start` → set + set-add
(defn lower-set-from [ast start t l lines loops adt structs]
  (let [n (count ast)
        dest (fresh-temp t)
        t1 (+ t 1)
        _ (put lines (str-concat "    call " (str-concat dest " set")))]
    (loop [i start tcur t1 lcur l]
      (if (>= i n)
        (mk-ret dest tcur lcur)
        (let [res (lower-expr (get ast i) tcur lcur lines loops adt structs)
              op (ret-op res)
              t2 (st-t res)
              l2 (st-l res)
              tmp (fresh-temp t2)
              _ (put lines (str-concat "    call " (str-concat tmp
                    (str-concat " set-add var " (str-concat dest
                      (str-concat " " (op-fmt op)))))))]
          (recur (+ i 1) (+ t2 1) l2))))))

(defn lower-form [ast t l lines loops adt structs]
  (let [head (list-head ast)
        tag (if (is-atom? head) (tag-of head) -1)]
    (if (= tag 10)
      (lower-defn ast t l lines loops adt structs)
      (if (= tag 11)
        (lower-let ast t l lines loops adt structs)
        (if (= tag 12)
          (lower-if ast t l lines loops adt structs)
          (if (= tag 13)
            (lower-do ast t l lines loops adt structs)
            (if (= tag 14)
              (lower-loop ast t l lines loops adt structs)
              (if (= tag 15)
                (lower-recur ast t l lines loops adt structs)
                (if (= tag 17)
                  (lower-match ast t l lines loops adt structs)
                  (if (= tag 28)
                    (lower-vector-from ast 1 t l lines loops adt structs)
                    (if (is-atom? head)
                      (lower-call ast t l lines loops adt structs)
                      ;; Bare data vector (no marker): all elements
                      (lower-vector-from ast 0 t l lines loops adt structs))))))))))))

(defn lower-expr [ast t l lines loops adt structs]
  (if (is-atom? ast)
    (lower-atom ast t l lines)
    (lower-form ast t l lines loops adt structs)))

;; Strip ^type meta atoms (tag 26) left as separate vector elems by reader.
;; [^i64 n] → [[26 i64] n] — keep only symbol params (tag 1).
(defn is-meta-atom? [x]
  (if (is-atom? x) (= (tag-of x) 26) false))

(defn normalize-params [params]
  (let [plain (unwrap-vec params)
        n (count plain)
        out (vector)]
    (do (loop [i 0]
          (if (>= i n) 0
            (let [p (get plain i)]
              (if (is-meta-atom? p)
                (recur (+ i 1))
                (do (if (if (is-atom? p) (= (tag-of p) 1) false)
                      (push out p)
                      0)
                    (recur (+ i 1)))))))
        out)))

(defn fmt-params [params]
  (let [n (count params)]
    (if (= n 0) "[]"
      (str-concat "[" (str-concat (join-syms params 0) "]")))))

(defn join-syms [params i]
  (let [n (count params)]
    (if (>= i n) ""
      (let [name (val-of (get params i))]
        (if (= i 0)
          (str-concat name (join-syms params (+ i 1)))
          (str-concat " " (str-concat name (join-syms params (+ i 1)))))))))

(defn lower-body-exprs [ast i n t l lines loops adt structs last-op]
  (if (>= i n) (mk-ret last-op t l)
    (let [res (lower-expr (get ast i) t l lines loops adt structs)
          op  (ret-op res)
          t2  (st-t res)
          l2  (st-l res)]
      (lower-body-exprs ast (+ i 1) n t2 l2 lines loops adt structs op))))

;; First body expr that is a string, with more body after it → docstring (skip).
(defn defn-body-start [ast]
  (let [n (count ast)]
    (if (< n 4) 3
      (let [b0 (get ast 3)]
        (if (if (is-atom? b0) (= (tag-of b0) 2) false)
          (if (> n 4) 4 3)
          3)))))

;; ============================================================
;; Automatic TCO: self-tail-recursive defn → loop/recur
;; (defn f [p…] body…) with any self-call becomes
;;   (defn f [p…] (loop [p p …] body'))
;; where tail-position (f a…) of matching arity becomes (recur a…).
;; Tail positions: defn body last expr; if branches; do last expr;
;; let body last expr; match arm bodies. Nested loop/fn are NOT
;; entered (inner scope). Non-tail or wrong-arity self-calls stay
;; ordinary calls. Bodies with no self-call are left untouched.
;; ============================================================

;; True if expr contains any call to `name` (scans whole subtree).
(defn tco-has-call? [expr name]
  (if (is-atom? expr) false
    (let [head (list-head expr)
          n (count expr)]
      (if (if (is-atom? head)
            (if (= (tag-of head) 1) (str-eq? (val-of head) name) false)
            false)
        true
        (loop [i 0]
          (if (>= i n) false
            (if (tco-has-call? (get expr i) name) true
              (recur (+ i 1)))))))))

;; True if expr is a call (name a…) with exactly `arity` args.
(defn tco-self-call? [expr name arity]
  (if (is-atom? expr) false
    (let [head (list-head expr)]
      (if (if (is-atom? head)
            (if (= (tag-of head) 1) (str-eq? (val-of head) name) false)
            false)
        (= (- (count expr) 1) arity)
        false))))

;; Copy a form, replacing the element at idx.
(defn tco-replace [expr idx newval]
  (let [n (count expr)
        out (vector)]
    (do (loop [i 0]
          (if (>= i n) 0
            (do (push out (if (= i idx) newval (get expr i)))
                (recur (+ i 1)))))
        out)))

;; (f a…) → (recur a…) keeping the arg ASTs.
(defn tco-call-to-recur [expr]
  (let [n (count expr)
        args (vector)]
    (do (loop [i 1]
          (if (>= i n) 0
            (do (push args (get expr i))
                (recur (+ i 1)))))
        (hir-recur args))))

;; Rewrite tail-position self-calls in match arm bodies (odd idx ≥ 3).
(defn tco-rewrite-match [expr name arity]
  (let [n (count expr)
        out (vector)]
    (do (loop [i 0]
          (if (>= i n) 0
            (do (push out
                  (if (if (>= i 3) (= (% i 2) 1) false)
                    (tco-rewrite-tail (get expr i) name arity)
                    (get expr i)))
                (recur (+ i 1)))))
        out)))

;; Rewrite tail-position self-calls in expr → recur. All else untouched.
(defn tco-rewrite-tail [expr name arity]
  (if (is-atom? expr) expr
    (if (tco-self-call? expr name arity)
      (tco-call-to-recur expr)
      (let [head (list-head expr)
            tag (if (is-atom? head) (tag-of head) -1)
            n (count expr)]
        (if (= tag 12)
          ;; (if c t e): both branches are tail
          (if (>= n 4)
            (tco-replace
              (tco-replace expr 2 (tco-rewrite-tail (get expr 2) name arity))
              3 (tco-rewrite-tail (get expr 3) name arity))
            expr)
          (if (= tag 13)
            ;; (do e…): last expr is tail
            (if (> n 1)
              (tco-replace expr (- n 1) (tco-rewrite-tail (get expr (- n 1)) name arity))
              expr)
            (if (= tag 11)
              ;; (let […] body…): last body expr is tail
              (if (> n 2)
                (tco-replace expr (- n 1) (tco-rewrite-tail (get expr (- n 1)) name arity))
                expr)
              (if (= tag 17)
                (tco-rewrite-match expr name arity)
                expr))))))))

;; True if any defn body expr (from start) contains a self-call.
(defn tco-body-has-call? [ast start name]
  (let [n (count ast)]
    (loop [i start]
      (if (>= i n) false
        (if (tco-has-call? (get ast i) name) true
          (recur (+ i 1)))))))

;; Wrap defn body exprs [start..n) in (loop [p p …] body') with rewrites.
(defn tco-wrap-body [ast start params name arity]
  (let [n (count ast)
        body (if (= (- n start) 1)
               (get ast start)
               (let [exprs (vector)]
                 (do (loop [i start]
                       (if (>= i n) 0
                         (do (push exprs (get ast i))
                             (recur (+ i 1)))))
                     (hir-do exprs))))
        bind-elems (vector)
        np (count params)]
    (do (loop [i 0]
          (if (>= i np) 0
            (do (push bind-elems (get params i))
                (push bind-elems (get params i))
                (recur (+ i 1)))))
        (hir-loop (hir-vec bind-elems)
                  (tco-rewrite-tail body name arity)))))

;; Entry: rewrite a self-recursive defn; otherwise return it unchanged.
(defn tco-defn [ast]
  (let [name   (val-of (get ast 1))
        params (normalize-params (get ast 2))
        start  (defn-body-start ast)
        n      (count ast)]
    (if (if (>= start n) true (not (tco-body-has-call? ast start name)))
      ast
      (let [out (vector)]
        (do (push out (get ast 0))
            (push out (get ast 1))
            (push out (get ast 2))
            (push out (tco-wrap-body ast start params name (count params)))
            out)))))

(defn lower-defn [ast t l lines loops adt structs]
  (let [ast    (tco-defn ast)
        name   (val-of (get ast 1))
        params (normalize-params (get ast 2))
        n      (count ast)
        start  (defn-body-start ast)
        entry  (fresh-label l "entry_")
        l2     (+ l 1)
        empty  (vector)
        _      (put lines (str-concat "func " (str-concat name (str-concat " " (str-concat (fmt-params params) ":")))))
        _      (put lines (str-concat "  " (str-concat entry ":")))
        res    (if (> (- n start) 1)
                 (lower-body-exprs ast start n t l2 lines empty adt structs "")
                 (lower-expr (get ast start) t l2 lines empty adt structs))
        op     (ret-op res)
        t3     (st-t res)
        l3     (st-l res)
        _      (if (is-dead-op? op) 0
                 (put lines (str-concat "    return " (op-fmt op))))]
    (mk-ret "<done>" t3 l3)))

;; ADT constructor call: vector + push disc + fields
(defn lower-ctor [disc args t l lines loops adt structs]
  (let [n (count args)
        dest (fresh-temp t)
        t1 (+ t 1)
        _ (put lines (str-concat "    call " (str-concat dest " vector")))
        tmp0 (fresh-temp t1)
        t2 (+ t1 1)
        _ (put lines (str-concat "    call " (str-concat tmp0
              (str-concat " push var " (str-concat dest
                (str-concat " const " (int-str disc)))))))]
    (loop [i 0 tcur t2 lcur l]
      (if (>= i n)
        (mk-ret dest tcur lcur)
        (let [res (lower-expr (get args i) tcur lcur lines loops adt structs)
              op (ret-op res)
              t3 (st-t res)
              l3 (st-l res)
              tmp (fresh-temp t3)
              _ (put lines (str-concat "    call " (str-concat tmp
                    (str-concat " push var " (str-concat dest
                      (str-concat " " (op-fmt op)))))))]
          (recur (+ i 1) (+ t3 1) l3))))))

;; (def name val) → assign (local mutable slot)
(defn lower-def [ast t l lines loops adt structs]
  (let [bname (val-of (get ast 1))
        res (lower-expr (get ast 2) t l lines loops adt structs)
        op (ret-op res)
        t2 (st-t res)
        l2 (st-l res)
        _ (put lines (str-concat "    assign " (str-concat bname (str-concat " " (op-fmt op)))))]
    (mk-ret op t2 l2)))

;; ---- HOF desugar: map / filter / reduce → loop (Phase 17.3) ----
;; Named functions and inline (fn […] …) via beta-reduction into let.
;; Avoids calling bars_map_new for (map f vec).

(defn hir-sym [name]
  (let [v (vector)]
    (do (push v 1) (push v name) v)))

(defn hir-num [n]
  (let [v (vector)]
    (do (push v 0) (push v n) v)))

(defn hir-special [tag name]
  (let [v (vector)]
    (do (push v tag) (push v name) v)))

(defn hir-vec-marker []
  (let [v (vector)]
    (do (push v 28) v)))

(defn hir-vec [elems]
  (let [out (vector)
        n (count elems)]
    (do (push out (hir-vec-marker))
        (loop [i 0]
          (if (>= i n) out
            (do (push out (get elems i))
                (recur (+ i 1))))))))

(defn hir-call [name args]
  (let [out (vector)
        n (count args)]
    (do (push out (hir-sym name))
        (loop [i 0]
          (if (>= i n) out
            (do (push out (get args i))
                (recur (+ i 1))))))))

(defn hir-if [c t e]
  (let [out (vector)]
    (do (push out (hir-special 12 "if"))
        (push out c)
        (push out t)
        (push out e)
        out)))

(defn hir-do [exprs]
  (let [out (vector)
        n (count exprs)]
    (do (push out (hir-special 13 "do"))
        (loop [i 0]
          (if (>= i n) out
            (do (push out (get exprs i))
                (recur (+ i 1))))))))

(defn hir-loop [binds body]
  (let [out (vector)]
    (do (push out (hir-special 14 "loop"))
        (push out binds)
        (push out body)
        out)))

(defn hir-recur [args]
  (let [out (vector)
        n (count args)]
    (do (push out (hir-special 15 "recur"))
        (loop [i 0]
          (if (>= i n) out
            (do (push out (get args i))
                (recur (+ i 1))))))))

(defn hir-let [binds body]
  (let [out (vector)]
    (do (push out (hir-special 11 "let"))
        (push out binds)
        (push out body)
        out)))

(defn is-fn-form? [expr]
  (if (is-atom? expr) false
    (let [h (get expr 0)]
      (if (not (is-atom? h)) false
        (if (= (tag-of h) 16) true
          (if (= (tag-of h) 1) (str-eq? (val-of h) "fn") false))))))

(defn fn-body-ast [expr]
  (let [n (count expr)]
    (if (<= n 2) (hir-num 0)
      (if (= n 3) (get expr 2)
        (let [bodies (vector)]
          (do (loop [i 2]
                (if (>= i n) 0
                  (do (push bodies (get expr i))
                      (recur (+ i 1)))))
              (hir-do bodies)))))))

;; Apply f (symbol or fn) to arg ASTs → call or (let [params args] body).
(defn apply-callable [f args]
  (if (if (is-atom? f) (= (tag-of f) 1) false)
    (hir-call (val-of f) args)
    (if (is-fn-form? f)
      (let [params (normalize-params (get f 1))
            np (count params)
            na (count args)
            bind-elems (vector)]
        (do (loop [i 0]
              (if (>= i np) 0
                (do (push bind-elems (get params i))
                    (push bind-elems (if (< i na) (get args i) (hir-num 0)))
                    (recur (+ i 1)))))
            (hir-let (hir-vec bind-elems) (fn-body-ast f))))
      ;; Fallback: treat compound head as error → call 0-arg nonsense
      (hir-num 0))))

(defn desugar-map [f vec-ast uid]
  (let [i (hir-sym (str-concat "__mi" (int-str uid)))
        result (hir-sym (str-concat "__mr" (int-str uid)))
        binds (hir-vec (vector i (hir-num 0) result (hir-call "vector" (vector))))
        cond (hir-call "=" (vector i (hir-call "count" (vector vec-ast))))
        elem (hir-call "get" (vector vec-ast i))
        mapped (apply-callable f (vector elem))
        push-c (hir-call "push" (vector result mapped))
        rec (hir-recur (vector (hir-call "+" (vector i (hir-num 1))) result))
        body (hir-if cond result (hir-do (vector push-c rec)))]
    (hir-loop binds body)))

(defn desugar-filter [pred vec-ast uid]
  (let [i (hir-sym (str-concat "__fi" (int-str uid)))
        result (hir-sym (str-concat "__fr" (int-str uid)))
        elem (hir-sym (str-concat "__fe" (int-str uid)))
        binds (hir-vec (vector i (hir-num 0) result (hir-call "vector" (vector))))
        cond (hir-call "=" (vector i (hir-call "count" (vector vec-ast))))
        get-e (hir-call "get" (vector vec-ast i))
        pred-c (apply-callable pred (vector elem))
        push-c (hir-call "push" (vector result elem))
        maybe (hir-if pred-c push-c (hir-num 0))
        bind-e (hir-let (hir-vec (vector elem get-e)) maybe)
        rec (hir-recur (vector (hir-call "+" (vector i (hir-num 1))) result))
        body (hir-if cond result (hir-do (vector bind-e rec)))]
    (hir-loop binds body)))

(defn desugar-reduce [f init-ast vec-ast uid]
  (let [i (hir-sym (str-concat "__ri" (int-str uid)))
        acc (hir-sym (str-concat "__ra" (int-str uid)))
        binds (hir-vec (vector i (hir-num 0) acc init-ast))
        cond (hir-call "=" (vector i (hir-call "count" (vector vec-ast))))
        elem (hir-call "get" (vector vec-ast i))
        next-acc (apply-callable f (vector acc elem))
        rec (hir-recur (vector (hir-call "+" (vector i (hir-num 1))) next-acc))
        body (hir-if cond acc rec)]
    (hir-loop binds body)))

;; ---- Keyword args pack (Phase 17.3c) ----
;; (kwargs :name "Ada" :n 3) → (vector "name" "Ada" "n" 3)
;; Explicit form so (map-set m :k v) is not rewritten.
;; Keys are bare keyword names (no leading ':') for (kw-get opts "name").

(defn hir-str [s]
  (let [v (vector)]
    (do (push v 2) (push v s) v)))

(defn is-kw-atom? [x]
  (if (is-atom? x) (= (tag-of x) 3) false))

(defn desugar-kwargs-form [ast]
  ;; (kwargs k1 v1 k2 v2 ...) — require even number of args after head
  (let [n (count ast)
        out (vector)]
    (if (< n 1) (hir-call "vector" (vector))
      (if (!= (% (- n 1) 2) 0)
        (hir-call "vector" (vector))
        (do (push out (hir-sym "vector"))
            (loop [i 1]
              (if (>= i n) out
                (let [el (get ast i)]
                  (do (if (is-kw-atom? el)
                        (push out (hir-str (val-of el)))
                        (push out el))
                      (recur (+ i 1)))))))))))

(defn lower-call [ast t l lines loops adt structs]
  (let [fname (val-of (get ast 0))
        n (count ast)
        entry (adt-lookup adt fname)]
    (if (str-eq? fname "def")
      (lower-def ast t l lines loops adt structs)
    (if (str-eq? fname "vector")
      ;; (vector a b c) → new + push each (not multi-arg runtime new)
      (lower-vector-from ast 1 t l lines loops adt structs)
    (if (str-eq? fname "set")
      ;; (set a b c) → new + set-add each
      (lower-set-from ast 1 t l lines loops adt structs)
    ;; (kwargs :k v ...) → flat vector of string keys + values
    (if (if (str-eq? fname "kwargs") true (str-eq? fname "kw-pack"))
      (lower-expr (desugar-kwargs-form ast) t l lines loops adt structs)
    ;; HOF: (map f vec) (filter pred vec) (reduce f init vec)
    (if (if (str-eq? fname "map") (= n 3) false)
      (lower-expr (desugar-map (get ast 1) (get ast 2) l) t l lines loops adt structs)
    (if (if (str-eq? fname "filter") (= n 3) false)
      (lower-expr (desugar-filter (get ast 1) (get ast 2) l) t l lines loops adt structs)
    (if (if (str-eq? fname "reduce") (= n 4) false)
      (lower-expr (desugar-reduce (get ast 1) (get ast 2) (get ast 3) l) t l lines loops adt structs)
    (if (adt-found? entry)
      ;; Collect arg exprs into vector for lower-ctor
      (let [args (vector)]
        (do (loop [i 1]
              (if (>= i n) 0
                (do (push args (get ast i))
                    (recur (+ i 1)))))
            (lower-ctor (get entry 1) args t l lines loops adt structs)))
    (if (str-starts-with? fname ".")
      ;; Field access: (.field expr) → fieldload
      (let [field-name (str-slice fname 1 (count fname))
            offset (struct-field-offset structs field-name)
            res (lower-expr (get ast 1) t l lines loops adt structs)
            op (ret-op res)
            t2 (st-t res)
            l2 (st-l res)
            dest (fresh-temp t2)
            t3 (+ t2 1)
            _ (put lines (str-concat "    fieldload " (str-concat dest
                  (str-concat " " (str-concat (op-fmt op)
                    (str-concat " " (int-str offset)))))))]
        (mk-ret dest t3 l2))
      ;; Normal call (includes struct constructors via emit-all-struct-ctors)
      (loop [i 1 args (vector) tcur t lcur l]
        (if (>= i n)
          (let [dest (fresh-temp tcur)
                tnext (+ tcur 1)
                astr (join-args args 0)
                _ (put lines (str-concat "    call " (str-concat dest (str-concat " " (str-concat fname (str-concat " " astr))))))]
            (mk-ret dest tnext lcur))
          (let [res (lower-expr (get ast i) tcur lcur lines loops adt structs)
                op  (ret-op res)
                t2  (st-t res)
                l2  (st-l res)
                _   (push args op)]
            (recur (+ i 1) args t2 l2)))))))))))))))

(defn join-args [args i]
  (let [n (count args)]
    (if (>= i n) ""
      (if (= i 0) (str-concat (op-fmt (get args i)) (join-args args (+ i 1)))
        (str-concat " " (str-concat (op-fmt (get args i)) (join-args args (+ i 1))))))))

;; ---- Let destructuring helpers ----

(defn is-pattern-vec? [pat]
  (if (is-atom? pat) false
    (let [head (get pat 0)]
      (if (is-atom? head)
        (= (tag-of head) 28)
        false))))

(defn lower-let-vec-pat [pat val-op t l lines loops adt structs]
  (let [n (count pat)]
    (loop [i 1 tcur t lcur l]
      (if (>= i n) [tcur lcur]
        (let [sub-pat (get pat i)
              gtmp (fresh-temp tcur)
              t2 (+ tcur 1)
              _ (put lines (str-concat "    call " (str-concat gtmp
                    (str-concat " get " (str-concat (op-fmt val-op)
                      (str-concat " const " (int-str (- i 1))))))))
              tl (lower-let-pattern sub-pat gtmp t2 lcur lines loops adt structs)]
          (recur (+ i 1) (get tl 0) (get tl 1)))))))

(defn lower-let-struct-pat [pat val-op t l lines loops adt structs]
  (let [cname (val-of (get pat 0))
        entry (struct-lookup structs cname)
        n (count pat)]
    (if (= entry 0)
      [t l]
      (loop [i 1 tcur t lcur l]
        (if (>= i n) [tcur lcur]
          (let [sub-pat (get pat i)
                offset (- i 1)
                gtmp (fresh-temp tcur)
                t2 (+ tcur 1)
                _ (put lines (str-concat "    fieldload " (str-concat gtmp
                      (str-concat " " (str-concat (op-fmt val-op)
                        (str-concat " " (int-str offset)))))))
                tl (lower-let-pattern sub-pat gtmp t2 lcur lines loops adt structs)]
            (recur (+ i 1) (get tl 0) (get tl 1))))))))

(defn lower-let-pattern [pat val-op t l lines loops adt structs]
  (if (is-atom? pat)
    (let [tag (tag-of pat)]
      (if (= tag 1)
        (let [name (val-of pat)]
          (if (str-eq? name "_")
            [t l]
            (do (put lines (str-concat "    assign " (str-concat name
                  (str-concat " " (op-fmt val-op)))))
                [t l])))
        [t l]))
    (if (is-pattern-vec? pat)
      (lower-let-vec-pat pat val-op t l lines loops adt structs)
      ;; Struct pattern: (StructName field1 field2 ...)
      (let [head (get pat 0)]
        (if (if (is-atom? head) (= (tag-of head) 1) false)
          (lower-let-struct-pat pat val-op t l lines loops adt structs)
          [t l])))))

(defn lower-let [ast t l lines loops adt structs]
  (let [binds (unwrap-vec (get ast 1))
        nbody (count ast)
        n (count binds)]
    (loop [i 0 tcur t lcur l]
      (if (>= i n)
        (if (<= nbody 3)
          (lower-expr (get ast 2) tcur lcur lines loops adt structs)
          (loop [j 2 last "" t2 tcur l2 lcur]
            (if (>= j nbody)
              (mk-ret last t2 l2)
              (let [res (lower-expr (get ast j) t2 l2 lines loops adt structs)
                    op (ret-op res)
                    t3 (st-t res)
                    l3 (st-l res)]
                (recur (+ j 1) op t3 l3)))))
        (let [bpat (get binds i)
              bval (get binds (+ i 1))
              res  (lower-expr bval tcur lcur lines loops adt structs)
              op   (ret-op res)
              t2   (st-t res)
              l2   (st-l res)
              tl   (lower-let-pattern bpat op t2 l2 lines loops adt structs)]
          (recur (+ i 2) (get tl 0) (get tl 1)))))))

(defn lower-if [ast t l lines loops adt structs]
  (let [c-ast (get ast 1) then-ast (get ast 2) else-ast (get ast 3)
        res0  (lower-expr c-ast t l lines loops adt structs)
        c-op  (ret-op res0)
        t1    (st-t res0)
        l1    (st-l res0)
        t-lbl (fresh-label l1 "then_")
        l2    (+ l1 1)
        e-lbl (fresh-label l2 "else_")
        l3    (+ l2 1)
        j-lbl (fresh-label l3 "join_")
        l4    (+ l3 1)
        result (fresh-temp t1)
        t2    (+ t1 1)
        _     (put lines (str-concat "    assign " (str-concat result " const 0")))
        _     (put lines (str-concat "    branch " (str-concat (op-fmt c-op) (str-concat " " (str-concat t-lbl (str-concat " " e-lbl))))))
        _     (put lines (str-concat "  " (str-concat t-lbl ":")))
        res1  (lower-expr then-ast t2 l4 lines loops adt structs)
        op1   (ret-op res1)
        t3    (st-t res1)
        l5    (st-l res1)
        _     (if (is-dead-op? op1) 0
                (do (put lines (str-concat "    assign " (str-concat result (str-concat " " (op-fmt op1)))))
                    (put lines (str-concat "    jump " j-lbl))))
        _     (put lines (str-concat "  " (str-concat e-lbl ":")))
        res2  (lower-expr else-ast t3 l5 lines loops adt structs)
        op2   (ret-op res2)
        t4b   (st-t res2)
        l6    (st-l res2)
        _     (if (is-dead-op? op2) 0
                (do (put lines (str-concat "    assign " (str-concat result (str-concat " " (op-fmt op2)))))
                    (put lines (str-concat "    jump " j-lbl))))]
    (if (if (is-dead-op? op1) (is-dead-op? op2) false)
      (mk-ret "<dead>" t4b l6)
      (do (put lines (str-concat "  " (str-concat j-lbl ":")))
          (mk-ret result t4b l6)))))

(defn lower-do [ast t l lines loops adt structs]
  (let [n (count ast)]
    (loop [i 1 last "" tcur t lcur l]
      (if (>= i n) (mk-ret last tcur lcur)
        (let [res (lower-expr (get ast i) tcur lcur lines loops adt structs)
              op  (ret-op res)
              t2  (st-t res)
              l2  (st-l res)]
          (recur (+ i 1) op t2 l2))))))

(defn collect-loop-vars [binds]
  (let [nb (count binds)
        vars (vector)]
    (loop [j 0]
      (if (>= j nb) vars
        (do (push vars (val-of (get binds j)))
            (recur (+ j 2)))))))

(defn lower-loop [ast t l lines loops adt structs]
  (let [binds (unwrap-vec (get ast 1))
        body (get ast 2)
        nb (count binds)
        loop-lbl (fresh-label l "loop_")
        l2 (+ l 1)]
    (loop [i 0 tcur t lcur l2]
      (if (>= i nb)
        (let [vars (collect-loop-vars binds)
              _ (put lines (str-concat "    jump " loop-lbl))
              _ (put lines (str-concat "  " (str-concat loop-lbl ":")))
              loops2 (loops-push loops loop-lbl vars)
              res (lower-expr body tcur lcur lines loops2 adt structs)
              op (ret-op res)
              t3 (st-t res)
              l3 (st-l res)]
          (if (is-dead-op? op)
            (mk-ret "<dead>" t3 l3)
            (mk-ret op t3 l3)))
        (let [bname (val-of (get binds i))
              bval (get binds (+ i 1))
              res (lower-expr bval tcur lcur lines loops adt structs)
              op (ret-op res)
              t2 (st-t res)
              l2b (st-l res)
              _ (put lines (str-concat "    assign " (str-concat bname (str-concat " " (op-fmt op)))))]
          (recur (+ i 2) t2 l2b))))))

(defn lower-recur [ast t l lines loops adt structs]
  (if (< (count loops) 1)
    (do (println "error: hir: recur used outside loop") (mk-ret "0" t l))
    (let [frame (loops-top loops)
          label (get frame 0)
          vars  (get frame 1)
          n     (count ast)]
      (loop [i 1 args (vector) tcur t lcur l]
        (if (>= i n)
          (do (loop [j 0]
                (if (>= j (count vars)) 0
                  (if (>= j (count args)) 0
                    (do (put lines (str-concat "    assign "
                          (str-concat (get vars j)
                            (str-concat " " (op-fmt (get args j))))))
                        (recur (+ j 1))))))
              (put lines (str-concat "    jump " label))
              (mk-ret "<dead>" tcur lcur))
          (let [res (lower-expr (get ast i) tcur lcur lines loops adt structs)
                op  (ret-op res)
                t2  (st-t res)
                l2  (st-l res)
                _   (push args op)]
            (recur (+ i 1) args t2 l2)))))))

;; ---- match ----
;; AST: [[17 match] scrutinee pat1 body1 pat2 body2 ...]
;; Pattern forms:
;;   [1 _]                    wildcard
;;   [1 name]                 binding (catch-all)
;;   [[1 Ctor]]               unit variant
;;   [[1 Ctor] [1 f0] ...]    variant with field bindings

;; Patterns: only symbol atoms (tag 1) are bindings/wildcards.
;; Number/string/bool atoms are constant patterns (equality).
(defn is-symbol-pat? [pat]
  (if (is-atom? pat) (= (tag-of pat) 1) false))

(defn is-wildcard-pat? [pat]
  (if (is-symbol-pat? pat)
    (str-eq? (val-of pat) "_")
    false))

(defn is-binding-pat? [pat]
  (if (is-symbol-pat? pat)
    (if (str-eq? (val-of pat) "_") false true)
    false))

(defn is-const-pat? [pat]
  (if (is-atom? pat)
    (if (= (tag-of pat) 1) false true)
    false))

(defn pattern-ctor-name [pat]
  (if (is-atom? pat) ""
    (let [head (get pat 0)]
      (if (is-atom? head)
        (val-of head)
        ""))))

(defn pattern-fields [pat]
  ;; returns vector of field binding names (strings) — only symbols
  (if (is-atom? pat) (vector)
    (let [n (count pat)
          fields (vector)]
      (do (loop [i 1]
            (if (>= i n) 0
              (let [f (get pat i)]
                (do (if (is-atom? f)
                      (if (= (tag-of f) 1)
                        (push fields (val-of f))
                        0)
                      0)
                    (recur (+ i 1))))))
          fields))))

;; Bind pattern fields; returns new temp counter
(defn bind-fields [fields val t lines]
  (let [n (count fields)]
    (loop [fi 0 tcur t]
      (if (>= fi n) tcur
        (let [fname (get fields fi)
              gtmp (fresh-temp tcur)
              t5 (+ tcur 1)
              _ (put lines (str-concat "    call " (str-concat gtmp
                    (str-concat " get " (str-concat (op-fmt val)
                      (str-concat " const " (int-str (+ fi 1))))))))
              _ (put lines (str-concat "    assign " (str-concat fname (str-concat " var " gtmp))))]
          (recur (+ fi 1) t5))))))

;; Lower body into result and jump join; returns [t l]
(defn match-arm-body [body result join t l lines loops adt structs]
  (let [resb (lower-expr body t l lines loops adt structs)
        opb (ret-op resb)
        tb (st-t resb)
        lb (st-l resb)]
    (do (if (is-dead-op? opb) 0
          (do (put lines (str-concat "    assign " (str-concat result (str-concat " " (op-fmt opb)))))
              (put lines (str-concat "    jump " join))))
        [tb lb])))

(defn struct-const-count [pat]
  (let [n (count pat)]
    (loop [i 1 acc 0]
      (if (>= i n) acc
        (let [sub (get pat i)]
          (if (is-atom? sub)
            (if (= (tag-of sub) 1)
              (recur (+ i 1) acc)
              (recur (+ i 1) (+ acc 1)))
            (recur (+ i 1) acc)))))))

(defn emit-struct-checks [pat val t l next-lbl lines entry]
  (let [n (count pat)
        arm-lbl (fresh-label l "sarm_")]
    (loop [i 1 tcur t lcur (+ l 1)]
      (if (>= i n)
        (do (put lines (str-concat "    jump " arm-lbl))
            [tcur arm-lbl])
        (let [sub-pat (get pat i)
              offset (- i 1)
              gtmp (fresh-temp tcur)
              t2 (+ tcur 1)
              _ (put lines (str-concat "    fieldload " (str-concat gtmp
                    (str-concat " " (str-concat (op-fmt val)
                      (str-concat " " (int-str offset)))))))]
          (if (is-const-pat? sub-pat)
            (let [cpat-res (lower-atom sub-pat t2 lcur lines)
                  cop (ret-op cpat-res)
                  t3 (st-t cpat-res)
                  eqtmp (fresh-temp t3)
                  t4 (+ t3 1)
                  skip-lbl (fresh-label lcur "sskip_")
                  l3 (+ lcur 1)
                  _ (put lines (str-concat "    call " (str-concat eqtmp
                        (str-concat " = var " (str-concat gtmp
                          (str-concat " " (op-fmt cop)))))))
                  _ (put lines (str-concat "    branch var " (str-concat eqtmp
                        (str-concat " " (str-concat skip-lbl
                          (str-concat " " next-lbl))))))
                  _ (put lines (str-concat "  " (str-concat skip-lbl ":")))]
              (recur (+ i 1) t4 l3))
            (if (is-binding-pat? sub-pat)
              (do (put lines (str-concat "    assign " (str-concat (val-of sub-pat) (str-concat " var " gtmp))))
                  (recur (+ i 1) t2 lcur))
              (recur (+ i 1) t2 lcur))))))))

(defn lower-struct-match-arm [pat body val result join t l lines loops adt structs]
  (let [cname (pattern-ctor-name pat)
        entry (struct-lookup structs cname)]
    (if (= entry 0) [t l 0]
      (if (= (struct-const-count pat) 0)
        ;; All-binding struct pattern: catch-all
        (let [t2 (match-struct-bind pat val t lines entry)
              tl (match-arm-body body result join t2 l lines loops adt structs)]
          [(get tl 0) (get tl 1) 1])
        ;; Struct pattern with constants: check each field
        (let [next-lbl (fresh-label l "snext_")
              l2 (+ l 1)
              r (emit-struct-checks pat val t l2 next-lbl lines entry)
              t2 (get r 0)
              arm-lbl (get r 1)]
          (do (put lines (str-concat "  " (str-concat arm-lbl ":")))
              (let [tl (match-arm-body body result join t2 l2 lines loops adt structs)]
                (do (put lines (str-concat "  " (str-concat next-lbl ":")))
                    [(get tl 0) (get tl 1) 0]))))))))

(defn match-struct-bind [pat val t lines entry]
  (let [n (count pat)
        nf (- (count entry) 1)]
    (loop [i 1 tcur t]
      (if (if (>= i n) true (>= (- i 1) nf)) tcur
        (let [sub-pat (get pat i)
              offset (- i 1)
              gtmp (fresh-temp tcur)
              t2 (+ tcur 1)
              _ (put lines (str-concat "    fieldload " (str-concat gtmp
                    (str-concat " " (str-concat (op-fmt val)
                      (str-concat " " (int-str offset)))))))
              t3 (if (is-binding-pat? sub-pat)
                   (do (put lines (str-concat "    assign " (str-concat (val-of sub-pat) (str-concat " var " gtmp))))
                       t2)
                   t2)]
          (recur (+ i 1) t3))))))

;; Process one match arm; returns [t l done]
;; done=1 means catch-all (stop processing more arms)
(defn lower-match-arm [pat body val result join t l lines loops adt structs]
  (if (is-wildcard-pat? pat)
    ;; Fall-through catch-all (no branch needed)
    (let [tl (match-arm-body body result join t l lines loops adt structs)]
      [(get tl 0) (get tl 1) 1])
  (if (is-binding-pat? pat)
    (do (put lines (str-concat "    assign " (str-concat (val-of pat) (str-concat " " (op-fmt val)))))
        (let [tl (match-arm-body body result join t l lines loops adt structs)]
          [(get tl 0) (get tl 1) 1]))
  (if (is-const-pat? pat)
    ;; Constant pattern: branch on equality with scrutinee
    (let [arm (fresh-label l "match_arm_")
          l3 (+ l 1)
          nxt (fresh-label l3 "match_next_")
          l4 (+ l3 1)
          cpat (lower-atom pat t l lines)
          cop (ret-op cpat)
          t1 (st-t cpat)
          eqtmp (fresh-temp t1)
          t2 (+ t1 1)
          _ (put lines (str-concat "    call " (str-concat eqtmp
                (str-concat " = " (str-concat (op-fmt val)
                  (str-concat " " (op-fmt cop)))))))
          _ (put lines (str-concat "    branch var " (str-concat eqtmp
                (str-concat " " (str-concat arm (str-concat " " nxt))))))
          _ (put lines (str-concat "  " (str-concat arm ":")))
          tl (match-arm-body body result join t2 l4 lines loops adt structs)
          _ (put lines (str-concat "  " (str-concat nxt ":")))]
      [(get tl 0) (get tl 1) 0])
    ;; Check if this is a struct pattern
    (let [cname (pattern-ctor-name pat)]
      (if (> (count cname) 0)
        (let [sentry (struct-lookup structs cname)]
          (if (!= sentry 0)
            (lower-struct-match-arm pat body val result join t l lines loops adt structs)
            ;; ADT variant: branch on discriminant
            (let [arm (fresh-label l "match_arm_")
                  l3 (+ l 1)
                  nxt (fresh-label l3 "match_next_")
                  l4 (+ l3 1)
                  entry (adt-lookup adt cname)
                  disc (if (adt-found? entry) (get entry 1) 0)
                  fields (pattern-fields pat)
                  tagtmp (fresh-temp t)
                  t3 (+ t 1)
                  eqtmp (fresh-temp t3)
                  t4 (+ t3 1)
                  _ (put lines (str-concat "    call " (str-concat tagtmp
                        (str-concat " get " (str-concat (op-fmt val) " const 0")))))
                  _ (put lines (str-concat "    call " (str-concat eqtmp
                        (str-concat " = var " (str-concat tagtmp
                          (str-concat " const " (int-str disc)))))))
                  _ (put lines (str-concat "    branch var " (str-concat eqtmp
                        (str-concat " " (str-concat arm (str-concat " " nxt))))))
                  _ (put lines (str-concat "  " (str-concat arm ":")))
                  t5 (bind-fields fields val t4 lines)
                  tl (match-arm-body body result join t5 l4 lines loops adt structs)
                  _ (put lines (str-concat "  " (str-concat nxt ":")))]
              [(get tl 0) (get tl 1) 0])))
        ;; No constructor name in pattern — fall through
        (let [tl (match-arm-body body result join t l lines loops adt structs)]
          [(get tl 0) (get tl 1) 1])))))))

;; Collect unique binding names from all match patterns (for pre-alloca)
(defn name-in-vec? [names name]
  (let [n (count names)]
    (loop [i 0]
      (if (>= i n) false
        (if (str-eq? (get names i) name) true
          (recur (+ i 1)))))))

(defn collect-match-binds [ast]
  (let [n (count ast)
        names (vector)]
    (loop [i 2]
      (if (>= i n) names
        (let [pat (get ast i)]
          (if (is-binding-pat? pat)
            (do (if (name-in-vec? names (val-of pat)) 0
                  (push names (val-of pat)))
                (recur (+ i 2)))
            (if (is-wildcard-pat? pat)
              (recur (+ i 2))
              (let [fields (pattern-fields pat)]
                (do (loop [fi 0]
                      (if (>= fi (count fields)) 0
                        (do (if (name-in-vec? names (get fields fi)) 0
                              (push names (get fields fi)))
                            (recur (+ fi 1)))))
                    (recur (+ i 2)))))))))))

(defn lower-match [ast t l lines loops adt structs]
  (let [scrut (get ast 1)
        n (count ast)
        res0 (lower-expr scrut t l lines loops adt structs)
        val (ret-op res0)
        t1 (st-t res0)
        l1 (st-l res0)
        result (fresh-temp t1)
        t2 (+ t1 1)
        join (fresh-label l1 "match_join_")
        l2 (+ l1 1)
        ;; Pre-allocate result + all pattern bindings before any branch
        ;; so LLVM allocas dominate all match arms
        _ (put lines (str-concat "    assign " (str-concat result " const 0")))
        binds (collect-match-binds ast)
        _ (loop [bi 0]
            (if (>= bi (count binds)) 0
              (do (put lines (str-concat "    assign " (str-concat (get binds bi) " const 0")))
                  (recur (+ bi 1)))))]
    (loop [i 2 tcur t2 lcur l2]
      (if (>= i n)
        (do (put lines (str-concat "    jump " join))
            (put lines (str-concat "  " (str-concat join ":")))
            (mk-ret result tcur lcur))
        (let [pat (get ast i)
              body (get ast (+ i 1))
              r (lower-match-arm pat body val result join tcur lcur lines loops adt structs)
              t3 (get r 0)
              l3 (get r 1)
              done (get r 2)]
          (if (= done 1)
            (do (put lines (str-concat "  " (str-concat join ":")))
                (mk-ret result t3 l3))
            (recur (+ i 2) t3 l3)))))))

(defn is-defn-form? [expr]
  (if (is-atom? expr) false
    (let [head (list-head expr)]
      (if (is-atom? head)
        (= (tag-of head) 10)
        false))))

(defn defn-name-is-main? [expr]
  (if (is-defn-form? expr)
    (str-eq? (val-of (get expr 1)) "main")
    false))

(defn has-main-defn? [ast-list]
  (let [n (count ast-list)]
    (loop [i 0]
      (if (>= i n) false
        (if (defn-name-is-main? (get ast-list i)) true
          (recur (+ i 1)))))))

;; Emit synthetic main from top-level exprs (scripts without defn main)
(defn lower-toplevel-main [exprs t l lines loops adt structs]
  (let [entry (fresh-label l "entry_")
        l2 (+ l 1)
        n (count exprs)
        _ (put lines "func main []:")
        _ (put lines (str-concat "  " (str-concat entry ":")))]
    (if (<= n 0)
      (do (put lines "    return const 0")
          (mk-ret "<done>" t l2))
      (let [res (lower-body-exprs exprs 0 n t l2 lines loops adt structs "")
            op (ret-op res)
            t3 (st-t res)
            l3 (st-l res)
            _ (if (is-dead-op? op)
                (put lines "    return const 0")
                (put lines (str-concat "    return " (op-fmt op))))]
        (mk-ret "<done>" t3 l3)))))

;; ---- Top-level def → real globals (Phase 17.5) ----
;; (def name init) at top level becomes a global cell. Backends emit the
;; storage from "global <name>" decl lines; initializers run once in
;; __bars_init_globals (called by the C main wrapper before _bars_main).
;; Note: a global name must not be shadowed by a local of the same name.

(defn is-def-form? [expr]
  (if (is-atom? expr) false
    (let [head (list-head expr)]
      (if (is-atom? head)
        (if (= (tag-of head) 1) (str-eq? (val-of head) "def") false)
        false))))

(defn name-in? [name names]
  (let [n (count names)]
    (loop [i 0]
      (if (>= i n) false
        (if (str-eq? (get names i) name) true
          (recur (+ i 1)))))))

;; Collect [name init-ast] pairs from top-level def forms, in source order.
(defn collect-gdefs [ast-list]
  (let [n (count ast-list) out (vector)]
    (loop [i 0]
      (if (>= i n) out
        (let [expr (get ast-list i)]
          (if (is-def-form? expr)
            (let [pair (vector)]
              (do (push pair (val-of (get expr 1)))
                  (push pair (get expr 2))
                  (push out pair)
                  (recur (+ i 1))))
            (recur (+ i 1))))))))

;; Emit "global <name>" decl lines (dedup by name; repeated def re-inits).
(defn emit-global-decls [lines gdefs]
  (let [n (count gdefs) seen (vector)]
    (loop [i 0]
      (if (>= i n) lines
        (let [name (get (get gdefs i) 0)]
          (if (name-in? name seen)
            (recur (+ i 1))
            (do (push seen name)
                (put lines (str-concat "global " name))
                (recur (+ i 1)))))))))

;; Emit the init function: assigns each global in source order.
;; Always emitted (even with no globals) so the C main wrapper can call it.
;; Returns [t l] for counter threading.
(defn lower-gdefs-init [gdefs t l lines adt structs]
  (let [entry (fresh-label l "entry_")
        l2 (+ l 1)
        n (count gdefs)
        _ (put lines "func __bars_init_globals []:")
        _ (put lines (str-concat "  " (str-concat entry ":")))
        r (loop [i 0 tcur t lcur l2]
            (if (>= i n) (let [out (vector)] (do (push out tcur) (push out lcur) out))
              (let [pair (get gdefs i)
                    name (get pair 0)
                    res (lower-expr (get pair 1) tcur lcur lines (vector) adt structs)
                    op (ret-op res)
                    t2 (st-t res)
                    l3 (st-l res)
                    _ (put lines (str-concat "    assign " (str-concat name (str-concat " " (op-fmt op)))))]
                (recur (+ i 1) t2 l3))))]
    (do (put lines "    return const 0")
        r)))

(defn lower-program [ast-list]
  (let [lines (vector)
        n (count ast-list)
        empty (vector)
        adt (collect-adt ast-list)
        structs (collect-structs ast-list)
        _ (emit-all-ctors lines adt)
        _ (emit-all-struct-ctors lines structs)
        gdefs (collect-gdefs ast-list)
        _ (emit-global-decls lines gdefs)
        init-r (lower-gdefs-init gdefs 0 0 lines adt structs)
        t0 (get init-r 0)
        l0 (get init-r 1)
        tops (vector)
        has-main (has-main-defn? ast-list)]
    (loop [i 0 t t0 l l0]
      (if (>= i n)
        (do (if (if has-main false (> (count tops) 0))
              (lower-toplevel-main tops t l lines empty adt structs)
              0)
            lines)
        (let [expr (get ast-list i)]
          (if (is-defn-form? expr)
            (let [res (lower-expr expr t l lines empty adt structs)]
              (recur (+ i 1) (st-t res) (st-l res)))
            (if (if (is-deftype-form? expr) true (is-defstruct-form? expr))
              (recur (+ i 1) t l)
              (if (is-def-form? expr)
                ;; handled by __bars_init_globals
                (recur (+ i 1) t l)
                (do (push tops expr)
                    (recur (+ i 1) t l))))))))))

(defn print-hir [lines]
  (let [n (count lines)]
    (loop [i 0]
      (if (>= i n) 0
        (do (println (get lines i))
            (recur (+ i 1)))))))

(defn main []
  0)
