;; Bars Standard Library — Vector functions
(load "lib/core.brs")

(defn last [^i64 vec]
  (let [n (count vec)]
    (if (= n 0)
      0
      (get vec (- n 1)))))

(defn rest [^i64 vec]
  (let [n (count vec)]
    (rest-helper vec 1 n (vector))))

(defn rest-helper [^i64 vec ^i64 i ^i64 n ^i64 result]
  (if (= i n)
    result
    (do
      (push result (get vec i))
      (rest-helper vec (+ i 1) n result))))

(defn take [^i64 vec ^i64 n]
  (take-helper vec 0 n (vector)))

(defn take-helper [^i64 vec ^i64 i ^i64 n ^i64 result]
  (if (or (= i n) (>= i (count vec)))
    result
    (do
      (push result (get vec i))
      (take-helper vec (+ i 1) n result))))

(defn drop [^i64 vec ^i64 n]
  (drop-helper vec n (count vec) (vector)))

(defn drop-helper [^i64 vec ^i64 i ^i64 n ^i64 result]
  (if (= i n)
    result
    (do
      (push result (get vec i))
      (drop-helper vec (+ i 1) n result))))

(defn reverse [^i64 vec]
  (reverse-helper vec (- (count vec) 1) (vector)))

(defn reverse-helper [^i64 vec ^i64 i ^i64 result]
  (if (< i 0)
    result
    (do
      (push result (get vec i))
      (reverse-helper vec (- i 1) result))))

(defn contains? [^i64 vec ^i64 val]
  (contains-helper vec 0 (count vec) val))

(defn contains-helper [^i64 vec ^i64 i ^i64 n ^i64 val]
  (if (= i n)
    0
    (if (= (get vec i) val)
      1
      (contains-helper vec (+ i 1) n val))))

(defn index-of [^i64 vec ^i64 val]
  (index-of-helper vec 0 (count vec) val))

(defn index-of-helper [^i64 vec ^i64 i ^i64 n ^i64 val]
  (if (= i n)
    -1
    (if (= (get vec i) val)
      i
      (index-of-helper vec (+ i 1) n val))))
