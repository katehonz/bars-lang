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

(defn int-str [n]
  (let [d "0123456789"]
    (if (< n 0) (str-concat "-" (int-str (- 0 n)))
      (if (< n 10) (str-slice d n (+ n 1))
        (str-concat (int-str (/ n 10)) (str-slice d (% n 10) (+ (% n 10) 1)))))))

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

;; ============================================================
;; lower-expr [ast t l lines loops adt]
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
            (mk-ret (val-of ast) t l)
            (if (= tag 4)
              (mk-ret "0" t l)
              (if (= tag 5)
                (mk-ret (int-str (val-of ast)) t l)
                (mk-ret "<unk>" t l)))))))))

;; Lower vector elements from index `start` → vector + push
(defn lower-vector-from [ast start t l lines loops adt]
  (let [n (count ast)
        dest (fresh-temp t)
        t1 (+ t 1)
        _ (put lines (str-concat "    call " (str-concat dest " vector")))]
    (loop [i start tcur t1 lcur l]
      (if (>= i n)
        (mk-ret dest tcur lcur)
        (let [res (lower-expr (get ast i) tcur lcur lines loops adt)
              op (ret-op res)
              t2 (st-t res)
              l2 (st-l res)
              tmp (fresh-temp t2)
              _ (put lines (str-concat "    call " (str-concat tmp
                    (str-concat " push var " (str-concat dest
                      (str-concat " " (op-fmt op)))))))]
          (recur (+ i 1) (+ t2 1) l2))))))

(defn lower-form [ast t l lines loops adt]
  (let [head (list-head ast)
        tag (if (is-atom? head) (tag-of head) -1)]
    (if (= tag 10)
      (lower-defn ast t l lines loops adt)
      (if (= tag 11)
        (lower-let ast t l lines loops adt)
        (if (= tag 12)
          (lower-if ast t l lines loops adt)
          (if (= tag 13)
            (lower-do ast t l lines loops adt)
            (if (= tag 14)
              (lower-loop ast t l lines loops adt)
              (if (= tag 15)
                (lower-recur ast t l lines loops adt)
                (if (= tag 17)
                  (lower-match ast t l lines loops adt)
                  (if (= tag 28)
                    (lower-vector-from ast 1 t l lines loops adt)
                    (if (is-atom? head)
                      (lower-call ast t l lines loops adt)
                      ;; Bare data vector (no marker): all elements
                      (lower-vector-from ast 0 t l lines loops adt))))))))))))

(defn lower-expr [ast t l lines loops adt]
  (if (is-atom? ast)
    (lower-atom ast t l lines)
    (lower-form ast t l lines loops adt)))

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

(defn lower-body-exprs [ast i n t l lines loops adt last-op]
  (if (>= i n) (mk-ret last-op t l)
    (let [res (lower-expr (get ast i) t l lines loops adt)
          op  (ret-op res)
          t2  (st-t res)
          l2  (st-l res)]
      (lower-body-exprs ast (+ i 1) n t2 l2 lines loops adt op))))

(defn lower-defn [ast t l lines loops adt]
  (let [name   (val-of (get ast 1))
        params (unwrap-vec (get ast 2))
        n      (count ast)
        entry  (fresh-label l "entry_")
        l2     (+ l 1)
        empty  (vector)
        _      (put lines (str-concat "func " (str-concat name (str-concat " " (str-concat (fmt-params params) ":")))))
        _      (put lines (str-concat "  " (str-concat entry ":")))
        res    (if (> n 4)
                 (lower-body-exprs ast 3 n t l2 lines empty adt "")
                 (lower-expr (get ast 3) t l2 lines empty adt))
        op     (ret-op res)
        t3     (st-t res)
        l3     (st-l res)
        _      (if (is-dead-op? op) 0
                 (put lines (str-concat "    return " (op-fmt op))))]
    (mk-ret "<done>" t3 l3)))

;; ADT constructor call: vector + push disc + fields
(defn lower-ctor [disc args t l lines loops adt]
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
        (let [res (lower-expr (get args i) tcur lcur lines loops adt)
              op (ret-op res)
              t3 (st-t res)
              l3 (st-l res)
              tmp (fresh-temp t3)
              _ (put lines (str-concat "    call " (str-concat tmp
                    (str-concat " push var " (str-concat dest
                      (str-concat " " (op-fmt op)))))))]
          (recur (+ i 1) (+ t3 1) l3))))))

