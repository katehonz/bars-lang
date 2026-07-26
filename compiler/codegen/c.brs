;; Bars C Backend — Phase 13.5
;; HIR text → C source (.c), then cc + runtime → binary.
;;
;; HIR:
;;   func name [params]:
;;     label:
;;       assign name var/const val
;;       call dest fname [var/const arg ...]
;;       branch var/const cond then else
;;       return var/const val
;;       jump label
;;       stringlit dest content...

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

;; Sanitize to C identifier (alnum + _).
(defn c-ident [s]
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
  (if (str-eq? fname "main") "_bars_main" (c-ident fname)))

(defn map-str-ops [fname]
  (if (str-eq? fname "str-concat") "bars_string_concat"
    (if (str-eq? fname "str-get") "bars_string_get"
      (if (str-eq? fname "str-slice") "bars_string_slice"
        (if (str-eq? fname "str-count") "bars_string_length"
          (if (str-eq? fname "str-starts-with?") "bars_string_starts_with"
            (if (str-eq? fname "str-index-of") "bars_string_index_of"
              "")))))))

(defn map-vec-ops [fname]
  (if (str-eq? fname "count") "bars_count_any_i64"
    (if (str-eq? fname "push") "bars_vector_push_i64"
      (if (str-eq? fname "pop") "bars_vector_pop_i64"
        (if (str-eq? fname "get") "bars_vector_get_i64"
          (if (str-eq? fname "vector") "bars_vector_new_i64"
            ""))))))

(defn map-map-ops [fname]
  (if (str-eq? fname "map") "bars_map_new_i64"
    (if (str-eq? fname "map-set") "bars_map_set_i64"
      (if (str-eq? fname "map-get") "bars_map_get_i64"
        (if (str-eq? fname "map-count") "bars_map_count_i64"
          "")))))

(defn map-io-ops [fname]
  (if (str-eq? fname "slurp") "bars_slurp"
    (if (str-eq? fname "spit") "bars_spit"
      (if (str-eq? fname "exit") "bars_exit"
        (if (str-eq? fname "args-count") "bars_args_count"
          (if (str-eq? fname "args-get") "bars_args_get"
            (if (str-eq? fname "bars_env_set") "bars_env_set"
              (if (str-eq? fname "bars_system") "bars_system"
                (if (str-eq? fname "bars_file_mtime") "bars_file_mtime"
                  (if (str-eq? fname "bars_sleep_ms") "bars_sleep_ms"
                    ""))))))))))

(defn map-fname [fname]
  (let [a (map-str-ops fname)]
    (if (> (count a) 0) a
      (let [b (map-vec-ops fname)]
        (if (> (count b) 0) b
          (let [c (map-map-ops fname)]
            (if (> (count c) 0) c
              (let [d (map-io-ops fname)]
                (if (> (count d) 0) d (map-user-fname fname))))))))))

(defn binop-c [fname]
  (if (str-eq? fname "+") "+"
    (if (str-eq? fname "-") "-"
      (if (str-eq? fname "*") "*"
        (if (str-eq? fname "/") "/"
          (if (str-eq? fname "%") "%"
            ""))))))

(defn cmp-c [fname]
  (if (str-eq? fname "=") "=="
    (if (str-eq? fname "!=") "!="
      (if (str-eq? fname "<") "<"
        (if (str-eq? fname ">") ">"
          (if (str-eq? fname "<=") "<="
            (if (str-eq? fname ">=") ">="
              "")))))))

(defn env-has? [env name]
  (let [n (count env)]
    (loop [i 0]
      (if (>= i n) false
        (if (str-eq? (get env i) name) true
          (recur (+ i 1)))))))

(defn env-add [env name]
  (if (env-has? env name) env
    (do (push env name) env)))

;; Operand → C expression string (const or variable name).
(defn resolve-op [prefix val]
  (if (str-eq? prefix "var") (c-ident val) val))

(defn pair-op [words i]
  (resolve-op (get words i) (get words (+ i 1))))

(defn extract-func-name [line]
  (str-slice line 5 (- (str-index-of line "[") 1)))

(defn extract-params-str [line]
  (let [lb (+ (str-index-of line "[") 1)
        rb (str-index-of line "]")]
    (str-slice line lb rb)))

(defn stringlit-dest [trimmed]
  (let [rest (str-slice trimmed 10 (count trimmed))
        sp (str-index-of rest " ")]
    (if (< sp 0) rest (str-slice rest 0 sp))))

(defn stringlit-content [trimmed]
  (let [rest (str-slice trimmed 10 (count trimmed))
        sp (str-index-of rest " ")]
    (if (< sp 0) "" (str-slice rest (+ sp 1) (count rest)))))

;; Escape for C string literal (minimal: backslash, quote, newline, tab).
(defn c-escape-char [c]
  (if (= c 92) "\\\\"
    (if (= c 34) "\\\""
      (if (= c 10) "\\n"
        (if (= c 9) "\\t"
          0)))))

