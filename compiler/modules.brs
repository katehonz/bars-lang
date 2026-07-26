;; Bars Module System — Stage 9 of self-hosting
;; Resolves (require "path" :as alias), renames with _m_alias_ prefix,
;; substitutes alias/name qualified symbols.
;;
;; File I/O (slurp + reader) is provided by the caller (build.brs).

(defn str-eq? [a b]
  (if (!= (count a) (count b)) false
    (= (str-starts-with? a b) 1)))

(defn ast-tag [x] (get x 0))
(defn ast-val [x] (get x 1))
(defn is-atom? [x] (< (ast-tag x) 1000))

(defn make-atom [tag val]
  (let [v (vector)]
    (do (push v tag) (do (push v val) v))))

;; Preserve source offset (3rd element) when rewriting a symbol.
(defn make-atom-keep-span [old tag val]
  (if (>= (count old) 3)
    (let [v (vector)]
      (do (push v tag) (push v val) (push v (get old 2)) v))
    (make-atom tag val)))

;; ---- parse require: (require "path.brs" :as alias) => [path alias] or 0 ----

(defn parse-require [expr]
  (if (is-atom? expr) 0
    (let [head (get expr 0)]
      (if (not (is-atom? head)) 0
        (if (not (str-eq? (ast-val head) "require")) 0
          (if (< (count expr) 4) 0
            (let [path-expr (get expr 1)
                  kw-expr (get expr 2)
                  alias-expr (get expr 3)]
              (if (not (is-atom? path-expr)) 0
                (if (not (str-eq? (ast-val kw-expr) "as")) 0
                  (if (not (is-atom? alias-expr)) 0
                    (let [pair (vector)]
                      (do (push pair (ast-val path-expr))
                          (push pair (ast-val alias-expr))
                          pair))))))))))))

(defn is-require? [expr]
  (> (count (parse-require expr)) 0))

;; Already module-mangled? (_m_alias_name) — do not re-prefix (nested requires).
(defn is-mangled? [name]
  (if (< (count name) 3) false
    (if (if (= (str-get name 0) 95)
          (if (= (str-get name 1) 109) (= (str-get name 2) 95) false)
          false)
      true
      false)))

;; ---- collect public defn names (skip already-mangled nested modules) ----

(defn collect-names [ast-list]
  (let [n (count ast-list) names (vector)]
    (loop [i 0]
      (if (>= i n) names
        (let [expr (get ast-list i)]
          (if (is-atom? expr)
            (recur (+ i 1))
            (let [head (get expr 0)
                  tag (if (is-atom? head) (ast-tag head) 99)]
              (if (= tag 10)
                (let [name-atom (get expr 1)]
                  (if (is-atom? name-atom)
                    (let [nm (ast-val name-atom)]
                      (if (is-mangled? nm)
                        (recur (+ i 1))
                        (do (push names nm)
                            (recur (+ i 1)))))
                    (recur (+ i 1))))
                (recur (+ i 1))))))))))

;; ---- rename: unqualified public names get prefix; keep others ----
;; alias-for-slash: when non-empty, also rewrite alias/name → prefix+name

(defn name-in-list? [name names]
  (let [n (count names)]
    (loop [i 0]
      (if (>= i n) false
        (if (str-eq? (get names i) name) true
          (recur (+ i 1)))))))

(defn rename-expr [expr prefix names alias-for-slash]
  (if (is-atom? expr)
    (if (= (ast-tag expr) 1)
      (let [name (ast-val expr)
            slash-pos (str-index-of name "/")]
        ;; Qualified alias/name only when slash is not at start (so "/" operator is safe)
        (if (> slash-pos 0)
          (let [al (str-slice name 0 slash-pos)
                rest (str-slice name (+ slash-pos 1) (count name))]
            (if (str-eq? al alias-for-slash)
              (make-atom 1 (str-concat prefix rest))
              expr))
          ;; Skip already-mangled (_m_...) and only rename local public names
          (if (is-mangled? name) expr
            (if (name-in-list? name names)
              (make-atom 1 (str-concat prefix name))
              expr))))
      expr)
    (let [n (count expr) new-expr (vector)]
      (do (push new-expr (rename-expr (get expr 0) prefix names alias-for-slash))
          (loop [i 1]
            (if (>= i n) new-expr
              (do (push new-expr (rename-expr (get expr i) prefix names alias-for-slash))
                  (recur (+ i 1)))))))))

(defn rename-module [ast-list prefix]
  (let [pub (collect-names ast-list)
        n (count ast-list)
        result (vector)]
    (loop [i 0]
      (if (>= i n) result
        (do (push result (rename-expr (get ast-list i) prefix pub ""))
            (recur (+ i 1)))))))

;; Rewrite alias/name in an AST using alias→prefix pairs.
;; pairs: vector of [alias prefix]
(defn find-prefix [alias pairs]
  (let [n (count pairs)]
    (loop [i 0]
      (if (>= i n) ""
        (let [p (get pairs i)]
          (if (str-eq? (get p 0) alias) (get p 1)
            (recur (+ i 1))))))))

(defn subst-qualified-expr [expr pairs]
  (if (is-atom? expr)
    (if (= (ast-tag expr) 1)
      (let [name (ast-val expr)
            slash-pos (str-index-of name "/")]
        ;; slash at 0 is the "/" operator, not a qualifier
        (if (<= slash-pos 0) expr
          (let [al (str-slice name 0 slash-pos)
                rest (str-slice name (+ slash-pos 1) (count name))
                pref (find-prefix al pairs)]
            (if (str-eq? pref "") expr
              (make-atom-keep-span expr 1 (str-concat pref rest))))))
      expr)
    (let [n (count expr) new-expr (vector)]
      (do (push new-expr (subst-qualified-expr (get expr 0) pairs))
          (loop [i 1]
            (if (>= i n) new-expr
              (do (push new-expr (subst-qualified-expr (get expr i) pairs))
                  (recur (+ i 1)))))))))

(defn subst-qualified [ast-list pairs]
  (let [n (count ast-list) result (vector)]
    (loop [i 0]
      (if (>= i n) result
        (do (push result (subst-qualified-expr (get ast-list i) pairs))
            (recur (+ i 1)))))))

;; Append all items from src onto dst (mutates dst)
(defn append-all [dst src]
  (let [n (count src)]
    (loop [i 0]
      (if (>= i n) dst
        (do (push dst (get src i))
            (recur (+ i 1)))))))

;; Host-compatible prefix: _m_<alias>_
(defn module-prefix [alias]
  (str-concat "_m_" (str-concat alias "_")))
