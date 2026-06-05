(defn own_t0 [tag]
  (let [v (vector)] (do (push v tag) v)))

(defn own_t1 [tag val]
  (let [v (vector)] (do (push v tag) (do (push v val) v))))

(defn ast_tag [x] (get x 0))
(defn ast_val [x] (get x 1))
(defn is_atom? [x] (< (ast_tag x) 10))

(defn S_Copy [] (own_t0 0))
(defn S_Owned [] (own_t0 1))
(defn S_Moved [] (own_t0 2))

(defn S_Borrowed [n] (own_t1 3 n))

(defn S_MutBorrowed [] (own_t0 4))

(defn state_tag [s] (get s 0))
(defn is_moved? [s] (= (state_tag s) 2))

(defn own_env_lookup [env name]
  (loop [i (- (count env) 1)]
    (if (< i 0) (own_t0 99)
      (let [pair (get env i)]
        (if (= (get pair 0) name)
          (get pair 1)
          (recur (- i 1)))))))

(defn own_env_insert [env name state]
  (let [pair (vector)]
    (do (push pair name) (do (push pair state) (do (push env pair) env)))))

(defn check_expr [env expr]
  (if (is_atom? expr)
    (if (= (ast_tag expr) 1)
      (let [name (ast_val expr)
            state (own_env_lookup env name)]
        (if (> (count state) 0)
          (if (is_moved? state)
            (do (println "ownership error") 1)
            0)
          (do (println "unknown var") 0)))
      0)
    (let [tag (ast_tag (get expr 0))]
      (cond
        (= tag 11) (check_let env expr)
        (= tag 12) (check_if env expr)
        (= tag 13) (check_do env expr)
        :else      (check_call env expr)))))

(defn check_let [env expr]
  (let [bindings (get expr 1) n (count bindings) body (get expr 2)]
    (loop [i 0 env env]
      (if (>= i n) (check_expr env body)
        (let [pair (get bindings i) name (ast_val (get pair 0)) val_expr (get pair 1)]
          (do (check_expr env val_expr) (recur (+ i 1) (own_env_insert env name (S_Owned)))))))))

(defn check_if [env expr]
  (let [cond (get expr 1) then (get expr 2) else (get expr 3)]
    (do (check_expr env cond) (do (check_expr env then) (do (check_expr env else) 0)))))

(defn check_do [env expr]
  (let [n (count expr)] (loop [i 1] (if (>= i n) 0 (do (check_expr env (get expr i)) (recur (+ i 1)))))))

(defn check_call [env expr]
  (let [n (count expr)] (loop [i 0] (if (>= i n) 0 (do (check_expr env (get expr i)) (recur (+ i 1)))))))

(defn check_ownership [ast_list]
  (let [env (vector) n (count ast_list)]
    (loop [i 0] (if (>= i n) 0 (let [expr (get ast_list i)] (do (check_expr env expr) (recur (+ i 1))))))))
