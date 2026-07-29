;; not-any? / not-every? (Phase 17.36)

(defn pos? [n] (> n 0))
(defn even? [n] (= (% n 2) 0))

(defn main []
  (println (not-any? pos? [-1 0 -2]))
  (println (not-any? pos? [-1 3 0]))
  (println (not-every? pos? [1 2 3]))
  (println (not-every? pos? [1 0 3]))
  (println (not-every? even? [2 4 5]))
  0)
