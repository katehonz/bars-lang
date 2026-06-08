;; Self-hosted Ownership Checker — Stage 6
;; NLL (Non-Lexical Lifetime) borrow checking for Bars
;;
;; State tags: 0=Copy, 1=Owned, 2=Moved, 3=Borrowed(n), 4=MutBorrowed
;; Environment: list of scopes, each scope is a vector of [name state] pairs.
;; Updates append new pairs (shadowing old ones).

(defn state-tag [s] (get s 0))

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
(defn is-atom? [x] (< (ast-tag x) 10))

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
            (if (= (get pair 0) name)
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

;; NLL: release borrows → push Owned entries for all borrowed vars in top scope
(defn env-release-borrows [env]
  (let [scope (get env (- (count env) 1))]
    (loop [i 0]
      (if (>= i (count scope)) env
        (let [pair (get scope i)
              state (get pair 1)]
          (do (if (is-borrowed? state)
                (let [new-pair (vector)]
                  (do (push new-pair (get pair 0))
                      (push new-pair (S_Owned))
                      (push scope new-pair)))
                0)
              (recur (+ i 1))))))))

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
          (if (= name "+") true
          (if (= name "-") true
          (if (= name "*") true
          (if (= name "/") true
          (if (= name "%") true
          (if (= name "=") true
          (if (= name "!=") true
          (if (= name "<") true
          (if (= name ">") true
          (if (= name "<=") true
          (if (= name ">=") true
          (if (= name "inc") true
          (if (= name "dec") true
          (if (= name "abs") true
          (if (= name "max") true
          (if (= name "min") true
          (if (= name "not") true
          (if (= name "even?") true
          (if (= name "odd?") true
          (if (= name "zero?") true
          (if (= name "pos?") true
          (if (= name "neg?") true
          (if (= name "count") true
          (if (= name "get") true
          (if (= name "first") true
          (if (= name "last") true
          (if (= name "str-count") true
          (if (= name "str-get") true
          (if (= name "str-starts-with?") true
          (if (= name "str-ends-with?") true
          (if (= name "str-index-of") true
          (if (= name "str-slice") true
          (if (= name "int-str") true
          (if (= name "vector") true
          false
          ))))))))))))))))))))))))))))))))))))
        false)))

;; ---- Main expression checker ----

(defn check-expr [env expr]
  (if (is-atom? expr)
    (let [tag (ast-tag expr)]
      (if (= tag 1)
        (let [name (ast-val expr)
              state (env-lookup env name)]
          (if (is-moved? state)
            (do (println (str-concat "ownership error: use after move: " name)) 1)
            (if (is-borrowed? state)
              (do (println (str-concat "ownership error: use while borrowed: " name)) 1)
              0)))
        0))
    (let [head (get expr 0)
          tag (ast-tag head)]
      (if (= tag 10) (check-defn env expr)
      (if (= tag 11) (check-let env expr)
      (if (= tag 12) (check-if env expr)
      (if (= tag 13) (check-do env expr)
      (if (= tag 14) (check-loop env expr)
      (if (= tag 16) (check-lambda env expr)
      (check-call env expr))))))))))

;; ---- defn ----
(defn check-defn [env expr]
  (let [params (get expr 2)
        n-params (count params)
        body (get expr 3)]
    (env-push-scope env)
    (loop [i 0]
      (if (>= i n-params) 0
        (let [pname (ast-val (get params i))]
          (do (env-insert env pname (S_Owned))
              (recur (+ i 1))))))
    (let [result (check-expr env body)]
      (do (env-release-borrows env)
          (env-pop-scope env)
          result))))

;; ---- let ----
(defn check-let [env expr]
  (let [bindings (get expr 1)
        body (get expr 2)
        n (count bindings)]
    (env-push-scope env)
    (loop [i 0]
      (if (>= i n)
        (let [result (check-expr env body)]
          (do (env-release-borrows env)
              (env-pop-scope env)
              result))
        (let [binding (get bindings i)
              bname (ast-val (get binding 0))
              val-expr (get binding 1)]
          (do (check-expr env val-expr)
              (env-release-borrows env)
              (if (is-atom? val-expr)
                (if (= (ast-tag val-expr) 1)
                  (let [vname (ast-val val-expr)]
                    (if (not (is-copy-expr? val-expr))
                      (env-update env vname (S_Moved)))))
                0)
              (if (is-copy-expr? val-expr)
                (env-insert env bname (S_Copy))
                (env-insert env bname (S_Owned)))
              (recur (+ i 1))))))))

;; ---- if ----
(defn check-if [env expr]
  (let [cond (get expr 1)
        then-branch (get expr 2)
        else-branch (get expr 3)]
    (do (check-expr env cond)
        (env-release-borrows env)
        (let [then-env (env-copy env)]
          (check-expr then-env then-branch)
          (let [else-env (env-copy env)]
            (check-expr else-env else-branch)
            (do (env-merge env then-env)
                (env-merge env else-env)
                (env-release-borrows env)
                0))))))

;; ---- do ----
(defn check-do [env expr]
  (let [n (count expr)]
    (loop [i 1]
      (if (>= i n) 0
        (do (check-expr env (get expr i))
            (env-release-borrows env)
            (recur (+ i 1)))))))

;; ---- loop/recur ----
(defn check-loop [env expr]
  (let [bindings (get expr 1)
        body (get expr 2)
        n (count bindings)]
    (env-push-scope env)
    (loop [i 0]
      (if (>= i n)
        (let [result (check-expr env body)]
          (do (env-release-borrows env)
              (env-pop-scope env)
              result))
        (let [binding (get bindings i)
              bname (ast-val (get binding 0))
              val-expr (get binding 1)]
          (do (check-expr env val-expr)
              (env-release-borrows env)
              (if (is-atom? val-expr)
                (if (= (ast-tag val-expr) 1)
                  (let [vname (ast-val val-expr)]
                    (if (not (is-copy-expr? val-expr))
                      (env-update env vname (S_Moved)))))
                0)
              (if (is-copy-expr? val-expr)
                (env-insert env bname (S_Copy))
                (env-insert env bname (S_Owned)))
              (recur (+ i 1))))))))

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
(defn check-call [env expr]
  (let [head (get expr 0)
        n (count expr)]
    (check-expr env head)
    (loop [i 1]
      (if (>= i n)
        (do (env-release-borrows env) 0)
        (let [arg (get expr i)]
          (if (is-atom? arg)
            (let [tag (ast-tag arg)]
              (if (= tag 1)
                (let [name (ast-val arg)
                      state (env-lookup env name)]
                  (if (is-moved? state)
                    (println (str-concat "ownership error: use after move: " name)))
                  (recur (+ i 1)))
                (recur (+ i 1))))
            (do (check-expr env arg)
                (recur (+ i 1)))))))))

;; ---- Top-level entry ----

(defn check_ownership [ast-list]
  (let [env (env-new)
        n (count ast-list)]
    (loop [i 0]
      (if (>= i n) 0
        (let [expr (get ast-list i)]
          (do (check-expr env expr)
              (recur (+ i 1))))))))
