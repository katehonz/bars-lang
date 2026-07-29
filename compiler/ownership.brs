;; Self-hosted Ownership Checker — Stage 6
;; NLL (Non-Lexical Lifetime) borrow checking for Bars
;;
;; State tags: 0=Copy, 1=Owned, 2=Moved, 3=Borrowed(n), 4=MutBorrowed
;; Environment: list of scopes, each scope is a vector of [name state] pairs.
;; Updates append new pairs (shadowing old ones).

(defn state-tag [s] (get s 0))

;; str-eq? — compare strings by content (not pointer)
(defn str-eq? [a b]
  (if (!= (count a) (count b)) false
    (= (str-starts-with? a b) 1)))

(defn S_Copy [] (let [v (vector)] (do (push v 0) v)))
(defn S_Owned [] (let [v (vector)] (do (push v 1) v)))
(defn S_Moved [] (let [v (vector)] (do (push v 2) v)))
(defn S_Borrowed [] (let [v (vector)] (do (push v 3) v)))
(defn S_MutBorrowed [] (let [v (vector)] (do (push v 4) v)))

(defn is-copy? [s] (= (state-tag s) 0))
(defn is-moved? [s] (= (state-tag s) 2))
(defn is-borrowed? [s] (if (= (state-tag s) 3) true (= (state-tag s) 4)))
(defn is-mut-borrowed? [s] (= (state-tag s) 4))

(defn merge-states [a b]
  (if (is-moved? a) (S_Moved)
  (if (is-moved? b) (S_Moved)
  (if (is-mut-borrowed? a) (S_Owned)
  (if (is-mut-borrowed? b) (S_Owned)
  (if (is-borrowed? a) (S_Owned)
  (if (is-borrowed? b) (S_Owned)
  (if (is-copy? a) (if (is-copy? b) (S_Copy) (S_Owned))
  (S_Owned)))))))))

;; ---- AST helpers ----

(defn ast-tag [x] (get x 0))
(defn ast-val [x] (get x 1))
(defn is-atom? [x] (< (ast-tag x) 1000))
;; Optional source offset (3rd element on atoms from reader).
(defn ast-off [x]
  (if (>= (count x) 3) (get x 2) -1))

;; diag = [path text] for line:col reporting
(defn diag-path [d] (get d 0))
(defn diag-text [d] (get d 1))

(defn int-str [n] (str-from-i64 n))

(defn offset-to-span [text offset]
  (let [n (count text)
        lim (if (< offset 0) 0 (if (> offset n) n offset))]
    (loop [i 0 line 1 col 1]
      (if (>= i lim)
        (let [v (vector)]
          (do (push v line) (push v col) v))
        (if (= (str-get text i) 10)
          (recur (+ i 1) (+ line 1) 1)
          (recur (+ i 1) line (+ col 1)))))))

(defn line-content [text line-num]
  (let [n (count text)]
    (loop [i 0 cur 1 start 0]
      (if (>= i n)
        (if (= cur line-num) (str-slice text start n) "")
        (if (= (str-get text i) 10)
          (if (= cur line-num)
            (str-slice text start i)
            (recur (+ i 1) (+ cur 1) (+ i 1)))
          (recur (+ i 1) cur start))))))

(defn n-spaces [n]
  (loop [i 0 acc ""]
    (if (>= i n) acc
      (recur (+ i 1) (str-concat acc " ")))))

(defn print-snippet [text line col]
  (if (if (<= line 0) true (= (count text) 0))
    0
    (let [src (line-content text line)
          gutter (int-str line)
          pad (n-spaces (count gutter))
          c0 (if (< col 1) 0 (- col 1))
          c1 (if (> c0 (count src)) (count src) c0)
          indent (n-spaces c1)]
      (do (println "")
          (println (str-concat "  " (str-concat gutter (str-concat " | " src))))
          (println (str-concat "  " (str-concat pad (str-concat " | " (str-concat indent "^")))))
          0))))

(defn report-uam [diag name off]
  (let [msg (str-concat "error: ownership: use after move: `" (str-concat name "`"))
        text (diag-text diag)
        tlen (count text)]
    ;; Only map offset→line:col when offset falls inside the provided source
    ;; (main file). Module renames drop spans so multi-file stays safe.
    (if (if (>= off 0) (< off tlen) false)
      (let [lc (offset-to-span text off)
            line (get lc 0)
            col (get lc 1)
            where (str-concat (int-str line) (str-concat ":" (int-str col)))
            path (diag-path diag)]
        (do (println (str-concat msg (str-concat " at " where)))
            (if (> (count path) 0)
              (println (str-concat "  --> " (str-concat path (str-concat ":" where))))
              0)
            (print-snippet text line col)
            1))
      (do (println msg) 1))))

