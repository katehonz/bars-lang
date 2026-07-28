;; Bars LLVM Backend — Stage 7/10 of self-hosting
;; HIR text → LLVM IR (.ll). Bare HIR temps; quoted LLVM ids for safety.
;;
;; HIR:
;;   func name [params]:
;;     label:
;;       assign name var/const val
;;       call dest fname [var/const arg ...]
;;       branch var/const cond then else
;;       return var/const val
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

;; ---- LLVM identifiers: always quoted (handles -, /, ?, etc.) ----

(defn llvm-local [name]
  (str-concat "%\"" (str-concat name "\"")))

(defn llvm-global [name]
  (str-concat "@\"" (str-concat name "\"")))

;; ---- Mutable locals via alloca (needed for loop reassignments) ----
;; env = vector of names that have an alloca (name.addr)
;; When reading a slotted name: emit load into ld_N
;; When assigning: ensure alloca exists, then store

(defn env-has? [env name]
  (let [n (count env)]
    (loop [i 0]
      (if (>= i n) false
        (if (str-eq? (get env i) name) true
          (recur (+ i 1)))))))

(defn env-add [env name]
  (if (env-has? env name) env
    (do (push env name) env)))

(defn addr-name [name]
  (str-concat name ".addr"))

;; ---- Top-level def globals (Phase 17.5) ----
;; HIR "global <name>" lines declare storage @"__g_<name>".
;; Function envs are seeded with "__g__:<name>" markers so reads/writes
;; of the name resolve to the global cell instead of an alloca.

(defn gmark [name]
  (str-concat "__g__:" name))

(defn is-gmark? [s]
  (str-starts-with? s "__g__:"))

(defn llvm-gstorage [name]
  (str-concat "@\"__g_" (str-concat name "\"")))

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

;; Emit @"__g_<name>" = global i64 0 storage lines.
(defn emit-gstorage [out globs]
  (let [n (count globs)]
    (loop [i 0]
      (if (>= i n) out
        (do (lines-push out
              (str-concat (llvm-gstorage (get globs i)) " = global i64 0"))
            (recur (+ i 1)))))))

;; Record that name needs an alloca (emitted later at function entry).
;; Returns [output env] — does not emit yet (avoids non-dominating allocas).
(defn ensure-alloca [output env name]
  (if (env-has? env name) [output env]
    [output (env-add env name)]))

;; Emit all pending allocas (call after entry label / at start of body)
;; Global markers never get allocas.
(defn emit-allocas [output env]
  (let [n (count env)]
    (loop [i 0]
      (if (>= i n) output
        (if (is-gmark? (get env i))
          (recur (+ i 1))
          (do (lines-push output
                (str-concat "  " (str-concat (llvm-local (addr-name (get env i))) " = alloca i64")))
              (recur (+ i 1))))))))

;; Resolve operand: returns [llvm-str output reg]
;; For slotted vars, emits a load. Globals load from @"__g_<name>".
(defn resolve-operand [prefix val output env reg]
  (if (str-eq? prefix "var")
    (if (env-has? env (gmark val))
      (let [tmp (str-concat "ld" (int-str reg))]
        (do (lines-push output
              (str-concat "  " (str-concat (llvm-local tmp)
                (str-concat " = load i64, i64* " (llvm-gstorage val)))))
            [(llvm-local tmp) output (+ reg 1)]))
      (if (env-has? env val)
        (let [tmp (str-concat "ld" (int-str reg))]
          (do (lines-push output
                (str-concat "  " (str-concat (llvm-local tmp)
                  (str-concat " = load i64, i64* " (llvm-local (addr-name val))))))
              [(llvm-local tmp) output (+ reg 1)]))
        [(llvm-local val) output reg]))
    [val output reg]))

(defn pair-resolve [words i output env reg]
  (resolve-operand (get words i) (get words (+ i 1)) output env reg))

(defn extract-func-name [line]
  (str-slice line 5 (- (str-index-of line "[") 1)))

(defn extract-params-str [line]
  (let [lb (+ (str-index-of line "[") 1)
        rb (str-index-of line "]")]
    (str-slice line lb rb)))

;; ---- stringlit ----

(defn stringlit-dest [trimmed]
  (let [rest (str-slice trimmed 10 (count trimmed))
        sp (str-index-of rest " ")]
    (if (< sp 0) rest (str-slice rest 0 sp))))

(defn stringlit-content [trimmed]
  (let [rest (str-slice trimmed 10 (count trimmed))
        sp (str-index-of rest " ")]
    (if (< sp 0) "" (str-slice rest (+ sp 1) (count rest)))))

(defn llvm-escape [s]
  (let [n (count s)]
    (loop [i 0 acc ""]
      (if (>= i n) (str-concat acc "\\00")
        (let [c (str-get s i)
              ch (str-slice s i (+ i 1))]
          (if (= c 34) (recur (+ i 1) (str-concat acc "\\22"))
            (if (= c 92) (recur (+ i 1) (str-concat acc "\\5C"))
              (if (= c 10) (recur (+ i 1) (str-concat acc "\\0A"))
                (if (= c 9) (recur (+ i 1) (str-concat acc "\\09"))
                  (recur (+ i 1) (str-concat acc ch)))))))))))

