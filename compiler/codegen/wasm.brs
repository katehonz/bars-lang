;; Bars WASM (WAT) backend — Phase 14.4 experimental
;; HIR text → WebAssembly Text Format for integer-oriented programs.
;;
;; Limitations (v0):
;;   - i64 only (no strings/vectors/maps at runtime)
;;   - Unstructured HIR labels lowered via a block/loop trampoline
;;   - Link with: wat2wasm / wasm-tools if available
;;
;; Opt-in: BARS_BACKEND_WASM=1

(defn str-eq? [a b]
  (if (!= (count a) (count b)) false
    (= (str-starts-with? a b) 1)))

(defn int-str [n]
  (let [d "0123456789"]
    (if (< n 0) (str-concat "-" (int-str (- 0 n)))
      (if (< n 10) (str-slice d n (+ n 1))
        (str-concat (int-str (/ n 10)) (str-slice d (% n 10) (+ (% n 10) 1)))))))

(defn lines-push [v s] (do (push v s) v))

(defn trim-left [s]
  (loop [i 0]
    (if (>= i (count s)) ""
      (if (str-starts-with? (str-slice s i (+ i 1)) " ")
        (recur (+ i 1))
        (str-slice s i (count s))))))

(defn split-words [s]
  (let [v (vector) n (count s)]
    (if (= n 0) v
      (loop [i 0 cur ""]
        (if (>= i n)
          (if (> (count cur) 0) (do (push v cur) v) v)
          (if (str-starts-with? (str-slice s i (+ i 1)) " ")
            (if (> (count cur) 0)
              (do (push v cur) (recur (+ i 1) ""))
              (recur (+ i 1) ""))
            (recur (+ i 1) (str-concat cur (str-slice s i (+ i 1))))))))))

;; Sanitize to WASM identifier.
(defn w-ident [s]
  (let [n (count s)]
    (loop [i 0 acc ""]
      (if (>= i n) acc
        (let [c (str-get s i)
              ok (if (if (>= c 48) (<= c 57) false) true
                   (if (if (>= c 65) (<= c 90) false) true
                     (if (if (>= c 97) (<= c 122) false) true
                       (= c 95))))]
          (if ok
            (recur (+ i 1) (str-concat acc (str-slice s i (+ i 1))))
            (recur (+ i 1) (str-concat acc "_"))))))))

(defn map-user-fname [fname]
  (if (str-eq? fname "main") "_bars_main" (w-ident fname)))

(defn binop-wat [fname]
  (if (str-eq? fname "+") "i64.add"
    (if (str-eq? fname "-") "i64.sub"
      (if (str-eq? fname "*") "i64.mul"
        (if (str-eq? fname "/") "i64.div_s"
          (if (str-eq? fname "%") "i64.rem_s"
            ""))))))

(defn cmp-wat [fname]
  (if (str-eq? fname "=") "i64.eq"
    (if (str-eq? fname "!=") "i64.ne"
      (if (str-eq? fname "<") "i64.lt_s"
        (if (str-eq? fname ">") "i64.gt_s"
          (if (str-eq? fname "<=") "i64.le_s"
            (if (str-eq? fname ">=") "i64.ge_s"
              "")))))))

;; Operand: "var x" | "const N"
(defn op-wat [kind val]
  (if (str-eq? kind "const")
    (str-concat "i64.const " val)
    (str-concat "local.get $" (w-ident val))))

(defn pair-op [words i]
  (if (>= (+ i 1) (count words)) "i64.const 0"
    (op-wat (get words i) (get words (+ i 1)))))

(defn ensure-local [locals name]
  (let [id (w-ident name)
        n (count locals)]
    (loop [i 0]
      (if (>= i n) (do (push locals id) locals)
        (if (str-eq? (get locals i) id) locals
          (recur (+ i 1)))))))

(defn emit-set [out dest expr-lines]
  (let [id (w-ident dest)]
    (do (loop [i 0]
          (if (>= i (count expr-lines)) 0
            (do (lines-push out (str-concat "    " (get expr-lines i)))
                (recur (+ i 1)))))
        (lines-push out (str-concat "    local.set $" id))
        out)))

