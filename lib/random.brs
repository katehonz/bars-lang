;; Bars Standard Library — Random (Phase 14.1)
;; libc rand; seed for reproducible tests.
;;
;;   (require "lib/random" :as rng)
;;   (rng/seed! 42)
;;   (rng/rand-int 10)   ; 0..9

(defn seed! [s]
  (bars_srand s))

;; Raw libc rand() value (0 .. RAND_MAX).
(defn raw []
  (bars_rand))

;; Integer in [0, n). If n <= 0 returns 0.
(defn rand-int [n]
  (if (<= n 0) 0
    (% (bars_rand) n)))

;; Inclusive range [lo, hi]. If hi < lo returns lo.
(defn rand-range [lo hi]
  (if (< hi lo) lo
    (+ lo (rand-int (+ (- hi lo) 1)))))
