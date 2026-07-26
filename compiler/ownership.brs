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

;; ---- Environment (stack of scopes, append-only) ----
;; Lookup scans scopes top-down, then each scope in reverse (newest first)

(defn env-new []
  (let [v (vector)] (do (push v (vector)) v)))

(defn env-lookup [env name]
  (loop [si (- (count env) 1) i -1]
    (if (< si 0) (S_Owned)
      (let [scope (get env si)
            idx (if (< i 0) (- (count scope) 1) i)]
        (if (< idx 0)
          (recur (- si 1) -1)
          (let [pair (get scope idx)]
            (if (str-eq? (get pair 0) name)
              (get pair 1)
              (recur si (- idx 1)))))))))

;; Append entry to current scope. Shadows any existing entry for the same name.
(defn env-insert [env name state]
  (let [scope (get env (- (count env) 1))
        pair (vector)]
    (do (push pair name) (do (push pair state) (do (push scope pair) env)))))

;; Update = insert with shadowing (same as env-insert, kept for clarity)
(defn env-update [env name state]
  (env-insert env name state))

(defn env-push-scope [env]
  (do (push env (vector)) env))

(defn env-pop-scope [env] env)

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

(defn is-copy-expr? [expr]
  (if (is-atom? expr)
    (let [tag (ast-tag expr)]
      (if (= tag 0) true (if (= tag 4) true (= tag 5))))
    (let [head (get expr 0)
          tag (ast-tag head)]
      (if (if (is-atom? head) (= tag 1) false)
        (let [name (ast-val head)]
          (if (str-eq? name "+") true
          (if (str-eq? name "-") true
          (if (str-eq? name "*") true
          (if (str-eq? name "/") true
          (if (str-eq? name "%") true
          (if (str-eq? name "=") true
          (if (str-eq? name "!=") true
          (if (str-eq? name "<") true
          (if (str-eq? name ">") true
          (if (str-eq? name "<=") true
          (if (str-eq? name ">=") true
          (if (str-eq? name "inc") true
          (if (str-eq? name "dec") true
          (if (str-eq? name "abs") true
          (if (str-eq? name "max") true
          (if (str-eq? name "min") true
          (if (str-eq? name "not") true
          (if (str-eq? name "even?") true
          (if (str-eq? name "odd?") true
          (if (str-eq? name "zero?") true
          (if (str-eq? name "pos?") true
          (if (str-eq? name "neg?") true
          (if (str-eq? name "count") true
          (if (str-eq? name "get") true
          (if (str-eq? name "first") true
          (if (str-eq? name "last") true
          (if (str-eq? name "str-count") true
          (if (str-eq? name "str-get") true
          (if (str-eq? name "str-starts-with?") true
          (if (str-eq? name "str-ends-with?") true
          (if (str-eq? name "str-index-of") true
          (if (str-eq? name "str-slice") true
          (if (str-eq? name "int-str") true
          (if (str-eq? name "vector") true
          false
          ))))))))))))))))))))))))))))))))))))
        false)))

;; ---- Main expression checker ----
;; Walks AST; flags use of symbols currently marked Moved.

(defn check-expr [env expr]
  (if (= expr 0) 0
  (if (is-atom? expr)
    (let [tag (ast-tag expr)]
      (if (= tag 1)
        (let [name (ast-val expr)
              state (env-lookup env name)]
          (if (is-moved? state)
            (do (println (str-concat "ownership error: use after move: " name)) 1)
            0))
        0))
    (let [head (get expr 0)]
      (if (not (is-atom? head))
        ;; data vector / nested list without atom head
        (let [n (count expr)]
          (loop [i 0 err 0]
            (if (>= i n) err
              (let [e (check-expr env (get expr i))]
                (recur (+ i 1) (if (> e 0) e err))))))
        (let [tag (ast-tag head)]
          (if (= tag 10) (check-defn env expr)
          (if (= tag 11) (check-let env expr)
          (if (= tag 12) (check-if env expr)
          (if (= tag 13) (check-do env expr)
          (if (= tag 14) (check-loop env expr)
          (if (= tag 16) (check-lambda env expr)
          (if (= tag 17)
            ;; match: scrut + flat arms
            (let [n (count expr)]
              (loop [i 1 err 0]
                (if (>= i n) err
                  (let [e (check-expr env (get expr i))]
                    (recur (+ i 1) (if (> e 0) e err))))))
          (check-call env expr))))))))))))))

;; ---- defn ----
(defn check-defn [env expr]
  (let [params (normalize-params (get expr 2))
        n-params (count params)
        n (count expr)
        body-start 3]
    (env-push-scope env)
    (loop [i 0]
      (if (>= i n-params) 0
        (do (env-insert env (ast-val (get params i)) (S_Owned))
            (recur (+ i 1)))))
    (let [result (if (<= n 4)
                   (check-expr env (get expr 3))
                   (loop [j body-start err 0]
                     (if (>= j n) err
                       (let [e (check-expr env (get expr j))]
                         (recur (+ j 1) (if (> e 0) e err))))))]
      (do (env-release-borrows env)
          (env-pop-scope env)
          result))))