;; ---- header with correct C runtime names ----

(defn llvm-header [triple]
  (let [t (if (> (count triple) 0) triple "x86_64-unknown-linux-gnu")
        lines (vector)]
    (do (lines-push lines (str-concat "target triple = \"" (str-concat t "\"")))
        (lines-push lines "")
        (lines-push lines "declare i64 @bars_string_new(i64)")
        (lines-push lines "declare i64 @bars_print_any_i64(i64)")
        (lines-push lines "declare i64 @bars_print_newline()")
        (lines-push lines "declare i64 @bars_print_i64(i64)")
        (lines-push lines "declare i64 @bars_string_concat(i64, i64)")
        (lines-push lines "declare i64 @bars_string_get(i64, i64)")
        (lines-push lines "declare i64 @bars_string_slice(i64, i64, i64)")
        (lines-push lines "declare i64 @bars_string_length(i64)")
        (lines-push lines "declare i64 @bars_string_starts_with(i64, i64)")
        (lines-push lines "declare i64 @bars_string_ends_with(i64, i64)")
        (lines-push lines "declare i64 @bars_string_index_of(i64, i64)")
        (lines-push lines "declare i64 @bars_string_trim(i64)")
        (lines-push lines "declare i64 @bars_string_substring(i64, i64, i64)")
        (lines-push lines "declare i64 @bars_string_split(i64, i64)")
        (lines-push lines "declare i64 @bars_string_join(i64, i64)")
        (lines-push lines "declare i64 @bars_vector_new_i64()")
        (lines-push lines "declare i64 @bars_vector_push_i64(i64, i64)")
        (lines-push lines "declare i64 @bars_vector_pop_i64(i64)")
        (lines-push lines "declare i64 @bars_vector_get_i64(i64, i64)")
        (lines-push lines "declare i64 @bars_vector_count_i64(i64)")
        (lines-push lines "declare i64 @bars_count_any_i64(i64)")
        (lines-push lines "declare i64 @bars_map_new_i64()")
        (lines-push lines "declare i64 @bars_map_set_i64(i64, i64, i64)")
        (lines-push lines "declare i64 @bars_map_get_i64(i64, i64)")
        (lines-push lines "declare i64 @bars_map_count_i64(i64)")
        (lines-push lines "declare i64 @bars_slurp(i64)")
        (lines-push lines "declare i64 @bars_spit(i64, i64)")
        (lines-push lines "declare i64 @bars_system(i64)")
        (lines-push lines "declare i64 @bars_args_count()")
        (lines-push lines "declare i64 @bars_args_get(i64)")
        (lines-push lines "declare i64 @bars_exit(i64)")
        (lines-push lines "declare i64 @bars_env_is_set(i64)")
        (lines-push lines "declare i64 @bars_getenv(i64)")
        (lines-push lines "declare i64 @bars_file_mtime(i64)")
        (lines-push lines "declare i64 @bars_sleep_ms(i64)")
        (lines-push lines "declare i64 @bars_file_exists(i64)")
        (lines-push lines "declare i64 @bars_file_delete(i64)")
        (lines-push lines "declare i64 @bars_file_append(i64, i64)")
        (lines-push lines "declare i64 @bars_time_unix()")
        (lines-push lines "declare i64 @bars_time_ms()")
        (lines-push lines "declare i64 @bars_srand(i64)")
        (lines-push lines "declare i64 @bars_rand()")
        (lines-push lines "declare i64 @bars_re_is_match(i64, i64)")
        (lines-push lines "declare i64 @bars_re_find(i64, i64)")
        (lines-push lines "declare i64 @bars_string_from_i64(i64)")
        (lines-push lines "declare i64 @bars_code_char(i64)")
        (lines-push lines "declare i64 @bars_tcp_connect(i64, i64)")
        (lines-push lines "declare i64 @bars_tcp_listen(i64)")
        (lines-push lines "declare i64 @bars_tcp_accept(i64)")
        (lines-push lines "declare i64 @bars_tcp_send(i64, i64)")
        (lines-push lines "declare i64 @bars_tcp_recv(i64, i64)")
        (lines-push lines "declare i64 @bars_tcp_close(i64)")
        (lines-push lines "declare i64 @bars_sha256(i64)")
        (lines-push lines "declare void @bars_set_args(i32, i8**)")
        (lines-push lines "declare i8* @bars_alloc(i64)")
        (lines-push lines "")
        lines)))

;; Bars main is emitted as _bars_main; C main sets argv then calls it.
(defn map-user-fname [fname]
  (if (str-eq? fname "main") "_bars_main" fname))

;; ---- map Bars names → C runtime (flat cond-style via helpers) ----
;; Avoids 15-deep if nesting / paren piles.