(defn unwrap-vec [v]
  (if (is-atom? v) v
    (let [head (get v 0)]
      (if (if (is-atom? head) (= (ast-tag head) 28) false)
        (let [n (count v) out (vector)]
          (do (loop [i 1]
                (if (>= i n) 0
                  (do (push out (get v i)) (recur (+ i 1)))))
              out))
        v))))

(defn normalize-params [params]
  (let [plain (unwrap-vec params)
        n (count plain)
        out (vector)]
    (do (loop [i 0]
          (if (>= i n) 0
            (let [p (get plain i)]
              (if (if (is-atom? p) (= (ast-tag p) 26) false)
                (recur (+ i 1))
                (do (if (if (is-atom? p) (= (ast-tag p) 1) false)
                      (push out p)
                      0)
                    (recur (+ i 1)))))))
        out)))

;; ---- Environment (stack of scopes) ----
;; insert → current scope only.
;; update → shadow in the scope that owns the name (host semantics).
;; pop    → real vector pop so inner moves of outer names don't leak.

(defn env-new []
  (let [v (vector)] (do (push v (vector)) v)))

;; Scan scopes top-down; within each scope reverse (newest first).
;; idx sentinel -2 = "start at end of this scope" (NOT -1: after
;; decrement past 0, -1 would re-arm start-at-end and infinite-loop).
(defn env-lookup [env name]
  (loop [si (- (count env) 1) idx -2]
    (if (< si 0) (S_Owned)
      (let [scope (get env si)
            j (if (= idx -2) (- (count scope) 1) idx)]
        (if (< j 0)
          (recur (- si 1) -2)
          (let [pair (get scope j)]
            (if (str-eq? (get pair 0) name)
              (get pair 1)
              (recur si (- j 1)))))))))

(defn scope-has? [scope name]
  (loop [j (- (count scope) 1)]
    (if (< j 0) false
      (if (str-eq? (get (get scope j) 0) name) true
        (recur (- j 1))))))

(defn env-insert [env name state]
  (let [scope (get env (- (count env) 1))
        pair (vector)]
    (do (push pair name)
        (push pair state)
        (push scope pair)
        env)))

(defn env-update [env name state]
  (loop [si (- (count env) 1)]
    (if (< si 0)
      (env-insert env name state)
      (let [scope (get env si)]
        (if (scope-has? scope name)
          (let [pair (vector)]
            (do (push pair name)
                (push pair state)
                (push scope pair)
                env))
          (recur (- si 1)))))))

(defn env-push-scope [env]
  (do (push env (vector)) env))

(defn env-pop-scope [env]
  (do (pop env) env))

(defn env-release-borrows [env] env)

;; Copy entire env (for if/else branch isolation)
(defn env-copy [env]
  (let [new-env (vector)]
    (do (loop [si 0]
          (if (>= si (count env)) 0
            (let [src-scope (get env si)
                  dst-scope (vector)]
              (do (loop [j 0]
                    (if (>= j (count src-scope)) 0
                      (let [sp (get src-scope j)
                            dp (vector)]
                        (do (push dp (get sp 0))
                            (push dp (get sp 1))
                            (push dst-scope dp)
                            (recur (+ j 1))))))
                  (push new-env dst-scope)
                  (recur (+ si 1))))))
        new-env)))

;; Merge another env into current (conservative, for if/match branches)
(defn env-merge [env other]
  (let [scope (get env (- (count env) 1))
        other-scope (get other (- (count other) 1))]
    (loop [i 0]
      (if (>= i (count other-scope)) env
        (let [other-pair (get other-scope i)
              other-name (get other-pair 0)
              other-state (get other-pair 1)
              self-state (env-lookup env other-name)
              merged (merge-states self-state other-state)]
          (do (env-update env other-name merged)
              (recur (+ i 1))))))))

;; ---- Copy type detection ----
;; Flat name list + loop (deep nested ifs overflow Gen1 HIR/LLVM).

