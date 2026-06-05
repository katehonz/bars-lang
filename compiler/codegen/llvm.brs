;; Bars LLVM Backend — Stage 7 of self-hosting
;; HIR → LLVM IR text (.ll format)

(defn str-eq? [a b]
  (if (!= (count a) (count b)) false
    (= (str-starts-with? a b) 1)))

(defn str-contains? [s sub]
  (!= (str-index-of s sub) -1))

(defn int-str [n]
  (let [d "0123456789"]
    (if (< n 0) (str-concat "-" (int-str (- 0 n)))
      (if (< n 10) (str-slice d n (+ n 1))
        (str-concat (int-str (/ n 10)) (str-slice d (% n 10) (+ (% n 10) 1)))))))

(defn extract-str [s prefix suf]
  (let [start (+ (str-index-of s prefix) (count prefix))
        end (str-index-of s suf)]
    (str-slice s start end)))

(defn op-to-llvm [op]
  (if (str-contains? op "Const(")
    (extract-str op "Const(" ")")
    (if (str-contains? op "Var(")
      (let [name (extract-str op "Var(\"" "\")")]
        (str-concat "%" name))
      op)))

(defn llvm-header []
  (let [lines (vector)]
    (do (push lines "target triple = \"x86_64-unknown-linux-gnu\"")
        (push lines "")
        (push lines "declare i64 @bars_print_any_i64(i64)")
        (push lines "declare i64 @bars_vec_new()")
        (push lines "declare i64 @bars_vec_push(i64, i64)")
        (push lines "declare i64 @bars_vec_get(i64, i64)")
        (push lines "declare i64 @bars_vec_count(i64)")
        (push lines "declare i64 @bars_str_concat(i64, i64)")
        (push lines "declare i64 @bars_str_get(i64, i64)")
        (push lines "declare i64 @bars_str_slice(i64, i64, i64)")
        (push lines "declare i64 @bars_system(i64)")
        (push lines "declare i64 @bars_slurp(i64)")
        (push lines "declare i64 @bars_spit(i64, i64)")
        (push lines "declare i64 @bars_args_count()")
        (push lines "declare i64 @bars_args_get(i64)")
        (push lines "declare i64 @bars_exit(i64)")
        (push lines "")
        lines)))

(defn process-line [output line]
  (cond
    (str-starts-with? line "func ")
    (let [name (extract-str line "func " ":")]
      (do (push output (str-concat "define i64 @" (str-concat name "() {")))
          (push output "entry:")
          output))
    (str-starts-with? line "    Assign")
    (let [dest (extract-str line "dest: \"" "\",")
          val-str (str-slice line (+ (str-index-of line "value: ") 7) (count line))
          llvm-val (op-to-llvm val-str)]
      (do (push output (str-concat "  %" (str-concat dest (str-concat " = add i64 " (str-concat llvm-val ", 0")))))
          output))
    (str-starts-with? line "    Call")
    (let [dest (extract-str line "dest: \"" "\",")
          func-start (+ (str-index-of line "func: \"") 7)
          func (str-slice line func-start (str-index-of line "\","))]
      (do (push output (str-concat "  %" (str-concat dest (str-concat " = call i64 @" (str-concat func "()")))))
          output))
    (str-starts-with? line "    Return")
    (let [val-str (str-slice line (+ (str-index-of line "Return(") 7) (- (count line) 1))
          llvm-val (op-to-llvm val-str)]
      (do (push output (str-concat "  ret i64 " llvm-val))
          (push output "}")
          (push output "")
          output))
    :else output))

(defn hir-to-llvm [hir-lines]
  (let [n (count hir-lines)]
    (loop [i 0 output (llvm-header)]
      (if (>= i n) output
        (recur (+ i 1) (process-line output (get hir-lines i)))))))

(defn compile-llvm [hir-lines out-path]
  (let [ll-lines (hir-to-llvm hir-lines)
        n (count ll-lines)]
    (loop [i 0 text ""]
      (if (>= i n)
        (let [ll-path (str-concat out-path ".ll")]
          (do (spit ll-path text)
              0))
        (recur (+ i 1) (str-concat (str-concat text (get ll-lines i)) "\n"))))))
