;; Bars Module System — Stage 9 of self-hosting
;; Minimal implementation: parses (require ...) forms from AST,
;; handles name prefixing for module isolation.
;;
;; The caller (build.brs) handles file I/O and reader integration.

(defn str-eq? [a b]
  (if (!= (count a) (count b)) false
    (= (str-starts-with? a b) 1)))

(defn ast-tag [x] (get x 0))
(defn ast-val [x] (get x 1))
(defn is-atom? [x] (< (ast-tag x) 1000))

;; make-atom [tag val] — create a tagged atom
(defn make-atom [tag val]
  (let [v (vector)]
    (do (push v tag) (do (push v val) v))))

;; ---- parse require form ----
;; (require "path.brs" :as alias) => [path alias] or nil

(defn parse-require [expr]
  (if (is-atom? expr)
    0
    (let [head (get expr 0)]
      (if (not (is-atom? head)) 0
      (if (not (str-eq? (ast-val head) "require")) 0
      (let [n (count expr)]
        (if (< n 4) 0
        (let [path-expr (get expr 1)
              kw-expr (get expr 2)
              alias-expr (get expr 3)]
          (if (not (is-atom? path-expr)) 0
          (if (not (str-eq? (ast-val kw-expr) "as")) 0
          (if (not (is-atom? alias-expr)) 0
            (let [pair (vector)]
              (do (push pair (ast-val path-expr))
                  (push pair (ast-val alias-expr))
                  pair)))))))))))))

;; ---- strip require forms from AST ----

(defn strip-requires [ast-list]
  (let [n (count ast-list)
        result (vector)]
    (loop [i 0]
      (if (>= i n) result
        (let [expr (get ast-list i)]
          (if (not (> (count (parse-require expr)) 0))
            (push result expr))
          (recur (+ i 1)))))))

;; ---- prefix names in AST ----

(defn prefix-name [prefix name]
  (str-concat prefix name))

;; rename symbols matching public names with prefix
(defn rename-expr [expr prefix names]
  (if (is-atom? expr)
    (if (= (ast-tag expr) 1)
      (let [name (ast-val expr)]
        ;; Check slash-prefixed: alias/name => prefixed_name
        (let [slash-pos (str-index-of name "/")]
          (if (>= slash-pos 0)
            ;; Has slash — check alias, replace with prefix
            (let [alias (str-slice name 0 slash-pos)
                  rest  (str-slice name (+ slash-pos 1) (count name))]
              (if (str-eq? alias prefix)  ;; alias matches prefix
                (make-atom 1 (str-concat prefix rest))
                expr))
            ;; No slash — check if name is a public name
            (loop [i 0]
              (if (>= i (count names)) expr
                (if (str-eq? (get names i) name)
                  (make-atom 1 (str-concat prefix name))
                  (recur (+ i 1))))))))
      expr)
    ;; Compound: [head args...]
    (let [n (count expr) new-expr (vector)]
      (do (push new-expr (rename-expr (get expr 0) prefix names))
          (loop [i 1]
            (if (>= i n) new-expr
              (do (push new-expr (rename-expr (get expr i) prefix names))
                  (recur (+ i 1)))))))))

;; rename top-level defn names
(defn rename-top-defns [ast-list prefix]
  (let [n (count ast-list)]
    (loop [i 0]
      (if (>= i n) ast-list
        (let [expr (get ast-list i)]
          (if (is-atom? expr) 0
            (let [head (get expr 0) tag (if (is-atom? head) (ast-tag head) 99)]
              ;; defn: position 1 is name
              (if (= tag 10)
                (let [name-atom (get expr 1)
                      name (ast-val name-atom)
                      new-name (make-atom 1 (prefix-name prefix name))]
                  (do 0))  ;; TODO: actually mutate the vector
                0)))
          (recur (+ i 1)))))))

;; rename all references in a module's AST
(defn rename-module-refs [ast-list prefix public-names]
  (let [n (count ast-list) result (vector)]
    (loop [i 0]
      (if (>= i n) result
        (do (push result (rename-expr (get ast-list i) prefix public-names))
            (recur (+ i 1)))))))

;; collect public names from AST
(defn collect-names [ast-list]
  (let [n (count ast-list) names (vector)]
    (loop [i 0]
      (if (>= i n) names
        (let [expr (get ast-list i)]
          (if (is-atom? expr) (recur (+ i 1))
            (let [head (get expr 0) tag (if (is-atom? head) (ast-tag head) 99)]
              (if (= tag 10)
                (let [name-atom (get expr 1)]
                  (if (is-atom? name-atom)
                    (do (push names (ast-val name-atom))
                        (recur (+ i 1)))
                    (recur (+ i 1))))
              (if (= tag 20)
                (let [name-atom (get expr 1)]
                  (if (is-atom? name-atom)
                    (do (push names (ast-val name-atom))
                        (recur (+ i 1)))
                    (recur (+ i 1))))
              (recur (+ i 1)))))))))))

;; ---- main entry: merge module AST into main AST ----
;; Returns [(merged AST) (prefix ...)]

(defn merge-module [main-ast module-ast alias]
  (let [prefix (str-concat "_" (str-concat alias "_"))
        pub-names (collect-names module-ast)
        renamed-module (rename-module-refs module-ast prefix pub-names)
        stripped-main (strip-requires main-ast)
        ;; Merge: main defs first, then module defs
        result (vector)
        n1 (count stripped-main)
        n2 (count renamed-module)]
    (loop [i 0]
      (if (>= i n1) 0
        (do (push result (get stripped-main i))
            (recur (+ i 1)))))
    (loop [i 0]
      (if (>= i n2) 0
        (do (push result (get renamed-module i))
            (recur (+ i 1)))))
    result))
