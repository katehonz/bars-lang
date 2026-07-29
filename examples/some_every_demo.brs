;; some / every? (Phase 17.35)

(defn pos? [n] (> n 0))
(defn even? [n] (= (% n 2) 0))

(defn main []
  ;; some → first truthy pred result (here the boolean 1)
  (println (some pos? [0 -1 3 -2]))
  (println (some pos? [-1 -2 0]))
  ;; every?
  (println (every? pos? [1 2 3]))
  (println (every? pos? [1 0 3]))
  (println (every? even? [2 4 6]))
  ;; inline fn
  (println (some (fn [x] (if (> x 10) x 0)) [1 5 12 3]))
  0)
