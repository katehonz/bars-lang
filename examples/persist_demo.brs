;; Persistent / COW vector & map ops (Phase 17.14).
;; Originals are never mutated by conj / v-assoc / map-assoc / v-pop.

(defn main []
  (let [a (vector)
        _ (push a 1)
        _ (push a 2)
        b (conj a 3)
        c (v-assoc a 0 9)
        d (v-pop b)]
    (do (println (count a))   ;; 2 — original
        (println (get a 0))   ;; 1
        (println (count b))   ;; 3
        (println (get b 2))   ;; 3
        (println (get c 0))   ;; 9
        (println (get a 0))   ;; 1 — still original
        (println (count d))   ;; 2
        (let [m (map)
              _ (map-set m 1 10)
              m2 (map-assoc m 2 20)]
          (do (println (map-count m))    ;; 1
              (println (map-get m2 2))   ;; 20
              (println (map-get m 2))    ;; 0 — original untouched
              0)))))
