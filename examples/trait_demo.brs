;; Phase 14.4 — traits via deftrait / impl / trait-call
;; Methods compile to Trait_method_Type functions.

(deftrait Show [show])

(impl Show for i64
  (defn show [x]
    x))

(impl Show for Bool
  (defn show [b]
    (if b 1 0)))

(defconst ANSWER 42)

(defn main []
  (let [a (trait-call Show show i64 7)
        b (trait-call Show show Bool true)
        c (trait-call Show show Bool false)
        d (ANSWER)]
    (do (println a)
        (println b)
        (println c)
        (println d)
        0)))
