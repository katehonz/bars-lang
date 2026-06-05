;; Bars Ownership Checker — Stage 6 of self-hosting
;; NLL borrow checking with states

;; State tags: 0=Copy, 1=Owned, 2=Moved, 3=Borrowed(n), 4=MutBorrowed

(defn S_Copy []
  (t0 0)
)

(defn S_Owned []
  (t0 1)
)

(defn S_Moved []
  (t0 2)
)

(defn S_Borrowed [n]
  (t1 3 n)
)

(defn S_MutBorrowed []
  (t0 4)
)

(defn state_tag [s]
  (get s 0)
)

(defn is_copy? [s]
  (= (state_tag s) 0)
)

(defn is_owned? [s]
  (= (state_tag s) 1)
)

(defn is_moved? [s]
  (= (state_tag s) 2)
)

(defn is_borrowed? [s]
  (= (state_tag s) 3)
)

(defn is_mut_borrowed? [s]
  (= (state_tag s) 4)
)

;; OwnershipEnv: vector of [name, state] pairs

(defn own_env_lookup [env name]
  (loop [i (- (count env) 1)]
    (if (< i 0) (t0 99)
      (let [pair (get env i)]
        (if (= (get pair 0) name)
          (get pair 1)
          (recur (- i 1))))))
)

(defn own_env_insert [env name state]
  (let [pair (vector)]
    (do (push pair name) (do (push pair state) (do (push env pair) env))))
)

;; Main ownership check function

(defn check_expr [env expr]
  (if (is_atom? expr)
    (if (= (ast_tag expr) 1)
      (let [name (ast_val expr)
            state (own_env_lookup env name)]
        (if (> (count state) 0)
          (if (is_moved? state)
            (do (println (str_concat "ownership error: use after move: " name)) 1)
            0)
          (do (println (str_concat "ownership: unknown var: " name)) 0)))
      0)
    (let [tag (ast_tag (get expr 0))]
      (cond
        (= tag 11) (check_let env expr)
        (= tag 12) (check_if env expr)
        (= tag 13) (check_do env expr)
        :else      (check_call env expr)))))
)

(defn check_let [env expr]
  (let [bindings (get expr 1)
        n (count bindings)
        body (get expr 2)]
    (loop [i 0 env env]
      (if (>= i n)
        (check_expr env body)
        (let [pair (get bindings i)
              name (ast_val (get pair 0))
              val_expr (get pair 1)]
          (do (check_expr env val_expr)
              (recur (+ i 1) (own_env_insert env name (S_Owned))))))))
)

(defn check_if [env expr]
  (let [cond (get expr 1)
        then (get expr 2)
        else (get expr 3)]
    (do (check_expr env cond)
        (do (check_expr env then)
            (do (check_expr env else)
                0))))
)

(defn check_do [env expr]
  (let [n (count expr)]
    (loop [i 1]
      (if (>= i n) 0
        (do (check_expr env (get expr i))
            (recur (+ i 1))))))
)

(defn check_call [env expr]
  (let [n (count expr)]
    (loop [i 0]
      (if (>= i n) 0
        (do (check_expr env (get expr i))
            (recur (+ i 1))))))
)

(defn check_ownership [ast_list]
  (let [env (vector)
        n (count ast_list)]
    (loop [i 0]
      (if (>= i n) 0
        (let [expr (get ast_list i)]
          (do (check_expr env expr)
              (recur (+ i 1)))))))
)


