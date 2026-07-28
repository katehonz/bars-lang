;; Top-level def → real globals (Phase 17.5)
;; Globals are initialized once (in __bars_init_globals) and are
;; readable/writable from every function. Note: do not shadow a global
;; name with a local of the same name.
(def max-items 42)
(def nums (vector 1 2 3))
(def greeting "hello")

(defn get-limit []
  max-items)

(defn add-num [n]
  (push nums n))

(defn main []
  (do (println (get-limit))
      (println (count nums))
      (add-num 4)
      (println (count nums))
      (println (get nums 3))
      (println greeting)))