(defn c-escape [s]
  (let [n (count s)]
    (loop [i 0 acc ""]
      (if (>= i n) acc
        (let [c (str-get s i)
              esc (c-escape-char c)]
          (if (= esc 0)
            (recur (+ i 1) (str-concat acc (str-slice s i (+ i 1))))
            (recur (+ i 1) (str-concat acc esc))))))))

(defn ensure-decl [output env dest]
  (let [d (c-ident dest)]
    (if (env-has? env d)
      [output env]
      (do (lines-push output (str-concat "  int64_t " (str-concat d ";")))
          [output (env-add env d)]))))

(defn emit-assign [output words env]
  (let [dest (c-ident (get words 1))
        raw (if (>= (count words) 4) (get words 3) (get words 2))]
    (if (if (str-eq? raw "<dead>") true (str-eq? raw "<done>"))
      [output env]
      (let [val (pair-op words 2)
            r (ensure-decl output env dest)
            o1 (get r 0)
            e1 (get r 1)]
        (do (lines-push o1 (str-concat "  " (str-concat dest (str-concat " = " (str-concat val ";")))))
            [o1 e1])))))

;; Emit args; cast each through (void*)(uintptr_t) so pointer APIs accept i64.
(defn emit-call-args [words n]
  (loop [i 3 acc ""]
    (if (>= i n) acc
      (let [a (pair-op words i)
            cast (str-concat "(void*)(uintptr_t)(" (str-concat a ")"))]
        (if (= i 3)
          (recur (+ i 2) cast)
          (recur (+ i 2) (str-concat acc (str-concat ", " cast))))))))

(defn emit-binop-c [output dest op words env]
  (let [l (pair-op words 3)
        r (pair-op words 5)
        er (ensure-decl output env dest)
        o1 (get er 0)
        e1 (get er 1)
        stmt (str-concat "  " (str-concat dest (str-concat " = " (str-concat l (str-concat " " (str-concat op (str-concat " " (str-concat r ";"))))))))]
    (do (lines-push o1 stmt)
        [o1 e1])))

(defn emit-cmp-c [output dest op words env]
  (let [l (pair-op words 3)
        r (pair-op words 5)
        er (ensure-decl output env dest)
        o1 (get er 0)
        e1 (get er 1)
        stmt (str-concat "  " (str-concat dest (str-concat " = (" (str-concat l (str-concat " " (str-concat op (str-concat " " (str-concat r ") ? 1 : 0;"))))))))]
    (do (lines-push o1 stmt)
        [o1 e1])))

(defn emit-call [output words n env]
  (let [dest (c-ident (get words 1))
        fname (get words 2)
        bop (binop-c fname)
        cop (cmp-c fname)]
    (if (> (count bop) 0)
      (emit-binop-c output dest bop words env)
      (if (> (count cop) 0)
        (emit-cmp-c output dest cop words env)
        (if (str-eq? fname "not")
          (let [a (pair-op words 3)
                er (ensure-decl output env dest)
                o1 (get er 0)
                e1 (get er 1)]
            (do (lines-push o1 (str-concat "  " (str-concat dest (str-concat " = (" (str-concat a " == 0) ? 1 : 0;")))))
                [o1 e1]))
          (if (str-eq? fname "println")
            (let [arg (if (<= n 3) "0" (pair-op words 3))
                  er (ensure-decl output env dest)
                  o1 (get er 0)
                  e1 (get er 1)]
              ;; bars_print_* return void — assign 0 to dest
              (do (lines-push o1 (str-concat "  bars_print_any_i64(" (str-concat arg ");")))
                  (lines-push o1 "  bars_print_newline();")
                  (lines-push o1 (str-concat "  " (str-concat dest " = 0;")))
                  [o1 e1]))
            (let [mapped (map-fname fname)
                  args (if (<= n 3) "" (emit-call-args words n))
                  er (ensure-decl output env dest)
                  o1 (get er 0)
                  e1 (get er 1)
                  is-void (if (str-eq? fname "map-set") true
                            (if (str-eq? fname "spit") true false))]
              (if is-void
                (do (lines-push o1 (str-concat "  " (str-concat mapped (str-concat "(" (str-concat args ");")))))
                    (lines-push o1 (str-concat "  " (str-concat dest " = 0;")))
                    [o1 e1])
                (do (lines-push o1
                      (str-concat "  " (str-concat dest
                        (str-concat " = (int64_t)(uintptr_t)"
                          (str-concat mapped (str-concat "(" (str-concat args ");")))))))
                    [o1 e1])))))))))

(defn emit-branch [output words]
  (let [c (pair-op words 1)
        then-lbl (c-ident (get words 3))
        else-lbl (c-ident (get words 4))]
    (do (lines-push output
          (str-concat "  if (" (str-concat c
            (str-concat ") goto " (str-concat then-lbl
              (str-concat "; else goto " (str-concat else-lbl ";")))))))
        output)))

(defn emit-return [output words]
  (let [n (count words)
        val (if (>= n 3) (get words 2) "")]
    (if (if (str-eq? val "<dead>") true (str-eq? val "<done>"))
      output
      (let [v (pair-op words 1)]
        (do (lines-push output (str-concat "  return " (str-concat v ";")))
            output)))))

