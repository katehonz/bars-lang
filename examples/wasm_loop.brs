;; Loop/recur sum 0..9 = 45 for WASM CFG smoke.

(defn sum-to [n]
  (loop [i 0 acc 0]
    (if (>= i n)
      acc
      (recur (+ i 1) (+ acc i)))))

(defn main []
  (sum-to 10))
