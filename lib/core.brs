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

(defn or [^i64 a ^i64 b]
  (if a 1 b))

(defn and [^i64 a ^i64 b]
  (if a b 0))

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
;; Higher-order functions over vectors (REPL/Cranelift only)
;; ---------------------------------------------------------------------------

;; (defn map-vec-helper [^i64 f ^i64 vec ^i64 i ^i64 n ^i64 result]
;;   (if (= i n)
;;     result
;;     (do
;;       (push result (f (get vec i)))
;;       (map-vec-helper f vec (+ i 1) n result))))
;;
;; (defn map-vec [^i64 f ^i64 vec]
;;   (map-vec-helper f vec 0 (count vec) (vector)))
;;
;; (defn filter-vec-helper [^i64 f ^i64 vec ^i64 i ^i64 n ^i64 result]
;;   (if (= i n)
;;     result
;;     (do
;;       (let [item (get vec i)]
;;         (when (f item)
;;           (push result item)))
;;       (filter-vec-helper f vec (+ i 1) n result))))
;;
;; (defn filter-vec [^i64 f ^i64 vec]
;;   (filter-vec-helper f vec 0 (count vec) (vector)))
;;
;; (defn reduce-vec-helper [^i64 f ^i64 vec ^i64 i ^i64 n ^i64 acc]
;;   (if (= i n)
;;     acc
;;     (reduce-vec-helper f vec (+ i 1) n (f acc (get vec i)))))
;;
;; (defn reduce-vec [^i64 f ^i64 vec ^i64 init]
;;   (reduce-vec-helper f vec 0 (count vec) init))
