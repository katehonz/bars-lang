;; Richer traits: defaults + Self + multi-method + tcall shorthand.

(deftrait Show [show]
  ;; default display uses Self → filled per impl
  (default display [x]
    (tcall Show show Self x)))

(deftrait Num [add]
  (default double [x]
    (tcall Num add Self x x))
  (default inc [x]
    (tcall Num add Self x 1)))

(impl Show for i64
  (defn show [x] x))
  ;; display filled from default

(impl Show for Bool
  (defn show [b]
    (if b 1 0))
  (defn display [b]
    ;; override default
    (if b 11 10)))

(impl Num for i64
  (defn add [a b] (+ a b)))
  ;; double + inc from defaults

(defn main []
  (let [a (tcall Show show i64 7)
        b (tcall Show display i64 7)
        c (tcall Show display Bool true)
        d (tcall Show display Bool false)
        e (tcall Num double i64 21)
        f (tcall Num inc i64 41)]
    (do (println a)
        (println b)
        (println c)
        (println d)
        (println e)
        (println f)
        0)))
