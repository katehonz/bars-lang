;; Bars QBE Codegen — Stage 3
;; Converts line-oriented HIR to QBE SSA IR


(defn sanitize-name [name]
  (let [n (str-count name)]
    (loop [i 0 acc ""]
      (if (>= i n) acc
        (let [c (str-get name i)]
          (recur (+ i 1)
                 (str-concat acc
                   (if (= c 45) "_"
                     (if (= c 63) "_"
                       (if (= c 33) "_"
                         (if (= c 60) "_lt"
                           (if (= c 62) "_gt"
                             (str-slice name i (+ i 1))))))))))))))

(defn int-str [n]
  (let [d "0123456789"]
    (if (< n 0) (str-concat "-" (int-str (- 0 n)))
      (if (< n 10) (str-slice d n (+ n 1))
        (str-concat (int-str (/ n 10)) (str-slice d (% n 10) (+ (% n 10) 1)))))))

(defn str-eq? [a b]
  (if (!= (str-count a) (str-count b))
    false
    (= (str-starts-with? a b) 1)))

(defn split-line [line]
  (let [n (str-count line)
        result (vector)]
    (loop [i 0 start 0 in-word false]
      (if (>= i n)
        (if in-word
          (do (push result (str-slice line start n))
              result)
          result)
        (let [c (str-get line i)]
          (if (= c 32)
            (if in-word
              (do (push result (str-slice line start i))
                  (recur (+ i 1) (+ i 1) false))
              (recur (+ i 1) start false))
            (if in-word
              (recur (+ i 1) start true)
              (recur (+ i 1) i true))))))))

(defn qbe-op [op]
  (let [n (str-count op)
        c (str-get op 0)]
    (if (= n 1)
      (cond
        (= c 43) "add"
        (= c 45) "sub"
        (= c 42) "mul"
        (= c 47) "div"
        (= c 37) "rem"
        (= c 60) "csltl"
        (= c 61) "ceql"
        (= c 62) "csgtl"
        :else "")
      (if (= n 2)
        (let [c2 (str-get op 1)]
          (if (= c 33)
            (if (= c2 61) "cnel" "")
            (if (= c 60)
              (if (= c2 61) "cslel" "")
              (if (= c 62)
                (if (= c2 61) "csgel" "")
                ""))))
        ""))))

(defn is-builtin? [op]
  (not (str-eq? (qbe-op op) "")))

(defn emit-arg-val [val]
  (if (str-eq? val "true") "1"
    (if (str-eq? val "false") "0"
      (if (str-eq? val "nil") "0"
        val))))

(defn emit-arg [arg]
  (let [parts (split-line arg)]
    (if (= (count parts) 2)
      (if (str-eq? (get parts 0) "const")
        (emit-arg-val (get parts 1))
        (str-concat "%" (sanitize-name (get parts 1))))
      "")))

(defn emit-arg-call [arg]
  (let [parts (split-line arg)]
    (if (= (count parts) 2)
      (if (str-eq? (get parts 0) "const")
        (str-concat "l " (get parts 1))
        (str-concat "l %" (get parts 1)))
      "")))

(defn emit-args [args i]
  (let [n (count args)]
    (if (>= i n) ""
      (if (= i 0)
        (str-concat (emit-arg (get args i)) (emit-args args (+ i 1)))
        (str-concat ", " (str-concat (emit-arg (get args i)) (emit-args args (+ i 1))))))))

(defn emit-func-header [line]
  (let [parts (split-line line)
        name (get parts 1)
        bracket-idx (str-index-of line "[")
        close-idx (str-index-of line "]")]
    (if (= bracket-idx -1)
      (str-concat "export function l $" (str-concat (sanitize-name name) "() {"))
      (let [params-str (str-slice line (+ bracket-idx 1) close-idx)
            params (split-line params-str)]
        (str-concat "export function l $" (str-concat (sanitize-name name) (str-concat "(" (str-concat (emit-func-params params 0) ") {"))))))))

(defn emit-func-params [params i]
  (let [n (count params)]
    (if (>= i n) ""
      (if (= i 0)
        (str-concat "l %" (str-concat (get params i) (emit-func-params params (+ i 1))))
        (str-concat ", l %" (str-concat (get params i) (emit-func-params params (+ i 1))))))))

(defn emit-assign [dest val-type val]
  (let [prefix (str-concat "  %" dest)]
    (if (str-eq? val-type "const")
      (str-concat prefix (str-concat " =l copy " val))
      (str-concat prefix (str-concat " =l copy %" val)))))

(defn emit-builtin-call [dest fname lhs rhs]
  (let [op-str (qbe-op fname)
        prefix (str-concat "  %" (str-concat dest " =l "))
        mid (str-concat op-str (str-concat " " lhs))
        suffix (str-concat ", " rhs)]
    (str-concat prefix (str-concat mid suffix))))

(defn emit-call-args [args i]
  (if (>= i (count args))
    ""
    (if (= i 0)
      (str-concat (emit-arg-call (get args i)) (emit-call-args args (+ i 1)))
      (str-concat ", " (str-concat (emit-arg-call (get args i)) (emit-call-args args (+ i 1)))))))
(defn emit-call [dest fname parts]
  (let [args (vector)]
    (loop [i 3]
      (if (>= (+ i 1) (count parts)) 0
        (do (push args (str-concat (get parts i) (str-concat " " (get parts (+ i 1)))))
            (recur (+ i 2)))))
    (let [prefix (str-concat "  %" (str-concat dest " =l call $"))
        mid (str-concat (sanitize-name fname) "(")
        suffix (str-concat (emit-call-args args 0) ")")]
    (str-concat prefix (str-concat mid suffix)))))