(defn emit-jump [output words]
  (let [lbl (c-ident (get words 1))]
    (do (lines-push output (str-concat "  goto " (str-concat lbl ";")))
        output)))

(defn emit-stringlit [output trimmed env]
  (let [dest (c-ident (stringlit-dest trimmed))
        content (stringlit-content trimmed)
        esc (c-escape content)
        er (ensure-decl output env dest)
        o1 (get er 0)
        e1 (get er 1)]
    (do (lines-push o1
          (str-concat "  " (str-concat dest
            (str-concat " = (int64_t)(uintptr_t)bars_string_new(\""
              (str-concat esc "\");")))))
        [o1 e1])))

(defn emit-instr [output words trimmed env]
  (let [cmd (get words 0) n (count words)]
    (if (str-eq? cmd "assign")
      (emit-assign output words env)
      (if (str-eq? cmd "call")
        (emit-call output words n env)
        (if (str-eq? cmd "branch")
          [(emit-branch output words) env]
          (if (str-eq? cmd "return")
            [(emit-return output words) env]
            (if (str-eq? cmd "jump")
              [(emit-jump output words) env]
              (if (str-eq? cmd "stringlit")
                (emit-stringlit output trimmed env)
                [output env]))))))))

(defn c-header []
  (let [lines (vector)]
    (do (lines-push lines "/* Generated by Bars C backend */")
        (lines-push lines "#include <stdint.h>")
        (lines-push lines "#include <stddef.h>")
        (lines-push lines "#include \"runtime/bars_runtime.h\"")
        (lines-push lines "")
        lines)))

(defn c-main-wrapper []
  (let [lines (vector)]
    (do (lines-push lines "")
        (lines-push lines "int main(int argc, char **argv) {")
        (lines-push lines "  bars_set_args(argc, argv);")
        (lines-push lines "  return (int)_bars_main();")
        (lines-push lines "}")
        lines)))

(defn process-func [body line]
  (let [name (map-user-fname (extract-func-name line))
        params (split-words (extract-params-str line))
        nparams (count params)
        ;; Seed env with params so we never redeclare them as locals.
        env (vector)]
    (do (loop [i 0]
          (if (>= i nparams) 0
            (do (push env (c-ident (get params i)))
                (recur (+ i 1)))))
        (if (= nparams 0)
          (do (lines-push body (str-concat "static int64_t " (str-concat name "(void) {")))
              [body env])
          (let [plist (loop [i 0 acc ""]
                        (if (>= i nparams) acc
                          (let [p (c-ident (get params i))]
                            (if (= i 0)
                              (recur (+ i 1) (str-concat "int64_t " p))
                              (recur (+ i 1) (str-concat acc (str-concat ", int64_t " p)))))))]
            (do (lines-push body
                  (str-concat "static int64_t " (str-concat name
                    (str-concat "(" (str-concat plist ") {")))))
                [body env]))))))

(defn process-line [body line env]
  (if (< (count line) 1)
    [body env]
    (if (str-starts-with? line "func ")
      (process-func body line)
      (if (str-starts-with? line "    ")
        (let [trimmed (trim-left line)
              words (split-words trimmed)
              res (emit-instr body words trimmed env)]
          [(get res 0) (get res 1)])
        (if (str-starts-with? line "  ")
          ;; label:  entry_0:
          (let [lbl (trim-left line)]
            (do (lines-push body (str-concat (c-ident (str-slice lbl 0 (- (count lbl) 1))) ":"))
                ;; empty statement so label before decl is valid if needed
                (lines-push body "  ;")
                [body env]))
          [body env])))))

(defn append-vec [dst src]
  (let [n (count src)]
    (loop [i 0]
      (if (>= i n) dst
        (do (push dst (get src i))
            (recur (+ i 1)))))))

(defn hir-to-c [hir-lines]
  (let [n (count hir-lines)]
    (loop [i 0 body (vector) in-func 0 env (vector) all (vector)]
      (if (>= i n)
        (let [flushed (if (= in-func 1)
                        (do (lines-push body "}")
                            (append-vec all body)
                            all)
                        all)
              out (c-header)
              wrap (c-main-wrapper)]
          (do (append-vec out flushed)
              (append-vec out wrap)
              out))
        (let [line (get hir-lines i)]
          (if (str-starts-with? line "func ")
            (let [flushed (if (= in-func 1)
                            (do (lines-push body "}")
                                (append-vec all body)
                                all)
                            all)
                  res (process-line (vector) line (vector))]
              (recur (+ i 1) (get res 0) 1 (get res 1) flushed))
            (let [res (process-line body line env)]
              (recur (+ i 1) (get res 0) in-func (get res 1) all))))))))

(defn join-lines [lines]
  (let [n (count lines)]
    (loop [i 0 text ""]
      (if (>= i n) text
        (recur (+ i 1) (str-concat (str-concat text (get lines i)) "\n"))))))

(defn compile-c [hir-lines out-path]
  (let [c-lines (hir-to-c hir-lines)
        text (join-lines c-lines)
        c-path (str-concat out-path ".c")]
    (do (spit c-path text)
        0)))
