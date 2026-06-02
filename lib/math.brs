;; Bars Standard Library — Math functions
(load "lib/core.brs")

(defn square [^i64 n] (* n n))
(defn cube   [^i64 n] (* n (* n n)))

(defn gcd [^i64 a ^i64 b]
  (if (= b 0)
    a
    (gcd b (% a b))))

(defn lcm [^i64 a ^i64 b]
  (/ (abs (* a b)) (gcd a b)))

(defn factorial [^i64 n]
  (if (<= n 1)
    1
    (* n (factorial (- n 1)))))

(defn fib [^i64 n]
  (if (<= n 1)
    n
    (+ (fib (- n 1)) (fib (- n 2)))))

(defn sum [^i64 vec]
  (let [n (count vec)]
    (sum-helper vec 0 n 0)))

(defn sum-helper [^i64 vec ^i64 i ^i64 n ^i64 acc]
  (if (= i n)
    acc
    (sum-helper vec (+ i 1) n (+ acc (get vec i)))))

(defn product [^i64 vec]
  (let [n (count vec)]
    (product-helper vec 0 n 1)))

(defn product-helper [^i64 vec ^i64 i ^i64 n ^i64 acc]
  (if (= i n)
    acc
    (product-helper vec (+ i 1) n (* acc (get vec i)))))
