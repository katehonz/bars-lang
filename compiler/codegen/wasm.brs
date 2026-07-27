;; Bars WASM (WAT) backend — Phase 14.4+
;; HIR text → WebAssembly Text Format (integer-oriented).
;;
;; Control flow: PC dispatcher (loop + per-step if). Handles
;; assign / call / branch / jump / return / labels.
;;
;; Host I/O: WASI preview1 fd_write → $bars_println_i64 (decimal + newline).
;;
;; Limitations:
;;   - i64 only (no Bars strings/vectors at runtime)
;;   - println prints the i64 value (not pointer-typed strings)
;;
;; Opt-in: BARS_BACKEND_WASM=1
;; Optional: wat2wasm / wasm-tools to emit .wasm
;; Run: wasmtime --invoke main out.wasm

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

(defn w-ident [s]
  (let [n (count s)]
    (loop [i 0 acc ""]
      (if (>= i n)
        (if (= (count acc) 0) "_id" acc)
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

;; ---- HIR line classification ----
;; Labels: "  name:"  (2 spaces). Instrs: "    ..." (4 spaces).

(defn is-label-line? [line]
  (let [n (count line)]
    (if (< n 3) false
      (if (if (= (str-get line 0) 32) (= (str-get line 1) 32) false)
        (if (!= (str-get line 2) 32)
          (= (str-get line (- n 1)) 58)
          false)
        false))))

(defn label-name [line]
  ;; strip leading spaces and trailing ':'
  (let [t (trim-left line)
        n (count t)]
    (if (if (> n 0) (= (str-get t (- n 1)) 58) false)
      (str-slice t 0 (- n 1))
      t)))

(defn extract-func-name [line]
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

;; ---- label → pc table (vector of [name pc] pairs) ----

(defn label-pc-get [table name]
  (let [n (count table)]
    (loop [i 0]
      (if (>= i n) -1
        (let [e (get table i)]
          (if (str-eq? (get e 0) name) (get e 1)
            (recur (+ i 1))))))))

(defn label-pc-set [table name pc]
  (let [pair (vector)]
    (do (push pair name)
        (push pair pc)
        (push table pair)
        table)))

;; Pre-scan: assign PC to every body line; build label table.
;; Also collect all assign/call dest names into locals.
(defn prescan-body [body-lines locals]
  (let [n (count body-lines)
        table (vector)]
    (do (loop [i 0]
          (if (>= i n) 0
            (let [line (get body-lines i)]
              (if (is-label-line? line)
                (do (label-pc-set table (label-name line) i)
                    (recur (+ i 1)))
                (let [trimmed (trim-left line)
                      words (split-words trimmed)
                      cmd (if (> (count words) 0) (get words 0) "")]
                  (if (if (str-eq? cmd "assign") true (str-eq? cmd "call"))
                    (if (>= (count words) 2)
                      (do (ensure-local locals (get words 1))
                          (recur (+ i 1)))
                      (recur (+ i 1)))
                    (recur (+ i 1))))))))
        table)))

;; Emit: set $pc to target and branch back to dispatcher loop.
(defn emit-goto-pc [out pc]
  (do (lines-push out (str-concat "      i32.const " (int-str pc)))
      (lines-push out "      local.set $__pc")
      (lines-push out "      br $dispatch")
      out))

(defn emit-next-pc [out i n]
  (if (>= (+ i 1) n)
    (do (lines-push out "      i64.const 0")
        (lines-push out "      return")
        out)
    (emit-goto-pc out (+ i 1))))

;; Emit one instruction body (no outer if). Ends with br $dispatch or return.
(defn emit-step [out words locals table i nsteps]
  (let [cmd (if (> (count words) 0) (get words 0) "")
        nw (count words)]
    (if (str-eq? cmd "assign")
      (let [dest (get words 1)
            _ (ensure-local locals dest)]
        (do (lines-push out (str-concat "      " (pair-op words 2)))
            (lines-push out (str-concat "      local.set $" (w-ident dest)))
            (emit-next-pc out i nsteps)))
      (if (str-eq? cmd "call")
        (emit-step-call out words nw locals table i nsteps)
        (if (str-eq? cmd "return")
          (let [val (if (>= nw 3) (get words 2) "")]
            (if (if (str-eq? val "<dead>") true (str-eq? val "<done>"))
              (do (lines-push out "      i64.const 0")
                  (lines-push out "      return")
                  out)
              (do (lines-push out (str-concat "      " (pair-op words 1)))
                  (lines-push out "      return")
                  out)))
          (if (str-eq? cmd "branch")
            ;; branch var/const c then-lbl else-lbl
            (let [cond (pair-op words 1)
                  then-n (get words 3)
                  else-n (get words 4)
                  then-pc (label-pc-get table then-n)
                  else-pc (label-pc-get table else-n)]
              (do (lines-push out (str-concat "      " cond))
                  (lines-push out "      i32.wrap_i64")
                  (lines-push out "      if")
                  (lines-push out (str-concat "        i32.const " (int-str then-pc)))
                  (lines-push out "        local.set $__pc")
                  (lines-push out "      else")
                  (lines-push out (str-concat "        i32.const " (int-str else-pc)))
                  (lines-push out "        local.set $__pc")
                  (lines-push out "      end")
                  (lines-push out "      br $dispatch")
                  out))
            (if (str-eq? cmd "jump")
              (let [lbl (get words 1)
                    pc (label-pc-get table lbl)]
                (emit-goto-pc out pc))
              (if (str-eq? cmd "stringlit")
                ;; no string runtime: store 0
                (let [dest (get words 1)
                      _ (ensure-local locals dest)]
                  (do (lines-push out "      i64.const 0")
                      (lines-push out (str-concat "      local.set $" (w-ident dest)))
                      (emit-next-pc out i nsteps)))
                ;; unknown / empty: fall through
                (emit-next-pc out i nsteps)))))))))

(defn emit-step-call [out words nw locals table i nsteps]
  (let [dest (get words 1)
        fname (get words 2)
        bop (binop-wat fname)
        cop (cmp-wat fname)
        _ (ensure-local locals dest)]
    (if (> (count bop) 0)
      (do (lines-push out (str-concat "      " (pair-op words 3)))
          (lines-push out (str-concat "      " (pair-op words 5)))
          (lines-push out (str-concat "      " bop))
          (lines-push out (str-concat "      local.set $" (w-ident dest)))
          (emit-next-pc out i nsteps))
      (if (> (count cop) 0)
        (do (lines-push out (str-concat "      " (pair-op words 3)))
            (lines-push out (str-concat "      " (pair-op words 5)))
            (lines-push out (str-concat "      " cop))
            (lines-push out "      i64.extend_i32_u")
            (lines-push out (str-concat "      local.set $" (w-ident dest)))
            (emit-next-pc out i nsteps))
        (if (str-eq? fname "not")
          (do (lines-push out (str-concat "      " (pair-op words 3)))
              (lines-push out "      i64.eqz")
              (lines-push out "      i64.extend_i32_u")
              (lines-push out (str-concat "      local.set $" (w-ident dest)))
              (emit-next-pc out i nsteps))
          (if (str-eq? fname "println")
            ;; WASI-backed i64 println (arg at words 3..4)
            (do (if (<= nw 3)
                  (lines-push out "      i64.const 0")
                  (lines-push out (str-concat "      " (pair-op words 3))))
                (lines-push out "      call $bars_println_i64")
                (lines-push out (str-concat "      local.set $" (w-ident dest)))
                (emit-next-pc out i nsteps))
            (do (loop [j 3]
                  (if (>= j nw) 0
                    (do (lines-push out (str-concat "      " (pair-op words j)))
                        (recur (+ j 2)))))
                (lines-push out (str-concat "      call $" (map-user-fname fname)))
                (lines-push out (str-concat "      local.set $" (w-ident dest)))
                (emit-next-pc out i nsteps))))))))

(defn compile-func-dispatch [name params body-lines]
  (let [out (vector)
        locals (vector)
        nparams (count params)
        nsteps (count body-lines)]
    (do (loop [i 0]
          (if (>= i nparams) 0
            (do (ensure-local locals (get params i))
                (recur (+ i 1)))))
        (let [table (prescan-body body-lines locals)]
          (do (lines-push out (func-header name params))
              ;; body
              (lines-push out "    i32.const 0")
              (lines-push out "    local.set $__pc")
              (lines-push out "    (loop $dispatch")
              (loop [i 0]
                (if (>= i nsteps) 0
                  (let [line (get body-lines i)]
                    (do (lines-push out (str-concat "      ;; step " (int-str i)))
                        (lines-push out "      local.get $__pc")
                        (lines-push out (str-concat "      i32.const " (int-str i)))
                        (lines-push out "      i32.eq")
                        (lines-push out "      if")
                        (if (is-label-line? line)
                          (emit-next-pc out i nsteps)
                          (let [trimmed (trim-left line)
                                words (split-words trimmed)]
                            (emit-step out words locals table i nsteps)))
                        (lines-push out "      end")
                        (recur (+ i 1))))))
              (lines-push out "      br $dispatch")
              (lines-push out "    )")
              (lines-push out "    i64.const 0")
              (lines-push out "    return")
              ;; wrap with locals after header
              (let [ld (locals-decl locals params)
                    final (vector)]
                (do (lines-push final (get out 0))
                    (lines-push final "    (local $__pc i32)")
                    (if (> (count ld) 0)
                      (lines-push final (str-concat "   " ld))
                      0)
                    (loop [i 1]
                      (if (>= i (count out)) 0
                        (do (lines-push final (get out i))
                            (recur (+ i 1)))))
                    (lines-push final "  )")
                    final)))))))

;; WASI import + memory + decimal println helper (emitted once per module).
(defn emit-wasi-runtime [mod]
  (do
    (lines-push mod "  ;; WASI preview1 — stdout via fd_write")
    (lines-push mod "  (import \"wasi_snapshot_preview1\" \"fd_write\"")
    (lines-push mod "    (func $fd_write (param i32 i32 i32 i32) (result i32)))")
    (lines-push mod "  (memory (export \"memory\") 1)")
    (lines-push mod "  ;; mem: 0..=7 iovec {ptr,len}, 8..=11 nwritten, 16..=48 digit buf")
    (lines-push mod "  (func $bars_println_i64 (param $v i64) (result i64)")
    (lines-push mod "    (local $x i64) (local $neg i32) (local $pos i32)")
    (lines-push mod "    (local $start i32) (local $len i32)")
    (lines-push mod "    local.get $v")
    (lines-push mod "    local.set $x")
    (lines-push mod "    i32.const 0")
    (lines-push mod "    local.set $neg")
    (lines-push mod "    i32.const 40")
    (lines-push mod "    local.set $pos")
    ;; zero
    (lines-push mod "    local.get $x")
    (lines-push mod "    i64.eqz")
    (lines-push mod "    if")
    (lines-push mod "      i32.const 39")
    (lines-push mod "      local.set $pos")
    (lines-push mod "      i32.const 39")
    (lines-push mod "      i32.const 48")
    (lines-push mod "      i32.store8")
    (lines-push mod "    else")
    (lines-push mod "      local.get $x")
    (lines-push mod "      i64.const 0")
    (lines-push mod "      i64.lt_s")
    (lines-push mod "      if")
    (lines-push mod "        i32.const 1")
    (lines-push mod "        local.set $neg")
    (lines-push mod "        i64.const 0")
    (lines-push mod "        local.get $x")
    (lines-push mod "        i64.sub")
    (lines-push mod "        local.set $x")
    (lines-push mod "      end")
    (lines-push mod "      (loop $digits")
    (lines-push mod "        local.get $pos")
    (lines-push mod "        i32.const 1")
    (lines-push mod "        i32.sub")
    (lines-push mod "        local.set $pos")
    (lines-push mod "        local.get $pos")
    (lines-push mod "        local.get $x")
    (lines-push mod "        i64.const 10")
    (lines-push mod "        i64.rem_u")
    (lines-push mod "        i32.wrap_i64")
    (lines-push mod "        i32.const 48")
    (lines-push mod "        i32.add")
    (lines-push mod "        i32.store8")
    (lines-push mod "        local.get $x")
    (lines-push mod "        i64.const 10")
    (lines-push mod "        i64.div_u")
    (lines-push mod "        local.set $x")
    (lines-push mod "        local.get $x")
    (lines-push mod "        i64.const 0")
    (lines-push mod "        i64.ne")
    (lines-push mod "        br_if $digits")
    (lines-push mod "      )")
    (lines-push mod "      local.get $neg")
    (lines-push mod "      if")
    (lines-push mod "        local.get $pos")
    (lines-push mod "        i32.const 1")
    (lines-push mod "        i32.sub")
    (lines-push mod "        local.set $pos")
    (lines-push mod "        local.get $pos")
    (lines-push mod "        i32.const 45")
    (lines-push mod "        i32.store8")
    (lines-push mod "      end")
    (lines-push mod "    end")
    ;; newline at 40
    (lines-push mod "    i32.const 40")
    (lines-push mod "    i32.const 10")
    (lines-push mod "    i32.store8")
    (lines-push mod "    local.get $pos")
    (lines-push mod "    local.set $start")
    (lines-push mod "    i32.const 41")
    (lines-push mod "    local.get $pos")
    (lines-push mod "    i32.sub")
    (lines-push mod "    local.set $len")
    ;; iovec at 0
    (lines-push mod "    i32.const 0")
    (lines-push mod "    local.get $start")
    (lines-push mod "    i32.store")
    (lines-push mod "    i32.const 4")
    (lines-push mod "    local.get $len")
    (lines-push mod "    i32.store")
    ;; fd_write(stdout=1, iov=0, iovcnt=1, nwritten=8)
    (lines-push mod "    i32.const 1")
    (lines-push mod "    i32.const 0")
    (lines-push mod "    i32.const 1")
    (lines-push mod "    i32.const 8")
    (lines-push mod "    call $fd_write")
    (lines-push mod "    drop")
    (lines-push mod "    i64.const 0")
    (lines-push mod "  )")
    mod))

(defn hir-to-wat [hir-lines]
  (let [n (count hir-lines)
        funcs (vector)
        mod (vector)]
    (do (lines-push mod ";; Generated by Bars WASM/WAT backend (PC dispatch + WASI println)")
        (lines-push mod "(module")
        (emit-wasi-runtime mod)
        (loop [i 0 cur-name "" cur-params (vector) cur-body (vector) in-func 0]
          (if (>= i n)
            (do (if (= in-func 1)
                  (push funcs (compile-func-dispatch cur-name cur-params cur-body))
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
                      (push funcs (compile-func-dispatch cur-name cur-params cur-body))
                      0)
                    (let [nm (extract-func-name line)
                          ps (split-words (extract-params-str line))
                          body (vector)]
                      (recur (+ i 1) nm ps body 1)))
                (if (= in-func 1)
                  ;; keep labels (2-space) and instrs (4-space); skip blanks
                  (do (if (if (str-starts-with? line "    ") true
                            (is-label-line? line))
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