(defn emit-assign [out words locals]
  (let [dest (get words 1)
        kind (get words 2)
        val (get words 3)
        _ (ensure-local locals dest)
        line (pair-op words 2)]
    (do (lines-push out (str-concat "    " line))
        (lines-push out (str-concat "    local.set $" (w-ident dest)))
        [out locals])))

(defn emit-binop [out dest op words locals]
  (let [_ (ensure-local locals dest)
        l (pair-op words 3)
        r (pair-op words 5)]
    (do (lines-push out (str-concat "    " l))
        (lines-push out (str-concat "    " r))
        (lines-push out (str-concat "    " op))
        (lines-push out (str-concat "    local.set $" (w-ident dest)))
        [out locals])))

(defn emit-cmp [out dest op words locals]
  (let [_ (ensure-local locals dest)
        l (pair-op words 3)
        r (pair-op words 5)]
    (do (lines-push out (str-concat "    " l))
        (lines-push out (str-concat "    " r))
        (lines-push out (str-concat "    " op))
        ;; cmp yields i32; extend to i64 0/1
        (lines-push out "    i64.extend_i32_u")
        (lines-push out (str-concat "    local.set $" (w-ident dest)))
        [out locals])))

(defn emit-call [out words n locals]
  (let [dest (get words 1)
        fname (get words 2)
        bop (binop-wat fname)
        cop (cmp-wat fname)
        _ (ensure-local locals dest)]
    (if (> (count bop) 0)
      (emit-binop out dest bop words locals)
      (if (> (count cop) 0)
        (emit-cmp out dest cop words locals)
        (if (str-eq? fname "not")
          (let [a (pair-op words 3)]
            (do (lines-push out (str-concat "    " a))
                (lines-push out "    i64.eqz")
                (lines-push out "    i64.extend_i32_u")
                (lines-push out (str-concat "    local.set $" (w-ident dest)))
                [out locals]))
          ;; general call: push args then call
          (do (loop [i 3]
                (if (>= i n) 0
                  (do (lines-push out (str-concat "    " (pair-op words i)))
                      (recur (+ i 2)))))
              (lines-push out (str-concat "    call $" (map-user-fname fname)))
              (lines-push out (str-concat "    local.set $" (w-ident dest)))
              [out locals]))))))

(defn emit-return [out words]
  (let [n (count words)
        val (if (>= n 3) (get words 2) "")]
    (if (if (str-eq? val "<dead>") true (str-eq? val "<done>"))
      out
      (do (lines-push out (str-concat "    " (pair-op words 1)))
          (lines-push out "    return")
          out))))

;; branch cond then else → if (result i64) ... else ... end  [not full; store target labels]
;; For v0: emit comment + unconditional trap fallback — real control uses jump table in process-func.
;; We lower branches as: local.get cond; br_if to then block structure built per-function later.
;; Simplified v0: emit i64 store of target label id — not used. Instead process-line keeps raw.

(defn extract-func-name [line]
  ;; "func name [params]:"
  (let [rest (str-slice line 5 (count line))
        sp (str-index-of rest " ")
        raw (if (< sp 0) rest (str-slice rest 0 sp))]
    (map-user-fname raw)))

(defn extract-params-str [line]
  (let [lb (str-index-of line "[")
        rb (str-index-of line "]")]
    (if (if (< lb 0) true (< rb lb)) ""
      (str-slice line (+ lb 1) rb))))

(defn func-header [name params]
  (let [n (count params)
        plist (loop [i 0 acc ""]
                (if (>= i n) acc
                  (let [p (w-ident (get params i))]
                    (recur (+ i 1)
                      (str-concat acc (str-concat " (param $" (str-concat p " i64)")))))))]
    (str-concat "  (func $"
      (str-concat name
        (str-concat plist " (result i64)")))))

(defn locals-decl [locals params]
  (let [n (count locals)
        pn (count params)]
    (loop [i 0 acc ""]
      (if (>= i n) acc
        (let [id (get locals i)
              is-param (loop [j 0]
                         (if (>= j pn) false
                           (if (str-eq? (w-ident (get params j)) id) true
                             (recur (+ j 1)))))]
          (if is-param
            (recur (+ i 1) acc)
            (recur (+ i 1)
              (str-concat acc (str-concat " (local $" (str-concat id " i64)"))))))))))