(defn copy-op-names []
  (let [v (vector)]
    (do (push v "+") (push v "-") (push v "*") (push v "/") (push v "%")
        (push v "=") (push v "!=") (push v "<") (push v ">") (push v "<=") (push v ">=")
        (push v "inc") (push v "dec") (push v "abs") (push v "max") (push v "min")
        (push v "not") (push v "even?") (push v "odd?") (push v "zero?") (push v "pos?") (push v "neg?")
        (push v "count") (push v "get") (push v "first") (push v "last")
        (push v "str-count") (push v "str-get") (push v "str-starts-with?")
        (push v "str-ends-with?") (push v "str-index-of") (push v "str-slice")
        (push v "str-replace")
        (push v "int-str") (push v "vector")
        (push v "map-contains?") (push v "map-keys") (push v "map-values")
        (push v "vector-clone") (push v "conj") (push v "v-assoc") (push v "v-pop")
        (push v "map-clone") (push v "map-assoc")
        (push v "set-contains?") (push v "set-count")
        v)))

(defn name-in-copy-ops? [name]
  (let [ops (copy-op-names)
        n (count ops)]
    (loop [i 0]
      (if (>= i n) false
        (if (str-eq? (get ops i) name) true
          (recur (+ i 1)))))))

(defn is-copy-expr? [expr]
  (if (is-atom? expr)
    (let [tag (ast-tag expr)]
      ;; 0=number 2=string-lit 4=nil 5=bool — match host (literals are Copy)
      (if (= tag 0) true
        (if (= tag 2) true
          (if (= tag 4) true
            (if (= tag 5) true
              ;; true/false/nil as symbols (legacy reader) are still Copy
              (if (= tag 1)
                (let [n (ast-val expr)]
                  (if (str-eq? n "true") true
                    (if (str-eq? n "false") true
                      (str-eq? n "nil"))))
                false))))))
    (let [head (get expr 0)]
      (if (if (is-atom? head) (= (ast-tag head) 1) false)
        (name-in-copy-ops? (ast-val head))
        false))))

;; Mark source symbol moved only if it is not Copy (host NLL).
(defn maybe-move-symbol [env val-expr]
  (if (if (is-atom? val-expr) (= (ast-tag val-expr) 1) false)
    (let [vname (ast-val val-expr)
          st (env-lookup env vname)]
      (if (is-copy? st) 0
        (env-update env vname (S_Moved))))
    0))

;; State for a new binding from val-expr.
(defn binding-state [env val-expr]
  (if (is-copy-expr? val-expr)
    (S_Copy)
    (if (if (is-atom? val-expr) (= (ast-tag val-expr) 1) false)
      (let [st (env-lookup env (ast-val val-expr))]
        (if (is-copy? st) (S_Copy) (S_Owned)))
      (S_Owned))))

;; ---- Main expression checker ----
;; diag = [path text] for line:col on UAM.
;; Walks AST; flags use of symbols currently marked Moved.

(defn check-expr [env expr diag]
  (if (= expr 0) 0
  (if (is-atom? expr)
    (let [tag (ast-tag expr)]
      (if (= tag 1)
        (let [name (ast-val expr)
              state (env-lookup env name)]
          (if (is-moved? state)
            (report-uam diag name (ast-off expr))
            0))
        0))
    (let [head (get expr 0)]
      (if (not (is-atom? head))
        (let [n (count expr)]
          (loop [i 0 err 0]
            (if (>= i n) err
              (let [e (check-expr env (get expr i) diag)]
                (recur (+ i 1) (if (> e 0) e err))))))
        (let [tag (ast-tag head)]
          (if (= tag 28)
            0
          (if (= tag 10) (check-defn env expr diag)
          (if (= tag 11) (check-let env expr diag)
          (if (= tag 12) (check-if env expr diag)
          (if (= tag 13) (check-do env expr diag)
          (if (= tag 14) (check-loop env expr diag)
          (if (= tag 16) (check-lambda env expr diag)
          (if (= tag 17)
            (let [n (count expr)]
              (loop [i 1 err 0]
                (if (>= i n) err
                  (let [arm-env (env-copy env)
                        e (check-expr arm-env (get expr i) diag)]
                    (recur (+ i 1) (if (> e 0) e err))))))
          (check-call env expr diag)))))))))))))))

(defn check-defn [env expr diag]
  (let [params (normalize-params (get expr 2))
        n-params (count params)
        n (count expr)]
    (do
      (env-push-scope env)
      (loop [i 0]
        (if (>= i n-params) 0
          (do (env-insert env (ast-val (get params i)) (S_Owned))
              (recur (+ i 1)))))
      (let [result
            (loop [j 3 err 0]
              (if (>= j n) err
                (let [e (check-expr env (get expr j) diag)]
                  (recur (+ j 1) (if (> e 0) e err)))))]
        (do (env-release-borrows env)
            (env-pop-scope env)
            result)))))