(defn map-str-ops [fname]
  (if (str-eq? fname "str-concat") "bars_string_concat"
    (if (str-eq? fname "str-get") "bars_string_get"
      (if (str-eq? fname "str-slice") "bars_string_slice"
        (if (str-eq? fname "str-count") "bars_string_length"
          (if (str-eq? fname "str-starts-with?") "bars_string_starts_with"
            (if (str-eq? fname "str-ends-with?") "bars_string_ends_with"
              (if (str-eq? fname "str-index-of") "bars_string_index_of"
                (if (str-eq? fname "str-trim") "bars_string_trim"
                  (if (str-eq? fname "str-substring") "bars_string_substring"
                    (if (str-eq? fname "str-split") "bars_string_split"
                      (if (str-eq? fname "str-join") "bars_string_join"
                        (if (str-eq? fname "code-char") "bars_code_char"
                          (if (str-eq? fname "str-from-i64") "bars_string_from_i64"
                            ""))))))))))))))

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
            (if (str-eq? fname "println") "bars_print_any_i64"
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
                            (if (> (count g) 0) g fname)))))))))))))))

;; ---- operators (small groups = fewer closing parens) ----

(defn binop-code [fname]
  (if (str-eq? fname "+") "add"
    (if (str-eq? fname "-") "sub"
      (if (str-eq? fname "*") "mul"
        (if (str-eq? fname "/") "sdiv"
          (if (str-eq? fname "%") "srem"
            ""))))))

(defn cmp-code [fname]
  (if (str-eq? fname "=") "eq"
    (if (str-eq? fname "!=") "ne"
      (if (str-eq? fname "<") "slt"
        (if (str-eq? fname ">") "sgt"
          (if (str-eq? fname "<=") "sle"
            (if (str-eq? fname ">=") "sge"
              "")))))))

(defn cmp-suffix [fname]
  (if (str-eq? fname "=") "_c"
    (if (str-eq? fname "!=") "_n"
      (if (str-eq? fname "<") "_l"
        (if (str-eq? fname ">") "_g"
          (if (str-eq? fname "<=") "_le"
            (if (str-eq? fname ">=") "_ge"
              "_x")))))))


;; ---- operators with alloca loads ----
;; Returns [output reg]

(defn emit-binop [output dest llvm-op words si env reg]
  (let [r1 (pair-resolve words si output env reg)
        l (get r1 0)
        o1 (get r1 1)
        g1 (get r1 2)
        r2 (pair-resolve words (+ si 2) o1 env g1)
        r (get r2 0)
        o2 (get r2 1)
        g2 (get r2 2)]
    (do (lines-push o2
          (str-concat "  " (str-concat (llvm-local dest)
            (str-concat " = " (str-concat llvm-op
              (str-concat " i64 " (str-concat l (str-concat ", " r))))))))
        [o2 g2])))

(defn emit-cmp [output dest pred words si zext-suffix env reg]
  (let [r1 (pair-resolve words si output env reg)
        l (get r1 0)
        o1 (get r1 1)
        g1 (get r1 2)
        r2 (pair-resolve words (+ si 2) o1 env g1)
        r (get r2 0)
        o2 (get r2 1)
        g2 (get r2 2)
        tmp (str-concat dest zext-suffix)]
    (do (lines-push o2
          (str-concat "  " (str-concat (llvm-local tmp)
            (str-concat " = icmp " (str-concat pred
              (str-concat " i64 " (str-concat l (str-concat ", " r))))))))
        (lines-push o2
          (str-concat "  " (str-concat (llvm-local dest)
            (str-concat " = zext i1 " (str-concat (llvm-local tmp) " to i64")))))
        [o2 g2])))

;; Returns [output reg handled]
(defn inline-op [output dest fname words si n env reg]
  (let [bop (binop-code fname)]
    (if (> (count bop) 0)
      (let [r (emit-binop output dest bop words si env reg)]
        [(get r 0) (get r 1) 1])
      (let [cop (cmp-code fname)]
        (if (> (count cop) 0)
          (let [r (emit-cmp output dest cop words si (cmp-suffix fname) env reg)]
            [(get r 0) (get r 1) 1])
          (if (str-eq? fname "not")
            (let [r1 (pair-resolve words si output env reg)
                  a (get r1 0)
                  o1 (get r1 1)
                  g1 (get r1 2)
                  tmp (str-concat dest "_not")]
              (do (lines-push o1
                    (str-concat "  " (str-concat (llvm-local tmp)
                      (str-concat " = icmp eq i64 " (str-concat a ", 0")))))
                  (lines-push o1
                    (str-concat "  " (str-concat (llvm-local dest)
                      (str-concat " = zext i1 " (str-concat (llvm-local tmp) " to i64")))))
                  [o1 g1 1]))
            [output reg 0]))))))

