;; Bars HIR Lowering — Stage 2
;; Simplified: use let+_ instead of do for flat structure

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
        (str-concat "var " s)))))

(defn ret-op [r] (get r 0)) (defn ret-st [r] (get r 1))
(defn st-t [r] (get (ret-st r) 0)) (defn st-l [r] (get (ret-st r) 1))
(defn mk-ret [op t l] [op [t l]])

(defn is-atom? [x] (< (get x 0) 1000))
(defn tag-of [x] (get x 0))
(defn val-of [x] (get x 1))
(defn list-head [x] (get x 0))

;; ============================================================
;; lower-expr
;; ============================================================
(defn lower-expr [ast t l lines]
  (if (is-atom? ast)
    (let [tag (tag-of ast)]
      (if (= tag 0) (mk-ret (int-str (val-of ast)) t l)
      (if (= tag 1) (mk-ret (val-of ast) t l)
      (if (= tag 2) (mk-ret (val-of ast) t l)
      (if (= tag 3) (mk-ret (val-of ast) t l)
      (if (= tag 4) (mk-ret "0" t l)
      (if (= tag 5) (mk-ret (int-str (val-of ast)) t l)
      (mk-ret "<unk>" t l))))))))
    (let [head (list-head ast) tag (tag-of head)]
      (if (= tag 10) (lower-defn ast t l lines)
      (if (= tag 11) (lower-let  ast t l lines)
      (if (= tag 12) (lower-if   ast t l lines)
      (if (= tag 13) (lower-do   ast t l lines)
      (lower-call ast t l lines))))))))

;; ============================================================
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


(defn lower-defn [ast t l lines]
  (let [name   (val-of (get ast 1))
        params (get ast 2)
        body   (get ast 3)
        entry  (fresh-label l "entry_")
        l      (+ l 1)
        _      (put lines (str-concat "func " (str-concat name (str-concat " " (str-concat (fmt-params params) ":")))))
        _      (put lines (str-concat "  " (str-concat entry ":")))
        res    (lower-expr body t l lines)
        op     (ret-op res)
        t      (st-t res)
        l      (st-l res)
        _      (if (= op "<dead>") 0
                 (put lines (str-concat "    return " (op-fmt op))))]
    (mk-ret "<done>" t l)))

(defn lower-call [ast t l lines]
  (let [fname (val-of (get ast 0)) n (count ast)]
    (loop [i 1 args (vector) t t l l]
      (if (>= i n)
        (let [dest (fresh-temp t) t (+ t 1)
              astr (join-args args 0)
              _    (put lines (str-concat "    call " (str-concat dest (str-concat " " (str-concat fname (str-concat " " astr))))))]
          (mk-ret dest t l))
        (let [res (lower-expr (get ast i) t l lines)
              op  (ret-op res) t (st-t res) l (st-l res)
              _   (push args op)]
          (recur (+ i 1) args t l))))))

(defn join-args [args i]
  (let [n (count args)]
    (if (>= i n) ""
      (if (= i 0) (str-concat (op-fmt (get args i)) (join-args args (+ i 1)))
        (str-concat " " (str-concat (op-fmt (get args i)) (join-args args (+ i 1))))))))

(defn lower-let [ast t l lines]
  (let [binds (get ast 1) body (get ast 2) n (count binds)]
    (loop [i 0 t t l l]
      (if (>= i n) (lower-expr body t l lines)
        (let [bname (val-of (get binds i))
              bval  (get binds (+ i 1))
              res   (lower-expr bval t l lines)
              op    (ret-op res) t (st-t res) l (st-l res)
              _     (put lines (str-concat "    assign " (str-concat bname (str-concat " " (op-fmt op)))))]
          (recur (+ i 2) t l))))))