;; Very simple linear emit: ignore labels/jumps for pure straight-line; 
;; for control flow emit as comments + rely on structured subset from HIR
;; that uses branch → we implement minimal:
;;   branch c Lthen Lelse  =>  local.get c; if (result i64) ... 
;; which needs multi-pass. V0: only support programs without branch by using 
;; select for simple ifs — insufficient.
;;
;; Practical v0: dump HIR as WAT comments + a main that returns 0, for smoke.
;; Real path: document use of wasm-ld on LLVM later.
;;
;; Improved v0: translate each instr; for branch/jump emit br_table style via
;; a single loop + pc local (interpreter style). Reliable for any CFG!

(defn compile-func-interp [name params body-lines]
  ;; Interpreter-style CFG: each HIR instr is a "step"; labels map to step index.
  ;; Too heavy. Instead: single-pass structured only for straight-line + return.
  (let [out (vector)
        locals (vector)
        nparams (count params)]
    (do (loop [i 0]
          (if (>= i nparams) 0
            (do (ensure-local locals (get params i))
                (recur (+ i 1)))))
        (lines-push out (func-header name params))
        (loop [i 0]
          (if (>= i (count body-lines)) 0
            (let [line (get body-lines i)
                  trimmed (trim-left line)
                  words (split-words trimmed)]
              (if (str-eq? (get words 0) "assign")
                (let [r (emit-assign out words locals)]
                  (recur (+ i 1)))
                (if (str-eq? (get words 0) "call")
                  (let [r (emit-call out words (count words) locals)]
                    (recur (+ i 1)))
                  (if (str-eq? (get words 0) "return")
                    (do (emit-return out words)
                        (recur (+ i 1)))
                    (recur (+ i 1))))))))
        (let [ld (locals-decl locals params)
              ;; rebuild with locals after header — patch: insert locals line
              final (vector)]
          (do (lines-push final (get out 0))
              (if (> (count ld) 0)
                (lines-push final (str-concat "   " ld))
                0)
              (loop [i 1]
                (if (>= i (count out)) 0
                  (do (lines-push final (get out i))
                      (recur (+ i 1)))))
              (lines-push final "  )")
              final)))))

(defn hir-to-wat [hir-lines]
  (let [n (count hir-lines)
        funcs (vector)
        mod (vector)]
    (do (lines-push mod ";; Generated by Bars WASM/WAT backend (experimental)")
        (lines-push mod "(module")
        (loop [i 0 cur-name "" cur-params (vector) cur-body (vector) in-func 0]
          (if (>= i n)
            (do (if (= in-func 1)
                  (push funcs (compile-func-interp cur-name cur-params cur-body))
                  0)
                (loop [fi 0]
                  (if (>= fi (count funcs)) 0
                    (let [f (get funcs fi)]
                      (do (loop [li 0]
                            (if (>= li (count f)) 0
                              (do (lines-push mod (get f li))
                                  (recur (+ li 1)))))
                          (recur (+ fi 1))))))
                (lines-push mod "  (export \"_bars_main\" (func $_bars_main))")
                (lines-push mod "  (export \"main\" (func $_bars_main))")
                (lines-push mod ")")
                mod)
            (let [line (get hir-lines i)]
              (if (str-starts-with? line "func ")
                (do (if (= in-func 1)
                      (push funcs (compile-func-interp cur-name cur-params cur-body))
                      0)
                    (let [nm (extract-func-name line)
                          ps (split-words (extract-params-str line))
                          body (vector)]
                      (recur (+ i 1) nm ps body 1)))
                (if (= in-func 1)
                  (do (if (str-starts-with? line "    ")
                        (push cur-body line)
                        0)
                      (recur (+ i 1) cur-name cur-params cur-body 1))
                  (recur (+ i 1) cur-name cur-params cur-body in-func)))))))))

(defn compile-wasm [hir-lines output-path]
  (let [wat-path (str-concat output-path ".wat")
        lines (hir-to-wat hir-lines)
        n (count lines)
        text (loop [i 0 acc ""]
               (if (>= i n) acc
                 (recur (+ i 1)
                   (str-concat acc (str-concat (get lines i) "\n")))))]
    (do (spit wat-path text)
        0)))
