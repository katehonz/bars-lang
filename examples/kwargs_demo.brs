;; Keyword-argument pack demo (Phase 17.3c)
(require "lib/kw" :as kw)

(defn greet [msg opts]
  (let [name (kw/lookup-or opts "name" "world")
        times (kw/lookup-or opts "times" 1)]
    (do
      (println msg)
      (println name)
      (println times)
      (if (kw/has? opts "name") 1 0))))

(defn main []
  (let [opts (kwargs :name "Ada" :times 3)]
    (do
      (greet "hello" opts)
      (greet "hi" (kwargs :times 2))
      0)))