;; Returns [output env reg]
(defn emit-assign [output words env reg]
  (let [dest (get words 1)
        raw (if (>= (count words) 4) (get words 3) (get words 2))]
    ;; Skip stores of HIR dead markers (unreachable paths)
    (if (str-eq? raw "<dead>")
      [output env reg]
      (if (str-eq? raw "<done>")
        [output env reg]
        (if (env-has? env (gmark dest))
          ;; Global cell: store directly, no alloca.
          (let [r1 (pair-resolve words 2 output env reg)
                val (get r1 0)
                o1 (get r1 1)
                g1 (get r1 2)]
            (do (lines-push o1
                  (str-concat "  store i64 " (str-concat val
                    (str-concat ", i64* " (llvm-gstorage dest)))))
                [o1 env g1]))
          (let [r1 (pair-resolve words 2 output env reg)
                val (get r1 0)
                o1 (get r1 1)
                g1 (get r1 2)
                r2 (ensure-alloca o1 env dest)
                o2 (get r2 0)
                env2 (get r2 1)]
            (do (lines-push o2
                  (str-concat "  store i64 " (str-concat val
                    (str-concat ", i64* " (llvm-local (addr-name dest))))))
                [o2 env2 g1])))))))

;; Returns [arglist-str output reg]
(defn emit-call-args [words n output env reg]
  (loop [i 3 acc "" ocur output rcur reg]
    (if (>= i n) [acc ocur rcur]
      (let [r (pair-resolve words i ocur env rcur)
            a (get r 0)
            o2 (get r 1)
            g2 (get r 2)]
        (if (= i 3)
          (recur (+ i 2) (str-concat "i64 " a) o2 g2)
          (recur (+ i 2) (str-concat acc (str-concat ", i64 " a)) o2 g2))))))

;; Multi-arg str-concat → left-fold of binary bars_string_concat (like Cranelift).
;; HIR pairs: call dest str-concat var/const a var/const b var/const c ...
;; Returns [output reg] or 0 if not multi-arg str-concat.
(defn emit-str-concat-n [output dest words n env reg]
  (if (not (str-eq? (get words 2) "str-concat")) 0
    ;; n = 3 + 2*nargs; nargs >= 3 → n >= 9
    (if (< n 9) 0
      (let [r0 (pair-resolve words 3 output env reg)
            a0 (get r0 0)
            o0 (get r0 1)
            g0 (get r0 2)
            r1 (pair-resolve words 5 o0 env g0)
            a1 (get r1 0)
            o1 (get r1 1)
            g1 (get r1 2)
            t0 (str-concat dest "_sc0")]
        (do (lines-push o1
              (str-concat "  " (str-concat (llvm-local t0)
                (str-concat " = call i64 @bars_string_concat(i64 "
                  (str-concat a0 (str-concat ", i64 " (str-concat a1 ")")))))))
            (loop [i 7 k 1 ocur o1 rcur g1 acc-name t0]
              (if (>= i n)
                (do (lines-push ocur
                      (str-concat "  " (str-concat (llvm-local dest)
                        (str-concat " = add i64 " (str-concat (llvm-local acc-name) ", 0")))))
                    [ocur rcur])
                (let [r (pair-resolve words i ocur env rcur)
                      a (get r 0)
                      o2 (get r 1)
                      g2 (get r 2)
                      tn (str-concat dest (str-concat "_sc" (int-str k)))]
                  (do (lines-push o2
                        (str-concat "  " (str-concat (llvm-local tn)
                          (str-concat " = call i64 @bars_string_concat(i64 "
                            (str-concat (llvm-local acc-name)
                              (str-concat ", i64 " (str-concat a ")")))))))
                      (recur (+ i 2) (+ k 1) o2 g2 tn))))))))))

;; Returns [output reg]
(defn emit-call [output words n env reg]
  (let [dest (get words 1)
        fname (get words 2)
        ir (inline-op output dest fname words 3 n env reg)
        o1 (get ir 0)
        g1 (get ir 1)
        handled (get ir 2)]
    (if (= handled 1)
      [o1 g1]
      ;; multi-arg str-concat (n-ary → binary fold)
      (let [scn (emit-str-concat-n o1 dest words n env g1)]
        (if (!= scn 0) scn
      ;; str-concat with one arg is identity (host/cranelift does this too)
      ;; HIR: call dest str-concat var x  → n = 5
      (if (if (str-eq? fname "str-concat") (= n 5) false)
        (let [r (pair-resolve words 3 o1 env g1)
              a (get r 0)
              o2 (get r 1)
              g2 (get r 2)]
          (do (lines-push o2
                (str-concat "  " (str-concat (llvm-local dest)
                  (str-concat " = add i64 " (str-concat a ", 0")))))
              [o2 g2]))
        (if (str-eq? fname "println")
          (let [r (if (<= n 3)
                    ["0" o1 g1]
                    (pair-resolve words 3 o1 env g1))
                arg (get r 0)
                o2 (get r 1)
                g2 (get r 2)]
            (do (lines-push o2
                  (str-concat "  " (str-concat (llvm-local dest)
                    (str-concat " = call i64 @bars_print_any_i64(i64 " (str-concat arg ")")))))
                (lines-push o2 "  call i64 @bars_print_newline()")
                [o2 g2]))
          (let [mapped (map-fname fname)
                gname (llvm-global mapped)]
            (if (<= n 3)
              (do (lines-push o1
                    (str-concat "  " (str-concat (llvm-local dest)
                      (str-concat " = call i64 " (str-concat gname "()")))))
                  [o1 g1])
              (let [ra (emit-call-args words n o1 env g1)
                    arglist (get ra 0)
                    o2 (get ra 1)
                    g2 (get ra 2)
                    call (str-concat " = call i64 "
                            (str-concat gname
                              (str-concat "(" (str-concat arglist ")"))))]
                (do (lines-push o2
                      (str-concat "  " (str-concat (llvm-local dest) call)))
                    [o2 g2])))))))))))