(defn emit-branch [cond then-lbl else-lbl]
  (let [prefix (str-concat "  jnz " cond)
        mid (str-concat ", @" then-lbl)
        suffix (str-concat ", @" else-lbl)]
    (str-concat prefix (str-concat mid suffix))))

(defn emit-return [val-type val]
  (if (str-eq? val-type "const")
    (str-concat "  ret " (emit-arg-val val))
    (str-concat "  ret %" (sanitize-name val))))

(defn emit-println [dest parts]
  (if (> (count parts) 3)
    (let [arg (emit-arg-call (str-concat (get parts 3) (str-concat " " (get parts 4))))]
      (str-concat "  %" (str-concat dest (str-concat " =l call $bars_print_any_i64(" (str-concat arg ")")))))
    (str-concat "  %" (str-concat dest " =l call $bars_print_newline()"))))

(defn emit-instr [line]
  (let [parts (split-line line)]
    (let [cmd (get parts 0)]
      (if (str-eq? cmd "assign")
        (emit-assign (get parts 1) (get parts 2) (get parts 3))
        (if (str-eq? cmd "call")
          (let [dest (get parts 1)
                fname (get parts 2)]
            (if (str-eq? fname "println")
              (emit-println dest parts)
              (if (is-builtin? fname)
                (emit-builtin-call dest fname
                  (emit-arg (str-concat (get parts 3) (str-concat " " (get parts 4))))
                  (emit-arg (str-concat (get parts 5) (str-concat " " (get parts 6)))))
                (emit-call dest fname parts))))
          (if (str-eq? cmd "branch")
            (emit-branch
              (emit-arg (str-concat (get parts 1) (str-concat " " (get parts 2))))
              (get parts 3)
              (get parts 4))
            (if (str-eq? cmd "return")
              (emit-return (get parts 1) (get parts 2))
              "")))))))

(defn append-vec [dst src]
  (let [n (count src)]
    (loop [i 0]
      (if (>= i n) dst
        (do (push dst (get src i))
            (recur (+ i 1)))))))

(defn str-starts-with-2? [s prefix]
  (let [plen (str-count prefix)]
    (if (< (str-count s) plen) false
      (str-eq? (str-slice s 0 plen) prefix))))

(defn hir-to-qbe [hir-lines]
  (let [result (vector)
        n (count hir-lines)
        in-func false
        str-counter 0]
    (loop [i 0 in-func false str-counter str-counter str-data (vector) block-ended false]
      (if (>= i n)
        (do (if in-func (push result "}") 0)
            (append-vec result str-data)
            result)
        (let [line (str-trim (get hir-lines i))]
          (if (= (str-get line 0) 102)
            (let [_ (if in-func (push result "}") 0)
                  _ (append-vec result str-data)
                  header (emit-func-header line)
                  _ (push result header)]
              (recur (+ i 1) true str-counter (vector) false))
            (if block-ended
              (let [last-ch (str-get line (- (count line) 1))]
                (if (= last-ch 58)
                  (let [lbl (str-slice line 0 (- (count line) 1))]
                    (do (push result (str-concat "@" lbl))
                        (recur (+ i 1) in-func str-counter str-data false)))
                  (recur (+ i 1) in-func str-counter str-data block-ended)))
              (let [parts (split-line line)
                    cmd (get parts 0)]
                (if (str-eq? cmd "stringlit")
                  (let [label (str-concat "str_" (int-str str-counter))
                        dest (sanitize-name (get parts 1))
                        content (get parts 2)]
                    (do (push str-data (str-concat "data $" (str-concat label (str-concat " = { b \"" (str-concat content "\", b 0 }")))))
                        (push result (str-concat "  %" (str-concat dest (str-concat " =l call $bars_string_new(l $" (str-concat label ")"))))))
                        (recur (+ i 1) in-func (+ str-counter 1) str-data false)))
                  (if (= (str-get line (- (count line) 1)) 58)
                    (let [lbl (str-slice line 0 (- (count line) 1))]
                      (do (push result (str-concat "@" lbl))
                          (recur (+ i 1) in-func str-counter str-data false)))
                    (let [instr (emit-instr line)]
                      (if (str-eq? instr "")
                        (recur (+ i 1) in-func str-counter str-data block-ended)
                        (let [fname (if (> (count parts) 2) (get parts 2) "")
                              is-println (if (str-eq? cmd "call") (str-eq? fname "println") false)]
                          (do (push result instr)
                              (if is-println
                                (do (push result "  call $bars_print_newline()")
                                    (recur (+ i 1) in-func str-counter str-data (str-starts-with-2? instr "  ret ")))
                                (recur (+ i 1) in-func str-counter str-data (str-starts-with-2? instr "  ret "))))))))))))))))

(defn print-lines [lines]
  (let [n (count lines)]
    (loop [i 0]
      (if (>= i n) 0
        (do (println (get lines i))
            (recur (+ i 1)))))))

(defn main []
  (println "=== QBE Codegen ===")
  (let [hir (vector)
        _ (push hir "func add [x y]:")
        _ (push hir "  entry_0:")
        _ (push hir "    call t0 + var x var y")
        _ (push hir "    return var t0")
        _ (push hir "func main []:")
        _ (push hir "  main_entry_0:")
        _ (push hir "    return const 0")]
    (print-lines (hir-to-qbe hir)))
  0)
