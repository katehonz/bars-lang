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

(defn int-str [n] (str-from-i64 n))

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
;; C reserved words — a Bars identifier named e.g. `default` must not
;; reach the C compiler unrenamed.
(defn c-keyword? [s]
  (let [kws ["auto" "break" "case" "char" "const" "continue" "default" "do"
             "double" "else" "enum" "extern" "float" "for" "goto" "if" "int"
             "long" "register" "return" "short" "signed" "sizeof" "static"
             "struct" "switch" "typedef" "union" "unsigned" "void" "volatile"
             "while"]
        n (count kws)]
    (loop [i 0]
      (if (>= i n) false
        (if (str-eq? s (get kws i)) true
          (recur (+ i 1)))))))

(defn c-ident [s]
  (let [n (count s)]
    (loop [i 0 acc ""]
      (if (>= i n)
        (if (= (count acc) 0) "_id"
          (if (c-keyword? acc) (str-concat acc "_") acc))
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
            (if (str-eq? fname "str-ends-with?") "bars_string_ends_with"
              (if (str-eq? fname "str-index-of") "bars_string_index_of"
                (if (str-eq? fname "str-replace") "bars_string_replace"
                  (if (str-eq? fname "str-trim") "bars_string_trim"
                    (if (str-eq? fname "str-substring") "bars_string_substring"
                      (if (str-eq? fname "str-split") "bars_string_split"
                        (if (str-eq? fname "str-join") "bars_string_join"
                          (if (str-eq? fname "code-char") "bars_code_char"
                            (if (str-eq? fname "str-from-i64") "bars_string_from_i64"
                              "")))))))))))))))

(defn map-vec-ops [fname]
  (if (str-eq? fname "count") "bars_count_any_i64"
    (if (str-eq? fname "push") "bars_vector_push_i64"
      (if (str-eq? fname "pop") "bars_vector_pop_i64"
        (if (str-eq? fname "get") "bars_vector_get_i64"
          (if (str-eq? fname "first") "bars_vector_first_i64"
            (if (str-eq? fname "last") "bars_vector_last_i64"
              (if (str-eq? fname "vector") "bars_vector_new_i64"
                (if (str-eq? fname "vector-clone") "bars_vector_clone_i64"
                  (if (str-eq? fname "conj") "bars_vector_conj_i64"
                    (if (str-eq? fname "v-assoc") "bars_vector_assoc_i64"
                      (if (str-eq? fname "vector-set") "bars_vector_set_i64"
                        (if (str-eq? fname "flatten") "bars_flatten_i64"
                          (if (str-eq? fname "abs") "bars_abs_i64"
                      (if (str-eq? fname "v-pop") "bars_vector_pop_copy_i64"
                        "")))))))))))))))

(defn map-map-ops [fname]
  (if (str-eq? fname "map") "bars_map_new_i64"
    (if (str-eq? fname "map-set") "bars_map_set_i64"
      (if (str-eq? fname "map-get") "bars_map_get_i64"
        (if (str-eq? fname "map-count") "bars_map_count_i64"
          (if (str-eq? fname "map-contains?") "bars_map_contains_i64"
            (if (str-eq? fname "map-delete") "bars_map_delete_i64"
            (if (str-eq? fname "map-keys") "bars_map_keys_i64"
              (if (str-eq? fname "map-values") "bars_map_values_i64"
                (if (str-eq? fname "map-clone") "bars_map_clone_i64"
                  (if (str-eq? fname "map-assoc") "bars_map_assoc_i64"
                    (if (str-eq? fname "set") "bars_set_new_i64"
                      (if (str-eq? fname "set-add") "bars_set_add_i64"
                        (if (str-eq? fname "set-contains?") "bars_set_contains_i64"
                          (if (str-eq? fname "set-count") "bars_set_count_i64"
                            "")))))))))))))))

(defn map-io-ops [fname]
  (if (str-eq? fname "slurp") "bars_slurp"
    (if (str-eq? fname "spit") "bars_spit"
      (if (str-eq? fname "exit") "bars_exit"
        (if (str-eq? fname "args-count") "bars_args_count"
          (if (str-eq? fname "args-get") "bars_args_get"
            (if (str-eq? fname "identity") "bars_identity"
              (if (str-eq? fname "bars_env_is_set") "bars_env_is_set"
                (if (str-eq? fname "bars_getenv") "bars_getenv"
                  (if (str-eq? fname "bars_system") "bars_system"
                    ""))))))))))