;; Returns [output reg]
(defn emit-branch [output words env reg]
  (let [r (pair-resolve words 1 output env reg)
        c (get r 0)
        o1 (get r 1)
        g1 (get r 2)
        then-lbl (get words 3)
        else-lbl (get words 4)
        tmp (str-concat then-lbl "_c")]
    (do (lines-push o1
          (str-concat "  " (str-concat (llvm-local tmp)
            (str-concat " = trunc i64 " (str-concat c " to i1")))))
        (lines-push o1
          (str-concat "  br i1 " (str-concat (llvm-local tmp)
            (str-concat ", label %" (str-concat then-lbl
              (str-concat ", label %" else-lbl))))))
        [o1 g1])))

;; Returns [output reg]
(defn emit-return [output words env reg]
  (let [n (count words)
        val (if (>= n 3) (get words 2) "")]
    (if (str-eq? val "<dead>") [output reg]
      (if (str-eq? val "<done>") [output reg]
        (let [r (pair-resolve words 1 output env reg)
              v (get r 0)
              o1 (get r 1)
              g1 (get r 2)]
          (do (lines-push o1 (str-concat "  ret i64 " v))
              [o1 g1]))))))

(defn emit-jump [output words]
  (let [lbl (get words 1)]
    (lines-push output (str-concat "  br label %" lbl))))

;; Returns [output strs str-cnt env reg]
(defn emit-stringlit [output trimmed strs str-cnt env reg]
  (let [dest (stringlit-dest trimmed)
        content (stringlit-content trimmed)
        escaped (llvm-escape content)
        len (+ (count content) 1)
        gname (str-concat "str_" (int-str str-cnt))
        gdef (str-concat "@" (str-concat gname
                (str-concat " = private unnamed_addr constant ["
                  (str-concat (int-str len)
                    (str-concat " x i8] c\"" (str-concat escaped "\""))))))
        ptrtmp (str-concat dest "_p")
        inttmp (str-concat dest "_i")]
    (do (lines-push strs gdef)
        (lines-push output
          (str-concat "  " (str-concat (llvm-local ptrtmp)
            (str-concat " = getelementptr [" (str-concat (int-str len)
              (str-concat " x i8], [" (str-concat (int-str len)
                (str-concat " x i8]* @" (str-concat gname ", i64 0, i64 0")))))))))
        (lines-push output
          (str-concat "  " (str-concat (llvm-local inttmp)
            (str-concat " = ptrtoint i8* " (str-concat (llvm-local ptrtmp) " to i64")))))
        (lines-push output
          (str-concat "  " (str-concat (llvm-local dest)
            (str-concat " = call i64 @bars_string_new(i64 "
              (str-concat (llvm-local inttmp) ")")))))
        [output strs (+ str-cnt 1) env reg])))

;; Returns [output strs str-cnt env reg]
(defn emit-alloc [output words env reg]
  (let [dest (get words 1)
        size (get words 2)
        tmp (str-concat dest "_p")
        r2 (ensure-alloca output env dest)
        o2 (get r2 0)
        env2 (get r2 1)]
    (do (lines-push o2
          (str-concat "  " (str-concat (llvm-local tmp)
            (str-concat " = call i8* @bars_alloc(i64 " size ")"))))
        (lines-push o2
          (str-concat "  " (str-concat (llvm-local dest)
            (str-concat " = ptrtoint i8* " (str-concat (llvm-local tmp) " to i64")))))
        (let [r3 (emit-assign-inline o2 dest (llvm-local dest) env2)]
          [(get r3 0) env2 reg]))))  ;; alloc doesn't read vars, reg unchanged

(defn emit-assign-inline [output dest val-llvm env]
  (let [r2 (ensure-alloca output env dest)
        o2 (get r2 0)
        env2 (get r2 1)]
    (do (lines-push o2
          (str-concat "  store i64 " (str-concat val-llvm
            (str-concat ", i64* " (llvm-local (addr-name dest))))))
        [o2 env2])))

(defn emit-fieldload [output words env reg]
  (let [dest (get words 1)
        r1 (pair-resolve words 2 output env reg)
        base (get r1 0)
        o1 (get r1 1)
        g1 (get r1 2)
        woff (get words 4)
        tmp-p (str-concat dest "_p")
        tmp-g (str-concat dest "_g")
        r2 (ensure-alloca o1 env dest)
        o2 (get r2 0)
        env2 (get r2 1)]
    (do (lines-push o2
          (str-concat "  " (str-concat (llvm-local tmp-p)
            (str-concat " = inttoptr i64 " (str-concat base " to i64*")))))
        (lines-push o2
          (str-concat "  " (str-concat (llvm-local tmp-g)
            (str-concat " = getelementptr i64, i64* " (str-concat (llvm-local tmp-p)
              (str-concat ", i64 " woff))))))
        (lines-push o2
          (str-concat "  " (str-concat (llvm-local dest)
            (str-concat " = load i64, i64* " (llvm-local tmp-g)))))
        (let [r3 (emit-assign-inline o2 dest (llvm-local dest) env2)]
          [(get r3 0) env2 g1]))))