(defn lower-call [ast t l lines loops adt]
  (let [fname (val-of (get ast 0))
        n (count ast)
        entry (adt-lookup adt fname)]
    (if (adt-found? entry)
      ;; Collect arg exprs into vector for lower-ctor
      (let [args (vector)]
        (do (loop [i 1]
              (if (>= i n) 0
                (do (push args (get ast i))
                    (recur (+ i 1)))))
            (lower-ctor (get entry 1) args t l lines loops adt)))
      ;; Normal call
      (loop [i 1 args (vector) tcur t lcur l]
        (if (>= i n)
          (let [dest (fresh-temp tcur)
                tnext (+ tcur 1)
                astr (join-args args 0)
                _ (put lines (str-concat "    call " (str-concat dest (str-concat " " (str-concat fname (str-concat " " astr))))))]
            (mk-ret dest tnext lcur))
          (let [res (lower-expr (get ast i) tcur lcur lines loops adt)
                op  (ret-op res)
                t2  (st-t res)
                l2  (st-l res)
                _   (push args op)]
            (recur (+ i 1) args t2 l2)))))))

(defn join-args [args i]
  (let [n (count args)]
    (if (>= i n) ""
      (if (= i 0) (str-concat (op-fmt (get args i)) (join-args args (+ i 1)))
        (str-concat " " (str-concat (op-fmt (get args i)) (join-args args (+ i 1))))))))

(defn lower-let [ast t l lines loops adt]
  (let [binds (unwrap-vec (get ast 1))
        nbody (count ast)
        n (count binds)]
    ;; First: evaluate bindings
    (loop [i 0 tcur t lcur l]
      (if (>= i n)
        ;; Then: body (multi-body let = sequential exprs)
        (if (<= nbody 3)
          (lower-expr (get ast 2) tcur lcur lines loops adt)
          (loop [j 2 last "" t2 tcur l2 lcur]
            (if (>= j nbody)
              (mk-ret last t2 l2)
              (let [res (lower-expr (get ast j) t2 l2 lines loops adt)
                    op (ret-op res)
                    t3 (st-t res)
                    l3 (st-l res)]
                (recur (+ j 1) op t3 l3)))))
        (let [bname (val-of (get binds i))
              bval  (get binds (+ i 1))
              res   (lower-expr bval tcur lcur lines loops adt)
              op    (ret-op res)
              t2    (st-t res)
              l2    (st-l res)
              _     (put lines (str-concat "    assign " (str-concat bname (str-concat " " (op-fmt op)))))]
          (recur (+ i 2) t2 l2))))))

(defn lower-if [ast t l lines loops adt]
  (let [c-ast (get ast 1) then-ast (get ast 2) else-ast (get ast 3)
        res0  (lower-expr c-ast t l lines loops adt)
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
        res1  (lower-expr then-ast t2 l4 lines loops adt)
        op1   (ret-op res1)
        t3    (st-t res1)
        l5    (st-l res1)
        _     (if (is-dead-op? op1) 0
                (do (put lines (str-concat "    assign " (str-concat result (str-concat " " (op-fmt op1)))))
                    (put lines (str-concat "    jump " j-lbl))))
        _     (put lines (str-concat "  " (str-concat e-lbl ":")))
        res2  (lower-expr else-ast t3 l5 lines loops adt)
        op2   (ret-op res2)
        t4b   (st-t res2)
        l6    (st-l res2)
        _     (if (is-dead-op? op2) 0
                (do (put lines (str-concat "    assign " (str-concat result (str-concat " " (op-fmt op2)))))
                    (put lines (str-concat "    jump " j-lbl))))]
    (if (if (is-dead-op? op1) (is-dead-op? op2) false)
      ;; Both arms terminate (return/recur) — no join needed
      (mk-ret "<dead>" t4b l6)
      (do (put lines (str-concat "  " (str-concat j-lbl ":")))
          (mk-ret result t4b l6)))))

