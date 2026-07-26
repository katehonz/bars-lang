;; Uses path dependency from Bars.toml
(require "pkg_lib" :as lib)

(defn main []
  (println (lib/greet "Bars"))
  (println (lib/answer)))
