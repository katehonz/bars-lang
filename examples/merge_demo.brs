;; merge / dissoc / assoc-in (Phase 17.46)

(defn main []
  ;; merge: later wins; variadic
  (let [a (zipmap (vector 1 2) (vector 10 20))
        b (zipmap (vector 2 3) (vector 99 30))
        m (merge a b)]
    (println (map-get m 1))
    (println (map-get m 2))
    (println (map-get m 3))
    ;; input not mutated
    (println (map-get a 2)))
  (println (map-count (merge (zipmap (vector 1) (vector 1))
                             (zipmap (vector 2) (vector 2))
                             (zipmap (vector 3) (vector 3)))))
  ;; dissoc: keys removed from a clone
  (let [d (dissoc (zipmap (vector 1 2 3) (vector 10 20 30)) 2 3)]
    (println (map-count d))
    (println (map-get d 1))
    (println (map-get d 2)))
  ;; assoc-in: creates intermediate maps, input kept
  (let [base (zipmap (vector 1) (vector (zipmap (vector 5) (vector 50))))
        ai (assoc-in base (vector 1 6) 60)]
    (println (get-in ai (vector 1 6)))
    (println (get-in ai (vector 1 5)))
    (println (get-in base (vector 1 6))))
  ;; assoc-in into missing path
  (println (get-in (assoc-in (map) (vector 7 8 9) 42) (vector 7 8 9)))
  0)
