;; Bars LLVM Backend — Stage 7 of self-hosting
;; Parses HIR text format from hir.brs -> LLVM IR text (.ll format)
;;
;; HIR format (4-space indent for instructions, 2-space for labels):
;;   func name [params]:
;;     label_name:
;;       assign name var/const val
;;       call dest fname [var/const arg ...]
;;       branch var/const cond then_lbl else_lbl
;;       return var/const val
;;       stringlit dest string_content

(defn str-eq? [a b]
  (if (!= (count a) (count b)) false
    (= (str-starts-with? a b) 1)))

(defn int-str [n]
  (let [d "0123456789"]
    (if (< n 0) (str-concat "-" (int-str (- 0 n)))
      (if (< n 10) (str-slice d n (+ n 1))
        (str-concat (int-str (/ n 10)) (str-slice d (% n 10) (+ (% n 10) 1)))))))

;; ---- helpers ----

(defn lines-push [v s] (do (push v s) v))

(defn trim-left [s]
  (loop [i 0]
    (if (>= i (count s)) ""
      (if (str-starts-with? (str-slice s i (+ i 1)) " ")
        (recur (+ i 1))
        (str-slice s i (count s))))))

;; Split string by spaces -> vector of tokens
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

;; "var x" -> "%x",  "const 42" -> "42"
(defn op-llvm [prefix val]
  (if (str-eq? prefix "var")
    (str-concat "%" val)
    val))

;; Reconstruct operand from prefix+val pair and convert to LLVM
(defn pair-to-llvm [words i]
  (op-llvm (get words i) (get words (+ i 1))))

;; "func name [p1 p2]:" -> "name"
(defn extract-func-name [line]
  (str-slice line 5 (- (str-index-of line "[") 1)))

;; "func name [p1 p2]:" -> "p1 p2"
(defn extract-params-str [line]
  (let [lb (+ (str-index-of line "[") 1)
        rb (str-index-of line "]")]
    (str-slice line lb rb)))

;; ---- LLVM header ----

(defn llvm-header []
  (let [lines (vector)]
    (do (lines-push lines "target triple = \"x86_64-unknown-linux-gnu\"")
        (lines-push lines "")
        (lines-push lines "declare i64 @bars_print_any_i64(i64)")
        (lines-push lines "declare i64 @bars_str_concat(i64, i64)")
        (lines-push lines "declare i64 @bars_str_get(i64, i64)")
        (lines-push lines "declare i64 @bars_str_slice(i64, i64, i64)")
        (lines-push lines "declare i64 @bars_vec_new()")
        (lines-push lines "declare i64 @bars_vec_push(i64, i64)")
        (lines-push lines "declare i64 @bars_vec_get(i64, i64)")
        (lines-push lines "declare i64 @bars_vec_count(i64)")
        (lines-push lines "declare i64 @bars_slurp(i64)")
        (lines-push lines "declare i64 @bars_spit(i64, i64)")
        (lines-push lines "declare i64 @bars_system(i64)")
        (lines-push lines "declare i64 @bars_args_count()")
        (lines-push lines "declare i64 @bars_args_get(i64)")
        (lines-push lines "declare i64 @bars_exit(i64)")
        (lines-push lines "")
        lines)))

;; ---- operator inlining ----
;; Returns 1 if fname is a known operator (output already pushed), else 0

(defn emit-cmp [output dest fname words si zext-suffix]
  (let [l (pair-to-llvm words si)
        r (pair-to-llvm words (+ si 2))
        tmp (str-concat dest zext-suffix)]
    (do (lines-push output (str-concat "  %" (str-concat tmp (str-concat " = icmp " (str-concat fname (str-concat " i64 " (str-concat l (str-concat ", " r))))))))
        (lines-push output (str-concat "  %" (str-concat dest (str-concat " = zext i1 %" (str-concat tmp " to i64"))))))))

(defn emit-binop [output dest llvm-op words si]
  (let [l (pair-to-llvm words si)
        r (pair-to-llvm words (+ si 2))]
    (lines-push output (str-concat "  %" (str-concat dest (str-concat " = " (str-concat llvm-op (str-concat " i64 " (str-concat l (str-concat ", " r))))))))))

(defn inline-op [output dest fname words si n]
  (if (str-eq? fname "+")  (do (emit-binop output dest "add" words si) 1)
  (if (str-eq? fname "-")  (do (emit-binop output dest "sub" words si) 1)
  (if (str-eq? fname "*")  (do (emit-binop output dest "mul" words si) 1)
  (if (str-eq? fname "/")  (do (emit-binop output dest "sdiv" words si) 1)
  (if (str-eq? fname "%")  (do (emit-binop output dest "srem" words si) 1)
  (if (str-eq? fname "=")  (do (emit-cmp output dest "eq" words si "_c") 1)
  (if (str-eq? fname "!=") (do (emit-cmp output dest "ne" words si "_n") 1)
  (if (str-eq? fname "<")  (do (emit-cmp output dest "slt" words si "_l") 1)
  (if (str-eq? fname ">")  (do (emit-cmp output dest "sgt" words si "_g") 1)
  (if (str-eq? fname "<=") (do (emit-cmp output dest "sle" words si "_le") 1)
  (if (str-eq? fname ">=") (do (emit-cmp output dest "sge" words si "_ge") 1)
  (if (str-eq? fname "not")
    (let [a (pair-to-llvm words si)
          tmp (str-concat dest "_not")]
      (do (lines-push output (str-concat "  %" (str-concat tmp (str-concat " = icmp eq i64 " (str-concat a ", 0")))))
          (lines-push output (str-concat "  %" (str-concat dest (str-concat " = zext i1 %" (str-concat tmp " to i64")))))
          1))
  0
  )))))))))))))