(defn check-let [env expr diag]
  (let [bindings (unwrap-vec (get expr 1))
        n (count bindings)
        nbody (count expr)]
    (env-push-scope env)
    (loop [i 0]
      (if (>= i n)
        (let [result (if (<= nbody 3)
                       (check-expr env (get expr 2) diag)
                       (loop [j 2 err 0]
                         (if (>= j nbody) err
                           (let [e (check-expr env (get expr j) diag)]
                             (recur (+ j 1) (if (> e 0) e err))))))]
          (do (env-release-borrows env)
              (env-pop-scope env)
              result))
        (let [bname (ast-val (get bindings i))
              val-expr (get bindings (+ i 1))]
          (do (check-expr env val-expr diag)
              (env-release-borrows env)
              (let [st (binding-state env val-expr)]
                (do (maybe-move-symbol env val-expr)
                    (env-insert env bname st)))
              (recur (+ i 2))))))))

(defn check-if [env expr diag]
  (let [cond (get expr 1)
        then-branch (get expr 2)
        else-branch (get expr 3)
        e0 (check-expr env cond diag)
        _ (env-release-borrows env)
        then-env (env-copy env)
        else-env (env-copy env)
        e1 (check-expr then-env then-branch diag)
        e2 (check-expr else-env else-branch diag)]
    (do (env-release-borrows env)
        (if (> e0 0) e0 (if (> e1 0) e1 e2)))))

(defn check-do [env expr diag]
  (let [n (count expr)]
    (loop [i 1 err 0]
      (if (>= i n) err
        (let [e (check-expr env (get expr i) diag)]
          (do (env-release-borrows env)
              (recur (+ i 1) (if (> e 0) e err))))))))

(defn check-loop [env expr diag]
  (let [bindings (unwrap-vec (get expr 1))
        n (count bindings)
        nbody (count expr)]
    (env-push-scope env)
    (loop [i 0]
      (if (>= i n)
        (let [result (if (<= nbody 3)
                       (check-expr env (get expr 2) diag)
                       (loop [j 2 err 0]
                         (if (>= j nbody) err
                           (let [e (check-expr env (get expr j) diag)]
                             (recur (+ j 1) (if (> e 0) e err))))))]
          (do (env-release-borrows env)
              (env-pop-scope env)
              result))
        (let [bname (ast-val (get bindings i))
              val-expr (get bindings (+ i 1))]
          (do (check-expr env val-expr diag)
              (env-release-borrows env)
              (env-insert env bname (binding-state env val-expr))
              (recur (+ i 2))))))))

(defn check-lambda [env expr diag]
  (let [params (get expr 1)
        body (get expr 2)
        n (count params)]
    (env-push-scope env)
    (loop [i 0]
      (if (>= i n) 0
        (let [pname (ast-val (get params i))]
          (do (env-insert env pname (S_Owned))
              (recur (+ i 1))))))
    (let [result (check-expr env body diag)]
      (do (env-release-borrows env)
          (env-pop-scope env)
          result))))

(defn check-one-arg [env arg diag]
  (if (is-atom? arg)
    (let [tag (ast-tag arg)]
      (if (= tag 1)
        (let [name (ast-val arg)
              state (env-lookup env name)]
          (if (is-moved? state)
            (report-uam diag name (ast-off arg))
            0))
        0))
    (check-expr env arg diag)))

(defn check-call [env expr diag]
  (let [n (count expr)]
    (loop [i 0 err 0]
      (if (>= i n)
        (do (env-release-borrows env) err)
        (let [e (check-one-arg env (get expr i) diag)]
          (recur (+ i 1) (if (> e 0) e err)))))))

;; ---- Top-level entry ----
;; check_ownership [ast] or check_ownership_at [ast path text]
;; Returns 0 if OK, >0 if any ownership error was reported.

(defn check_ownership_at [ast-list path text]
  (if (= ast-list 0) 0
    (let [env (env-new)
          diag (vector)
          n (count ast-list)]
      (do (push diag path)
          (push diag text)
          (loop [i 0 err 0]
            (if (>= i n) err
              (let [e (check-expr env (get ast-list i) diag)]
                (recur (+ i 1) (if (> e 0) e err)))))))))

(defn check_ownership [ast-list]
  (check_ownership_at ast-list "" ""))