(defn map-file-ops [fname]
  (if (str-eq? fname "bars_file_mtime") "bars_file_mtime"
    (if (str-eq? fname "bars_file_exists") "bars_file_exists"
      (if (str-eq? fname "bars_file_delete") "bars_file_delete"
        (if (str-eq? fname "bars_file_append") "bars_file_append"
          (if (str-eq? fname "bars_sleep_ms") "bars_sleep_ms"
            ""))))))

(defn map-time-rand-ops [fname]
  (if (str-eq? fname "bars_time_unix") "bars_time_unix"
    (if (str-eq? fname "bars_time_ms") "bars_time_ms"
      (if (str-eq? fname "bars_srand") "bars_srand"
        (if (str-eq? fname "bars_rand") "bars_rand"
          (if (str-eq? fname "bars_re_is_match") "bars_re_is_match"
            (if (str-eq? fname "bars_re_find") "bars_re_find"
              (if (str-eq? fname "str-from-i64") "bars_string_from_i64"
                (if (str-eq? fname "code-char") "bars_code_char"
                  "")))))))))

(defn map-net-ops [fname]
  (if (str-eq? fname "bars_tcp_connect") "bars_tcp_connect"
    (if (str-eq? fname "bars_tcp_listen") "bars_tcp_listen"
      (if (str-eq? fname "bars_tcp_accept") "bars_tcp_accept"
        (if (str-eq? fname "bars_tcp_send") "bars_tcp_send"
          (if (str-eq? fname "bars_tcp_recv") "bars_tcp_recv"
            (if (str-eq? fname "bars_tcp_close") "bars_tcp_close"
              "")))))))

(defn map-icall-ops [fname]
  (if (str-eq? fname "bars_icall0") "bars_icall0"
    (if (str-eq? fname "bars_icall1") "bars_icall1"
      (if (str-eq? fname "bars_icall2") "bars_icall2"
        (if (str-eq? fname "bars_icall3") "bars_icall3"
          (if (str-eq? fname "bars_icall4") "bars_icall4"
            (if (str-eq? fname "bars_icall5") "bars_icall5"
              (if (str-eq? fname "bars_icall6") "bars_icall6"
                (if (str-eq? fname "bars_icall7") "bars_icall7"
                  (if (str-eq? fname "bars_icall8") "bars_icall8"
                    (if (str-eq? fname "bars_apply") "bars_apply"
                      (if (str-eq? fname "apply") "bars_apply"
                        (if (str-eq? fname "bars_apply_join") "bars_apply_join"
                          (if (str-eq? fname "bars_is_vector_i64") "bars_is_vector_i64"
                            ""))))))))))))))

(defn map-fname [fname]
  (let [a (map-str-ops fname)]
    (if (> (count a) 0) a
      (let [b (map-vec-ops fname)]
        (if (> (count b) 0) b
          (let [c (map-map-ops fname)]
            (if (> (count c) 0) c
              (let [d (map-io-ops fname)]
                (if (> (count d) 0) d
                  (let [e (map-file-ops fname)]
                    (if (> (count e) 0) e
                      (let [f (map-time-rand-ops fname)]
                        (if (> (count f) 0) f
                          (let [g (map-net-ops fname)]
                            (if (> (count g) 0) g
                              (let [h (map-icall-ops fname)]
                                (if (> (count h) 0) h (map-user-fname fname))))))))))))))))))

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

;; ---- Top-level def globals (Phase 17.5) ----
;; HIR "global <name>" lines declare file-scope storage `static int64_t <c-ident>;`.
;; Function envs are seeded with "__g__:<name>" markers so assigns to the
;; name skip the local declaration and write the global directly. Reads of
;; `var <name>` need no change — the C identifier is the same as a local's.

(defn gmark [name]
  (str-concat "__g__:" name))

;; Pre-scan HIR for "global <name>" decl lines → vector of names.
(defn scan-globals [hir-lines]
  (let [n (count hir-lines) out (vector)]
    (loop [i 0]
      (if (>= i n) out
        (let [line (get hir-lines i)]
          (if (str-starts-with? line "global ")
            (do (push out (str-slice line 7 (count line)))
                (recur (+ i 1)))
            (recur (+ i 1))))))))

(defn gmarks-of [globs]
  (let [n (count globs) out (vector)]
    (loop [i 0]
      (if (>= i n) out
        (do (push out (gmark (get globs i)))
            (recur (+ i 1)))))))

