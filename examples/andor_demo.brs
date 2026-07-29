;; Built-in `and` / `or` macros (Phase 17.16) — short-circuit to nested if.

(defn main []
  (println (if (and true true) 1 0))
  (println (if (and true false) 1 0))
  (println (if (and true true true) 1 0))
  (println (if (or false false) 1 0))
  (println (if (or false true) 1 0))
  (println (if (or false false true) 1 0))
  ;; Last value: (and 1 2 3) → 3, (or 0 0 7) — 0 is truthy in Bars; use false
  (println (and 1 2 3))
  (println (or false false 7))
  (println (if (and) 1 0))
  (println (if (or) 1 0))
  0)