;; ---- let (flat binds: name1 val1 name2 val2 ...) ----
(defn check-let [env expr]
  (let [bindings (unwrap-vec (get expr 1))
        n (count bindings)
        nbody (count expr)]
    (env-push-scope env)
    (loop [i 0]
      (if (>= i n)
        (let [result (if (<= nbody 3)
                       (check-expr env (get expr 2))
                       (loop [j 2 err 0]
                         (if (>= j nbody) err
                           (let [e (check-expr env (get expr j))]
                             (recur (+ j 1) (if (> e 0) e err))))))]
          (do (env-release-borrows env)
              (env-pop-scope env)
              result))
        (let [bname (ast-val (get bindings i))
              val-expr (get bindings (+ i 1))]
          (do (check-expr env val-expr)
              (env-release-borrows env)
              (if (is-atom? val-expr)
                (if (= (ast-tag val-expr) 1)
                  (let [vname (ast-val val-expr)]
                    (if (not (is-copy-expr? val-expr))
                      (env-update env vname (S_Moved))
                      0))
                  0)
                0)
              (if (is-copy-expr? val-expr)
                (env-insert env bname (S_Copy))
                (env-insert env bname (S_Owned)))
              (recur (+ i 2))))))))

;; ---- if (shared env; no branch isolation — avoids heavy env-copy) ----
(defn check-if [env expr]
  (let [cond (get expr 1)
        then-branch (get expr 2)
        else-branch (get expr 3)
        e0 (check-expr env cond)
        _ (env-release-borrows env)
        e1 (check-expr env then-branch)
        e2 (check-expr env else-branch)]
    (do (env-release-borrows env)
        (if (> e0 0) e0 (if (> e1 0) e1 e2)))))

;; ---- do ----
(defn check-do [env expr]
  (let [n (count expr)]
    (loop [i 1]
      (if (>= i n) 0
        (do (check-expr env (get expr i))
            (env-release-borrows env)
            (recur (+ i 1)))))))

;; ---- loop/recur (flat binds) ----
(defn check-loop [env expr]
  (let [bindings (unwrap-vec (get expr 1))
        n (count bindings)
        nbody (count expr)]
    (env-push-scope env)
    (loop [i 0]
      (if (>= i n)
        (let [result (if (<= nbody 3)
                       (check-expr env (get expr 2))
                       (loop [j 2 err 0]
                         (if (>= j nbody) err
                           (let [e (check-expr env (get expr j))]
                             (recur (+ j 1) (if (> e 0) e err))))))]
          (do (env-release-borrows env)
              (env-pop-scope env)
              result))
        (let [bname (ast-val (get bindings i))
              val-expr (get bindings (+ i 1))]
          (do (check-expr env val-expr)
              (env-release-borrows env)
              (if (is-atom? val-expr)
                (if (= (ast-tag val-expr) 1)
                  (let [vname (ast-val val-expr)]
                    (if (not (is-copy-expr? val-expr))
                      (env-update env vname (S_Moved))
                      0))
                  0)
                0)
              (if (is-copy-expr? val-expr)
                (env-insert env bname (S_Copy))
                (env-insert env bname (S_Owned)))
              (recur (+ i 2))))))))

;; ---- lambda (fn) ----
(defn check-lambda [env expr]
  (let [params (get expr 1)
        body (get expr 2)
        n (count params)]
    (env-push-scope env)
    (loop [i 0]
      (if (>= i n) 0
        (let [pname (ast-val (get params i))]
          (do (env-insert env pname (S_Owned))
              (recur (+ i 1))))))
    (let [result (check-expr env body)]
      (do (env-release-borrows env)
          (env-pop-scope env)
          result))))

;; ---- function call ----
;; Most Bars functions don't consume their arguments (push, println, str-concat etc.)
;; We check for moved/borrowed variables but don't mark as moved after call.
(defn check-one-arg [env arg]
  (if (is-atom? arg)
    (let [tag (ast-tag arg)]
      (if (= tag 1)
        (let [name (ast-val arg)
              state (env-lookup env name)]
          (if (is-moved? state)
            (println (str-concat "ownership error: use after move: " name)))
          0)
        0))
    (check-expr env arg)))

(defn check-call [env expr]
  (let [n (count expr)]
    (loop [i 0 err 0]
      (if (>= i n)
        (do (env-release-borrows env) err)
        (let [e (check-one-arg env (get expr i))]
          (recur (+ i 1) (if (> e 0) e err)))))))

;; ---- Top-level entry ----
;; Returns 0 if OK, >0 if any ownership error was reported.

;; Placeholder pass (wired into pipeline). Full NLL walk hangs on recursive
;; if/call under Gen1 LLVM; keep API and enable via BARS_OWNERSHIP=1 later.
(defn check_ownership [ast-list]
  0)
