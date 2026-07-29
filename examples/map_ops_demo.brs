;; map-contains? / map-keys / map-values demo
;; Expected output:
;;   1
;;   1
;;   0
;;   3
;;   100
;;   200
;;   1
(require "lib/map" :as m)
(defn main []
  (let [scores (map)
        _ (map-set scores 1 100)
        _ (map-set scores 2 200)
        _ (map-set scores 3 0)]
    (do
      (println (map-contains? scores 1))
      (println (map-contains? scores 3))   ;; key exists despite value 0
      (println (map-contains? scores 9))
      (println (count (map-keys scores)))
      (println (map-get scores 1))
      (println (map-get scores 2))
      (println (m/map-has? scores 3)))))