;; Emit `static int64_t <c-ident name>;` file-scope storage lines.
(defn emit-gstorage [out globs]
  (let [n (count globs)]
    (loop [i 0]
      (if (>= i n) out
        (do (lines-push out
              (str-concat "static int64_t " (str-concat (c-ident (get globs i)) ";")))
            (recur (+ i 1)))))))

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
      (if (env-has? env (gmark (get words 1)))
        ;; Global cell: plain assignment, no local declaration.
        (let [val (pair-op words 2)]
          (do (lines-push output (str-concat "  " (str-concat dest (str-concat " = " (str-concat val ";")))))
              [output env]))
        (let [val (pair-op words 2)
            r (ensure-decl output env dest)
            o1 (get r 0)
            e1 (get r 1)]
        (do (lines-push o1 (str-concat "  " (str-concat dest (str-concat " = " (str-concat val ";")))))
            [o1 e1]))))))

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
          (if (if (str-eq? fname "min") true (str-eq? fname "max"))
            (let [a (pair-op words 3)
                  b (pair-op words 5)
                  er (ensure-decl output env dest)
                  o1 (get er 0)
                  e1 (get er 1)
                  op (if (str-eq? fname "min") "<" ">")]
              (do (lines-push o1
                    (str-concat "  " (str-concat dest
                      (str-concat " = ((" (str-concat a (str-concat " " (str-concat op
                        (str-concat " " (str-concat b (str-concat ") ? " (str-concat a (str-concat " : " (str-concat b ");")))))))))))))
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
                  ;; Runtime fns that return void: call as statement, dest = 0.
                  is-void (if (str-eq? fname "map-set") true
                            (if (str-eq? fname "set-add") true
                              (if (str-eq? fname "spit") true
                                (if (str-eq? fname "exit") true false))))]
              (if is-void
                (do (lines-push o1 (str-concat "  " (str-concat mapped (str-concat "(" (str-concat args ");")))))
                    (lines-push o1 (str-concat "  " (str-concat dest " = 0;")))
                    [o1 e1])
                (do (lines-push o1
                      (str-concat "  " (str-concat dest
                        (str-concat " = (int64_t)(uintptr_t)"
                          (str-concat mapped (str-concat "(" (str-concat args ");")))))))
                    [o1 e1]))))))))))

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

(defn emit-alloc-c [output words env]
  (let [dest (c-ident (get words 1))
        size (get words 2)
        er (ensure-decl output env dest)
        o1 (get er 0)
        e1 (get er 1)]
    (do (lines-push o1 (str-concat "  " (str-concat dest
          (str-concat " = (int64_t)(uintptr_t)bars_alloc(" (str-concat size ");")))))
        [o1 e1])))

(defn emit-fieldload-c [output words env]
  (let [dest (c-ident (get words 1))
        base (pair-op words 2)
        woff (get words 4)
        er (ensure-decl output env dest)
        o1 (get er 0)
        e1 (get er 1)]
    (do (lines-push o1 (str-concat "  " (str-concat dest
          (str-concat " = ((int64_t*)(uintptr_t)(" (str-concat base
            (str-concat "))[" (str-concat woff "];")))))))
        [o1 e1])))

(defn emit-fieldstore-c [output words env]
  (let [base (pair-op words 1)
        woff (get words 3)
        val (pair-op words 4)]
    (do (lines-push output (str-concat "  ((int64_t*)(uintptr_t)("
          (str-concat base (str-concat "))[" (str-concat woff
            (str-concat "] = " (str-concat val ";")))))))
        [output env])))

(defn emit-funcref-c [output words env]
  (let [dest (c-ident (get words 1))
        fname (map-user-fname (get words 2))
        er (ensure-decl output env dest)
        o1 (get er 0)
        e1 (get er 1)]
    (do (lines-push o1
          (str-concat "  " (str-concat dest
            (str-concat " = (int64_t)(uintptr_t)&" (str-concat (c-ident fname) ";")))))
        [o1 e1])))

