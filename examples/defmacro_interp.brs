;; Macro interpreter demo — non-template bodies (list/cons/if at expand-time).
;; Complements defmacro_demo (syntax-quote templates only).

(defmacro my-or [a b]
  (list (quote if) a a b))

(defmacro thrice [x]
  ;; `+` is binary in Bars; nest or use `*`
  (let [v x]
    (list (quote *) v 3)))

(defmacro when-pos [n body]
  (list (quote if)
        (list (quote >) n 0)
        body
        0))

(defmacro pick [c a b]
  (list (quote if) c a b))

(defn main []
  ;; Use bool cond + same-type branches to keep soft typecheck clean.
  (println (pick false 42 0))
  (println (pick true 7 99))
  (println (my-or 7 99))
  (println (thrice 5))
  (println (when-pos 3 100))
  (println (when-pos 0 100))
  0)