(defn emit-fieldstore [output words env reg]
  (let [r1 (pair-resolve words 1 output env reg)
        base (get r1 0)
        o1 (get r1 1)
        g1 (get r1 2)
        woff (get words 3)
        r2 (pair-resolve words 4 o1 env g1)
        val (get r2 0)
        o2 (get r2 1)
        g2 (get r2 2)
        base-name (get words 2)
        tmp-p (str-concat base-name (str-concat "_fp" (int-str reg)))
        tmp-g (str-concat base-name (str-concat "_fg" (int-str reg)))]
    (do (lines-push o2
          (str-concat "  " (str-concat (llvm-local tmp-p)
            (str-concat " = inttoptr i64 " (str-concat base " to i64*")))))
        (lines-push o2
          (str-concat "  " (str-concat (llvm-local tmp-g)
            (str-concat " = getelementptr i64, i64* " (str-concat (llvm-local tmp-p)
              (str-concat ", i64 " woff))))))
        (lines-push o2
          (str-concat "  store i64 " (str-concat val
            (str-concat ", i64* " (llvm-local tmp-g)))))
        [o2 env g2])))

;; Returns [output strs str-cnt env reg]
(defn emit-instr [output words trimmed strs str-cnt env reg]
  (let [cmd (get words 0) n (count words)]
    (if (str-eq? cmd "assign")
      (let [r (emit-assign output words env reg)]
        [(get r 0) strs str-cnt (get r 1) (get r 2)])
      (if (str-eq? cmd "call")
        (let [r (emit-call output words n env reg)]
          [(get r 0) strs str-cnt env (get r 1)])
        (if (str-eq? cmd "branch")
          (let [r (emit-branch output words env reg)]
            [(get r 0) strs str-cnt env (get r 1)])
          (if (str-eq? cmd "return")
            (let [r (emit-return output words env reg)]
              [(get r 0) strs str-cnt env (get r 1)])
            (if (str-eq? cmd "jump")
              [(emit-jump output words) strs str-cnt env reg]
              (if (str-eq? cmd "stringlit")
                (emit-stringlit output trimmed strs str-cnt env reg)
                (if (str-eq? cmd "alloc")
                  (let [r (emit-alloc output words env reg)]
                    [(get r 0) strs str-cnt (get r 1) (get r 2)])
                  (if (str-eq? cmd "fieldload")
                    (let [r (emit-fieldload output words env reg)]
                      [(get r 0) strs str-cnt (get r 1) (get r 2)])
                    (if (str-eq? cmd "fieldstore")
                      (let [r (emit-fieldstore output words env reg)]
                        [(get r 0) strs str-cnt (get r 1) (get r 2)])
                      [output strs str-cnt env reg])))))))))))

(defn process-func [body line in-func strs str-cnt seed]
  (let [body2 (if (= in-func 1) (lines-push body "}") body)
        name (map-user-fname (extract-func-name line))
        params (split-words (extract-params-str line))
        nparams (count params)
        gname (llvm-global name)
        empty seed]
    (if (= nparams 0)
      [(lines-push body2 (str-concat "define i64 " (str-concat gname "() {"))) 1 strs str-cnt empty 0]
      (let [plist (loop [i 0 acc ""]
                    (if (>= i nparams) acc
                      (if (= i 0)
                        (recur (+ i 1) (str-concat "i64 " (llvm-local (get params i))))
                        (recur (+ i 1) (str-concat acc
                          (str-concat ", i64 " (llvm-local (get params i))))))))]
        [(lines-push body2
           (str-concat "define i64 " (str-concat gname
             (str-concat "(" (str-concat plist ") {")))))
         1 strs str-cnt empty 0]))))

(defn process-line [body line in-func strs str-cnt env reg]
  (if (< (count line) 1)
    [body in-func strs str-cnt env reg]
    (if (str-starts-with? line "func ")
      (process-func body line in-func strs str-cnt env)
      (if (str-starts-with? line "    ")
        (let [trimmed (trim-left line)
              words (split-words trimmed)
              res (emit-instr body words trimmed strs str-cnt env reg)]
          [(get res 0) in-func (get res 1) (get res 2) (get res 3) (get res 4)])
        (if (str-starts-with? line "  ")
          [(lines-push body (str-slice line 2 (count line))) in-func strs str-cnt env reg]
          [body in-func strs str-cnt env reg])))))

(defn append-vec [dst src]
  (let [n (count src)]
    (loop [i 0]
      (if (>= i n) dst
        (do (push dst (get src i))
            (recur (+ i 1)))))))

