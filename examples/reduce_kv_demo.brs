;; update-in / reduce-kv / keys / vals (Phase 17.47)

(defn main []
  ;; update-in: f over the value at the path
  (let [m (assoc-in (map) (vector 1 2) 10)
        u (update-in m (vector 1 2) (fn [x] (+ x 5)))]
    (println (get-in u (vector 1 2))))
  ;; missing path: f gets 0
  (println (get-in (update-in (map) (vector 7 8) (fn [x] (+ x 1))) (vector 7 8)))
  ;; keys / vals aliases
  (let [m2 (zipmap (vector 1 2 3) (vector 10 20 30))]
    (println (count (keys m2)))
    (println (count (vals m2))))
  ;; reduce-kv: sum of values, key count, sum of keys
  (let [m3 (zipmap (vector 1 2 3) (vector 10 20 30))
        s (reduce-kv (fn [acc k v] (+ acc v)) 0 m3)
        c (reduce-kv (fn [acc k v] (+ acc 1)) 0 m3)
        ks (reduce-kv (fn [acc k v] (+ acc k)) 0 m3)]
    (println s)
    (println c)
    (println ks))
  ;; reduce-kv on empty map → init
  (println (reduce-kv (fn [acc k v] 99) 7 (map)))
  0)