(defn lower-if [ast t l lines]
  (let [c-ast (get ast 1) then-ast (get ast 2) else-ast (get ast 3)
        res   (lower-expr c-ast t l lines)
        c-op  (ret-op res) t (st-t res) l (st-l res)
        t-lbl (fresh-label l "then_") l (+ l 1)
        e-lbl (fresh-label l "else_") l (+ l 1)
        _     (put lines (str-concat "    branch " (str-concat (op-fmt c-op) (str-concat " " (str-concat t-lbl (str-concat " " e-lbl))))))
        _     (put lines (str-concat "  " (str-concat t-lbl ":")))
        res   (lower-expr then-ast t l lines)
        op    (ret-op res) t (st-t res) l (st-l res)
        _     (put lines (str-concat "    return " (op-fmt op)))
        _     (put lines (str-concat "  " (str-concat e-lbl ":")))
        res   (lower-expr else-ast t l lines)
        op    (ret-op res) t (st-t res) l (st-l res)
        _     (put lines (str-concat "    return " (op-fmt op)))]
    (mk-ret "<dead>" t l)))

(defn lower-do [ast t l lines]
  (let [n (count ast)]
    (loop [i 1 last "" t t l l]
      (if (>= i n) (mk-ret last t l)
        (let [res (lower-expr (get ast i) t l lines)
              op  (ret-op res) t (st-t res) l (st-l res)]
          (recur (+ i 1) op t l))))))

;; lower-program: process all top-level expressions
;; Collects defn/extern, builds implicit main from other exprs
(defn lower-program [ast-list]
  (let [lines (vector)
        n (count ast-list)
        main-exprs (vector)
        t 0 l 0]
    (loop [i 0 t t l l]
      (if (>= i n)
        (if (> (count main-exprs) 0)
          (let [entry (fresh-label l "entry_")
                _ (put lines (str-concat "func main []:"))
                _ (put lines (str-concat "  " (str-concat entry ":")))
                do-ast (vector)]
            (do (push do-ast [13 "do"])
                (loop [j 0]
                  (if (>= j (count main-exprs)) 0
                    (do (push do-ast (get main-exprs j))
                        (recur (+ j 1)))))
            (let [res (lower-expr do-ast t l lines)
                  op (ret-op res)]
              (if (= op "<dead>") 0
                (put lines (str-concat "    return " (op-fmt op))))
              lines))
          lines)
        (let [expr (get ast-list i)
              head (list-head expr)
              tag (tag-of head)]
          (if (= tag 10)
            (let [res (lower-defn expr t l lines)]
              (recur (+ i 1) (st-t res) (st-l res)))
            (if (= tag 20)
              (let [name (val-of (get expr 1))
                    params (get expr 2)
                    _ (put lines (str-concat "extern " (str-concat name (str-concat " " (fmt-params params)))))]
                (recur (+ i 1) t l))
              (do (push main-exprs expr)
                  (recur (+ i 1) t l))))))))))

(defn print-hir [lines]
  (let [n (count lines)]
    (loop [i 0]
      (if (>= i n) 0
        (do (println (get lines i))
            (recur (+ i 1)))))))

(defn main []
  (println "=== HIR Lowering ===")
  (println "--- (defn main [] 42) ---")
  (print-hir (lower-program [[[10 "defn"] [1 "main"] [] [0 42]]]))
  (println "--- (defn add [x y] (+ x y)) ---")
  (print-hir (lower-program [[[10 "defn"] [1 "add"] [[1 "x"] [1 "y"]] [[1 "+"] [1 "x"] [1 "y"]]]]))
  (println "--- (defn choose [a b] (if (> a b) a b)) ---")
  (print-hir (lower-program [[[10 "defn"] [1 "choose"] [[1 "a"] [1 "b"]] [[12 "if"] [[1 ">"] [1 "a"] [1 "b"]] [1 "a"] [1 "b"]]]]))
  (println "--- (defn calc [x] (let [y (+ x 1)] (* y 2))) ---")
  (print-hir (lower-program [[[10 "defn"] [1 "calc"] [[1 "x"]] [[11 "let"] [[1 "y"] [[1 "+"] [1 "x"] [0 1]]] [[1 "*"] [1 "y"] [0 2]]]]]))
  0)
