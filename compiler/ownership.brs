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
        (push v "int-str") (push v "vector")
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
            (= tag 5)))))
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
          (if (= tag 28)
            ;; vector literal [28 a b …] — host ignores element ownership
            0
          (if (= tag 10) (check-defn env expr)
          (if (= tag 11) (check-let env expr)
          (if (= tag 12) (check-if env expr)
          (if (= tag 13) (check-do env expr)
          (if (= tag 14) (check-loop env expr)
          (if (= tag 16) (check-lambda env expr)
          (if (= tag 17)
            ;; match: scrut + flat arms (shared env; light pass)
            (let [n (count expr)]
              (loop [i 1 err 0]
                (if (>= i n) err
                  (let [e (check-expr env (get expr i))]
                    (recur (+ i 1) (if (> e 0) e err))))))
          (check-call env expr)))))))))))))))

;; ---- defn ----
(defn check-defn [env expr]
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
                (let [e (check-expr env (get expr j))]
                  (recur (+ j 1) (if (> e 0) e err)))))]
        (do (env-release-borrows env)
            (env-pop-scope env)
            result)))))

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
              (let [st (binding-state env val-expr)]
                (do (maybe-move-symbol env val-expr)
                    (env-insert env bname st)))
              (recur (+ i 2))))))))

;; ---- if (shared env; branch isolation via env-copy is too heavy
;;      for Gen1 on the full compiler AST — false moves across arms
;;      are reduced by not moving on loop rebinds instead) ----
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
    (loop [i 1 err 0]
      (if (>= i n) err
        (let [e (check-expr env (get expr i))]
          (do (env-release-borrows env)
              (recur (+ i 1) (if (> e 0) e err))))))))

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
              ;; Loop rebinds (counters/accumulators) are not moves —
              ;; unlike let alias, recur updates the same slots.
              (env-insert env bname (binding-state env val-expr))
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
            (do (println (str-concat "ownership error: use after move: " name)) 1)
            0))
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
;; Light NLL (aligned with host): Copy literals/ops don't move;
;; bare-symbol alias of Owned marks source Moved; real scope pop.
;; Branch isolation via env-copy is avoided (Gen1 LLVM / depth).

(defn check_ownership [ast-list]
  (if (= ast-list 0) 0
    (let [env (env-new)
          n (count ast-list)]
      (loop [i 0 err 0]
        (if (>= i n) err
          (let [e (check-expr env (get ast-list i))]
            (recur (+ i 1) (if (> e 0) e err))))))))
