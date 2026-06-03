;; Bars Standard Library — Core functions
;; These are written in Bars itself and compiled with the toolchain.
;; NOTE: Higher-order vector functions (map-vec, filter-vec, reduce-vec)
;;       work only in the REPL/Cranelift backend where function pointers
;;       are supported. In QBE AOT mode, use inline loops or recursion.

;; ---------------------------------------------------------------------------
;; Numeric helpers
;; ---------------------------------------------------------------------------

(defn inc [^i64 n] (+ n 1))
(defn dec [^i64 n] (- n 1))

(defn zero? [^i64 n] (= n 0))
(defn pos?  [^i64 n] (> n 0))
(defn neg?  [^i64 n] (< n 0))

(defn or [^bool a ^bool b]
  (if a true b))

(defn and [^bool a ^bool b]
  (if a b false))

(defn even? [^i64 n] (= (% n 2) 0))
(defn odd?  [^i64 n] (= (% n 2) 1))

(defn abs [^i64 n]
  (if (< n 0)
    (- 0 n)
    n))

(defn max [^i64 a ^i64 b]
  (if (> a b) a b))

(defn min [^i64 a ^i64 b]
  (if (< a b) a b))

;; ---------------------------------------------------------------------------
;; Vector helpers
;; ---------------------------------------------------------------------------

(defn empty? [^i64 vec]
  (= (count vec) 0))

(defn nth [^i64 vec ^i64 idx]
  (get vec idx))

(defn first [^i64 vec]
  (get vec 0))

;; ---------------------------------------------------------------------------
;; Range
;; ---------------------------------------------------------------------------

(defn range-helper [^i64 start ^i64 end ^i64 step ^i64 result]
  (if (>= start end)
    result
    (do
      (push result start)
      (range-helper (+ start step) end step result))))

(defn range [^i64 start ^i64 end]
  (range-helper start end 1 (vector)))

(defn range-step [^i64 start ^i64 end ^i64 step]
  (range-helper start end step (vector)))

;; ---------------------------------------------------------------------------
;; Higher-order functions
;; ---------------------------------------------------------------------------
;; The built-in `map`, `filter`, and `reduce` are inlined by the compiler
;; into loops and work in all backends (QBE, Cranelift, LLVM) with both
;; named functions and inline lambdas:
;;
;;   (map inc [1 2 3])
;;   (filter even? [1 2 3 4 5])
;;   (reduce add 0 [1 2 3])
;;   (map (fn [x] (* x 2)) [1 2 3])