;; ---- emit one HIR instruction -> LLVM IR lines ----

(defn emit-instr [output words]
  (let [cmd (get words 0) n (count words)]
    ;; assign dest var/const val  ->  words: ["assign" dest prefix val]
    (if (str-eq? cmd "assign")
      (let [dest (get words 1)
            llvm-val (pair-to-llvm words 2)]
        (lines-push output (str-concat "  %" (str-concat dest (str-concat " = add i64 " (str-concat llvm-val ", 0"))))))
    ;; call dest fname [var/const arg ...]
    (if (str-eq? cmd "call")
      (let [dest (get words 1)
            fname (get words 2)
            handled (inline-op output dest fname words 3 n)]
        (if (= handled 1) output
          (if (<= n 3)
            (lines-push output (str-concat "  %" (str-concat dest (str-concat " = call i64 @" (str-concat fname "()")))))
            (let [arglist (loop [i 3 acc ""]
                            (if (>= i n) acc
                              (let [a (pair-to-llvm words i)]
                                (if (= i 3)
                                  (recur (+ i 2) (str-concat "i64 " a))
                                  (recur (+ i 2) (str-concat acc (str-concat ", i64 " a)))))))]
              (lines-push output (str-concat "  %" (str-concat dest (str-concat " = call i64 @" (str-concat fname (str-concat "(" (str-concat arglist ")")))))))))))))
    ;; branch var/const cond then_lbl else_lbl  ->  words: ["branch" prefix val lbl1 lbl2]
    (if (str-eq? cmd "branch")
      (let [c (pair-to-llvm words 1)
            then-lbl (get words 3)
            else-lbl (get words 4)
            tmp (str-concat then-lbl "_c")]
        (do (lines-push output (str-concat "  %" (str-concat tmp (str-concat " = trunc i64 " (str-concat c " to i1")))))
            (lines-push output (str-concat "  br i1 %" (str-concat tmp (str-concat ", label %" (str-concat then-lbl (str-concat ", label %" else-lbl))))))))
    ;; return var/const val  ->  words: ["return" prefix val]
    (if (str-eq? cmd "return")
      (let [llvm-val (pair-to-llvm words 1)]
        (lines-push output (str-concat "  ret i64 " llvm-val)))
    ;; stringlit dest content...  ->  placeholder
    (if (str-eq? cmd "stringlit")
      (let [dest (get words 1)]
        (do (lines-push output (str-concat "  ; stringlit " dest))
            (lines-push output (str-concat "  %" (str-concat dest " = add i64 0, 0")))))
    output
    )))))

;; ---- main line processing ----

(defn process-line [output line in-func]
  (if (< (count line) 1) [output in-func]
  ;; -- function def: "func name [params]:"
  (if (str-starts-with? line "func ")
    (let [output (if (= in-func 1) (lines-push output "}") output)
          name (extract-func-name line)
          params (split-words (extract-params-str line))
          nparams (count params)]
      (if (= nparams 0)
        [(lines-push output (str-concat "define i64 @" (str-concat name "() {"))) 1]
        (let [plist (loop [i 0 acc ""]
                      (if (>= i nparams) acc
                        (if (= i 0)
                          (recur (+ i 1) (str-concat "i64 %" (get params i)))
                          (recur (+ i 1) (str-concat acc (str-concat ", i64 %" (get params i)))))))]
          [(lines-push output (str-concat "define i64 @" (str-concat name (str-concat "(" (str-concat plist ") {"))))) 1])))
  ;; -- indented lines --
  (if (str-starts-with? line "  ")
    (if (str-starts-with? line "    ")
      ;; 4+ spaces = instruction
      [(emit-instr output (split-words (trim-left line))) in-func]
      ;; 2 spaces = label
      [(lines-push output (str-slice line 2 (count line))) in-func])
    ;; 0 spaces, not func -> skip
    [output in-func]))))

;; ---- pipeline ----

(defn hir-to-llvm [hir-lines]
  (let [n (count hir-lines)]
    (loop [i 0 output (llvm-header) in-func 0]
      (if (>= i n)
        (if (= in-func 1) (lines-push output "}") output)
        (let [line (get hir-lines i)
              res (process-line output line in-func)]
          (recur (+ i 1) (get res 0) (get res 1)))))))

(defn compile-llvm [hir-lines out-path]
  (let [ll-lines (hir-to-llvm hir-lines)
        n (count ll-lines)]
    (loop [i 0 text ""]
      (if (>= i n)
        (let [ll-path (str-concat out-path ".ll")]
          (do (spit ll-path text)
              0))
        (recur (+ i 1) (str-concat (str-concat text (get ll-lines i)) "\n"))))))