(defn c-main-wrapper []
  (let [lines (vector)]
    (do (lines-push lines "")
        (lines-push lines "define i32 @main(i32 %argc, i8** %argv) {")
        (lines-push lines "  call void @bars_set_args(i32 %argc, i8** %argv)")
        (lines-push lines "  %ig = call i64 @\"__bars_init_globals\"()")
        (lines-push lines "  %r = call i64 @_bars_main()")
        (lines-push lines "  %r32 = trunc i64 %r to i32")
        (lines-push lines "  ret i32 %r32")
        (lines-push lines "}")
        lines)))

;; Inject allocas right after the first basic-block label (entry_N:)
;; Labels in body are stored without leading spaces (stripped by process-line).
(defn is-label-line? [line]
  (if (< (count line) 2) false
    (if (str-starts-with? line " ") false
      (if (str-starts-with? line "define ") false
        (if (str-starts-with? line "}") false
          (str-eq? (str-slice line (- (count line) 1) (count line)) ":"))))))

(defn inject-allocas-after-define [body env]
  (if (<= (count env) 0) body
    (let [n (count body)
          out (vector)]
      (loop [i 0 done 0]
        (if (>= i n) out
          (let [line (get body i)]
            (do (push out line)
                (if (if (= done 0) (is-label-line? line) false)
                  (do (loop [j 0]
                        (if (>= j (count env)) 0
                          (if (is-gmark? (get env j))
                            (recur (+ j 1))
                            (do (push out (str-concat "  " (str-concat (llvm-local (addr-name (get env j))) " = alloca i64")))
                                (recur (+ j 1))))))
                      (recur (+ i 1) 1))
                  (recur (+ i 1) done)))))))))

(defn hir-to-llvm [hir-lines]
  (hir-to-llvm-at hir-lines "x86_64-unknown-linux-gnu"))

(defn hir-to-llvm-at [hir-lines triple]
  (let [n (count hir-lines)
        globs (scan-globals hir-lines)
        marks (gmarks-of globs)]
    (loop [i 0 body (vector) in-func 0 strs (vector) str-cnt 0 env (vector) reg 0
           all-body (vector)]
      (if (>= i n)
        (let [body2 (if (= in-func 1)
                      (let [closed (lines-push body "}")
                            inj (inject-allocas-after-define closed env)]
                        (do (append-vec all-body inj) all-body))
                      all-body)
              out (llvm-header triple)
              wrap (c-main-wrapper)]
          (do (append-vec out strs)
              (if (> (count strs) 0) (lines-push out "") 0)
              (emit-gstorage out globs)
              (if (> (count globs) 0) (lines-push out "") 0)
              (append-vec out body2)
              (append-vec out wrap)
              out))
        (let [line (get hir-lines i)]
          (if (str-starts-with? line "func ")
            (let [flushed (if (= in-func 1)
                            (let [closed (lines-push body "}")
                                  inj (inject-allocas-after-define closed env)]
                              (do (append-vec all-body inj) all-body))
                            all-body)
                  res (process-line (vector) line 0 strs str-cnt (append-vec (vector) marks) 0)]
              (recur (+ i 1) (get res 0) (get res 1) (get res 2) (get res 3) (get res 4) (get res 5) flushed))
            (let [res (process-line body line in-func strs str-cnt env reg)]
              (recur (+ i 1) (get res 0) (get res 1) (get res 2) (get res 3) (get res 4) (get res 5) all-body))))))))

(defn join-lines [ll-lines]
  (let [n (count ll-lines)]
    (loop [i 0 text ""]
      (if (>= i n) text
        (recur (+ i 1) (str-concat (str-concat text (get ll-lines i)) "\n"))))))

;; ---- Debug info (Phase 14.2): BARS_DEBUG=1 → DWARF via LLVM metadata ----
;; Function-level DISubprogram + DILocation on instructions so GDB/LLDB
;; can break on Bars fn names and step through generated IR.

(defn debug-mode? []
  (= (bars_env_is_set "BARS_DEBUG") 1))

;; Last path component ("a/b/c.brs" → "c.brs")
(defn path-basename [path]
  (let [n (count path)]
    (loop [i (- n 1)]
      (if (< i 0) path
        (if (= (str-get path i) 47)
          (str-slice path (+ i 1) n)
          (recur (- i 1)))))))

;; Parent directory ("a/b/c.brs" → "a/b", "c.brs" → ".")
(defn path-dirname [path]
  (let [n (count path)]
    (loop [i (- n 1)]
      (if (< i 0) "."
        (if (= (str-get path i) 47)
          (if (= i 0) "/" (str-slice path 0 i))
          (recur (- i 1)))))))