(defn emit-icall-c [output words n env]
  (let [dest (c-ident (get words 1))
        callee (pair-op words 2)
        nargs (/ (- n 4) 2)
        er (ensure-decl output env dest)
        o1 (get er 0)
        e1 (get er 1)
        args (loop [i 4 acc ""]
               (if (>= i n) acc
                 (let [a (pair-op words i)]
                   (if (= i 4)
                     (recur (+ i 2) a)
                     (recur (+ i 2) (str-concat acc (str-concat ", " a)))))))
        cast (if (= nargs 0)
               "int64_t(*)(void)"
               (loop [i 0 acc "int64_t(*)("]
                 (if (>= i nargs)
                   (str-concat acc ")")
                   (if (= i 0)
                     (recur (+ i 1) (str-concat acc "int64_t"))
                     (recur (+ i 1) (str-concat acc ", int64_t"))))))
        line (if (= nargs 0)
               (str-concat "  " (str-concat dest
                 (str-concat " = ((" (str-concat cast (str-concat ")(uintptr_t)("
                   (str-concat callee "))();"))))))
               (str-concat "  " (str-concat dest
                 (str-concat " = ((" (str-concat cast (str-concat ")(uintptr_t)("
                   (str-concat callee (str-concat "))(" (str-concat args ");")))))))))]
    (do (lines-push o1 line)
        [o1 e1])))

(defn emit-instr [output words trimmed env]
  (let [cmd (get words 0) n (count words)]
    (if (str-eq? cmd "assign")
      (emit-assign output words env)
      (if (str-eq? cmd "call")
        (emit-call output words n env)
        (if (str-eq? cmd "icall")
          (emit-icall-c output words n env)
          (if (str-eq? cmd "funcref")
            (emit-funcref-c output words env)
            (if (str-eq? cmd "branch")
              [(emit-branch output words) env]
              (if (str-eq? cmd "return")
                [(emit-return output words) env]
                (if (str-eq? cmd "jump")
                  [(emit-jump output words) env]
                  (if (str-eq? cmd "stringlit")
                    (emit-stringlit output trimmed env)
                    (if (str-eq? cmd "alloc")
                      (emit-alloc-c output words env)
                      (if (str-eq? cmd "fieldload")
                        (emit-fieldload-c output words env)
                        (if (str-eq? cmd "fieldstore")
                          (emit-fieldstore-c output words env)
                          [output env])))))))))))))

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
        (lines-push lines "  (void)__bars_init_globals();")
        (lines-push lines "  return (int)_bars_main();")
        (lines-push lines "}")
        lines)))

(defn process-func [body line seed]
  (let [name (map-user-fname (extract-func-name line))
        params (split-words (extract-params-str line))
        nparams (count params)
        ;; Seed env with global markers + params so we never redeclare them.
        env seed]
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
      (process-func body line env)
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

;; Forward declaration for a HIR `func` line: `static int64_t name(int64_t, …);`
;; Lambdas are lifted before user functions, so bodies may call fns defined
;; later in the file — without prototypes C99 implicit decls become errors.
(defn func-proto [line]
  (let [name (map-user-fname (extract-func-name line))
        params (split-words (extract-params-str line))
        nparams (count params)]
    (if (= nparams 0)
      (str-concat "static int64_t " (str-concat name "(void);"))
      (let [plist (loop [i 0 acc ""]
                    (if (>= i nparams) acc
                      (if (= i 0)
                        (recur (+ i 1) "int64_t")
                        (recur (+ i 1) (str-concat acc ", int64_t")))))]
        (str-concat "static int64_t " (str-concat name
          (str-concat "(" (str-concat plist ");"))))))))

(defn append-vec [dst src]
  (let [n (count src)]
    (loop [i 0]
      (if (>= i n) dst
        (do (push dst (get src i))
            (recur (+ i 1)))))))

(defn hir-to-c [hir-lines]
  (let [n (count hir-lines)
        globs (scan-globals hir-lines)
        marks (gmarks-of globs)]
    (loop [i 0 body (vector) in-func 0 env (vector) all (vector) protos (vector)]
      (if (>= i n)
        (let [flushed (if (= in-func 1)
                        (do (lines-push body "}")
                            (append-vec all body)
                            all)
                        all)
              out (c-header)
              wrap (c-main-wrapper)]
          (do (emit-gstorage out globs)
              (if (> (count globs) 0) (lines-push out "") 0)
              (append-vec out protos)
              (if (> (count protos) 0) (lines-push out "") 0)
              (append-vec out flushed)
              (append-vec out wrap)
              out))
        (let [line (get hir-lines i)]
          (if (str-starts-with? line "func ")
            (let [flushed (if (= in-func 1)
                            (do (lines-push body "}")
                                (append-vec all body)
                                all)
                            all)
                  res (process-line (vector) line (append-vec (vector) marks))]
              (do (push protos (func-proto line))
                  (recur (+ i 1) (get res 0) 1 (get res 1) flushed protos)))
            (let [res (process-line body line env)]
              (recur (+ i 1) (get res 0) in-func (get res 1) all protos))))))))

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