(defn lower-do [ast t l lines loops adt]
  (let [n (count ast)]
    (loop [i 1 last "" tcur t lcur l]
      (if (>= i n) (mk-ret last tcur lcur)
        (let [res (lower-expr (get ast i) tcur lcur lines loops adt)
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

(defn lower-loop [ast t l lines loops adt]
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
              res (lower-expr body tcur lcur lines loops2 adt)
              op (ret-op res)
              t3 (st-t res)
              l3 (st-l res)]
          (if (is-dead-op? op)
            (mk-ret "<dead>" t3 l3)
            (mk-ret op t3 l3)))
        (let [bname (val-of (get binds i))
              bval (get binds (+ i 1))
              res (lower-expr bval tcur lcur lines loops adt)
              op (ret-op res)
              t2 (st-t res)
              l2b (st-l res)
              _ (put lines (str-concat "    assign " (str-concat bname (str-concat " " (op-fmt op)))))]
          (recur (+ i 2) t2 l2b))))))

(defn lower-recur [ast t l lines loops adt]
  (if (< (count loops) 1)
    (mk-ret "0" t l)
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
          (let [res (lower-expr (get ast i) tcur lcur lines loops adt)
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

(defn is-wildcard-pat? [pat]
  (if (is-atom? pat)
    (str-eq? (val-of pat) "_")
    false))

(defn is-binding-pat? [pat]
  (if (is-atom? pat)
    (if (str-eq? (val-of pat) "_") false true)
    false))

(defn pattern-ctor-name [pat]
  (if (is-atom? pat) ""
    (let [head (get pat 0)]
      (if (is-atom? head)
        (val-of head)
        ""))))

(defn pattern-fields [pat]
  ;; returns vector of field binding names (strings)
  (if (is-atom? pat) (vector)
    (let [n (count pat)
          fields (vector)]
      (do (loop [i 1]
            (if (>= i n) 0
              (let [f (get pat i)]
                (do (if (is-atom? f)
                      (push fields (val-of f))
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
(defn match-arm-body [body result join t l lines loops adt]
  (let [resb (lower-expr body t l lines loops adt)
        opb (ret-op resb)
        tb (st-t resb)
        lb (st-l resb)]
    (do (if (is-dead-op? opb) 0
          (do (put lines (str-concat "    assign " (str-concat result (str-concat " " (op-fmt opb)))))
              (put lines (str-concat "    jump " join))))
        [tb lb])))

;; Process one match arm; returns [t l done]
;; done=1 means catch-all (stop processing more arms)
(defn lower-match-arm [pat body val result join t l lines loops adt]
  (if (is-wildcard-pat? pat)
    ;; Fall-through catch-all (no branch needed)
    (let [tl (match-arm-body body result join t l lines loops adt)]
      [(get tl 0) (get tl 1) 1])
  (if (is-binding-pat? pat)
    (do (put lines (str-concat "    assign " (str-concat (val-of pat) (str-concat " " (op-fmt val)))))
        (let [tl (match-arm-body body result join t l lines loops adt)]
          [(get tl 0) (get tl 1) 1]))
    ;; ADT variant: branch on discriminant
    (let [arm (fresh-label l "match_arm_")
          l3 (+ l 1)
          nxt (fresh-label l3 "match_next_")
          l4 (+ l3 1)
          cname (pattern-ctor-name pat)
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
          tl (match-arm-body body result join t5 l4 lines loops adt)
          _ (put lines (str-concat "  " (str-concat nxt ":")))]
      [(get tl 0) (get tl 1) 0]))))

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

(defn lower-match [ast t l lines loops adt]
  (let [scrut (get ast 1)
        n (count ast)
        res0 (lower-expr scrut t l lines loops adt)
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
              r (lower-match-arm pat body val result join tcur lcur lines loops adt)
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

(defn lower-program [ast-list]
  (let [lines (vector)
        n (count ast-list)
        empty (vector)
        adt (collect-adt ast-list)
        _ (emit-all-ctors lines adt)]
    (loop [i 0 t 0 l 0]
      (if (>= i n)
        lines
        (let [expr (get ast-list i)]
          (if (is-defn-form? expr)
            (let [res (lower-expr expr t l lines empty adt)]
              (recur (+ i 1) (st-t res) (st-l res)))
            (recur (+ i 1) t l)))))))

(defn print-hir [lines]
  (let [n (count lines)]
    (loop [i 0]
      (if (>= i n) 0
        (do (println (get lines i))
            (recur (+ i 1)))))))

(defn main []
  0)