;; define i64 @"name"(…) {  →  name   |  define i32 @main(…) { → main
(defn extract-define-name [line]
  (let [at (str-index-of line "@")]
    (if (< at 0) "fn"
      (let [rest (str-slice line (+ at 1) (count line))]
        (if (str-starts-with? rest "\"")
          (let [q (str-index-of (str-slice rest 1 (count rest)) "\"")]
            (if (< q 0) "fn" (str-slice rest 1 (+ q 1))))
          (let [lp (str-index-of rest "(")]
            (if (< lp 0) rest (str-slice rest 0 lp))))))))

;; Insert ` !dbg !N` before the opening `{` of a define line.
(defn add-dbg-to-define [line sp-id]
  (let [n (count line)]
    (loop [i (- n 1)]
      (if (< i 0) line
        (if (= (str-get line i) 123)
          (str-concat (str-slice line 0 i)
            (str-concat " !dbg !" (str-concat (int-str sp-id) " {")))
          (recur (- i 1)))))))

(defn has-dbg? [line]
  (>= (str-index-of line "!dbg") 0))

;; Instruction lines: two-space indent, not labels (…:), not comments.
(defn is-llvm-instr? [line]
  (if (< (count line) 3) false
    (if (str-starts-with? line "  ")
      (if (str-starts-with? line "  ;") false
        (if (str-eq? (str-slice line (- (count line) 1) (count line)) ":") false
          true))
      false)))

(defn attach-dbg-loc [line loc-id]
  (if (has-dbg? line) line
    (str-concat line (str-concat ", !dbg !" (int-str loc-id)))))

(defn dbg-meta-header [file dir]
  (let [v (vector)]
    (do (lines-push v "")
        (lines-push v "!llvm.dbg.cu = !{!0}")
        (lines-push v "!llvm.module.flags = !{!1, !2}")
        (lines-push v "!llvm.ident = !{!3}")
        (lines-push v (str-concat
          "!0 = distinct !DICompileUnit(language: DW_LANG_C99, file: !4, producer: \"bars\", "
          "isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, enums: !5)"))
        (lines-push v "!1 = !{i32 2, !\"Debug Info Version\", i32 3}")
        (lines-push v "!2 = !{i32 7, !\"Dwarf Version\", i32 4}")
        (lines-push v "!3 = !{!\"bars compiler\"}")
        (lines-push v (str-concat "!4 = !DIFile(filename: \""
          (str-concat file (str-concat "\", directory: \"" (str-concat dir "\")")))))
        (lines-push v "!5 = !{}")
        (lines-push v "!6 = !DIBasicType(name: \"i64\", size: 64, encoding: DW_ATE_signed)")
        (lines-push v "!7 = !DISubroutineType(types: !8)")
        (lines-push v "!8 = !{!6}")
        v)))

(defn dbg-subprogram [sp-id name]
  (str-concat "!" (str-concat (int-str sp-id)
    (str-concat " = distinct !DISubprogram(name: \"" (str-concat name
      "\", scope: !4, file: !4, line: 1, type: !7, scopeLine: 1, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !5)")))))

(defn dbg-location [loc-id sp-id]
  (str-concat "!" (str-concat (int-str loc-id)
    (str-concat " = !DILocation(line: 1, column: 1, scope: !" (str-concat (int-str sp-id) ")")))))

;; Rewrite body with !dbg attachments; append DI metadata. source-path for DIFile.
(defn attach-debug-info [ll-lines source-path]
  (let [file (if (> (count source-path) 0) (path-basename source-path) "program.brs")
        dir (if (> (count source-path) 0) (path-dirname source-path) ".")
        n (count ll-lines)
        out (vector)
        meta (vector)]
    (do (append-vec meta (dbg-meta-header file dir))
        (loop [i 0 cur-sp 0 cur-loc 0 next-id 20]
          (if (>= i n)
            (do (append-vec out meta) out)
            (let [line (get ll-lines i)]
              (if (str-starts-with? line "define ")
                (let [sp next-id
                      loc (+ sp 1)
                      name (extract-define-name line)
                      def (add-dbg-to-define line sp)
                      next2 (+ sp 2)]
                  (do (push out def)
                      (lines-push meta (dbg-subprogram sp name))
                      (lines-push meta (dbg-location loc sp))
                      (recur (+ i 1) sp loc next2)))
                (if (if (> cur-loc 0) (is-llvm-instr? line) false)
                  (do (push out (attach-dbg-loc line cur-loc))
                      (recur (+ i 1) cur-sp cur-loc next-id))
                  (if (str-eq? line "}")
                    (do (push out line)
                        (recur (+ i 1) 0 0 next-id))
                    (do (push out line)
                        (recur (+ i 1) cur-sp cur-loc next-id)))))))))))

;; source-path: DWARF DIFile when BARS_DEBUG=1.
;; triple: LLVM target triple (cross-compilation).
(defn compile-llvm-at [hir-lines out-path source-path]
  (compile-llvm-target hir-lines out-path source-path "x86_64-unknown-linux-gnu"))

(defn compile-llvm-target [hir-lines out-path source-path triple]
  (let [raw (hir-to-llvm-at hir-lines triple)
        ll-lines (if (debug-mode?) (attach-debug-info raw source-path) raw)
        text (join-lines ll-lines)
        ll-path (str-concat out-path ".ll")]
    (do (spit ll-path text)
        0)))

(defn compile-llvm [hir-lines out-path]
  (compile-llvm-at hir-lines out-path ""))
