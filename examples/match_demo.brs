(defn handle-result [r]
  (match r
    0 (println 0)
    1 (println 1)
    _ (println 999)))

(defn main []
  (handle-result 0)
  (handle-result 1)
  (handle-result 42)
  0)
