;; Bars async package stub — Phase 14.4
;; Async is NOT in the language core. This module defines a small
;; Future convention you can build on (no higher-order poll runtime yet).
;;
;; Future representation (vector):
;;   [0]        Pending
;;   [1 value]  Ready
;;
;;   (require "lib/async" :as async)
;;   (async/ready 42)
;;   (async/pending)

(defn pending []
  (let [v (vector)]
    (do (push v 0) v)))

(defn ready [val]
  (let [v (vector)]
    (do (push v 1) (push v val) v)))

(defn ready? [fut]
  (= (get fut 0) 1))

(defn pending? [fut]
  (= (get fut 0) 0))

(defn unwrap [fut]
  (if (ready? fut) (get fut 1) 0))

;; Map a ready value by adding n (self-host safe, no function values).
(defn map-add [fut n]
  (if (ready? fut)
    (ready (+ (unwrap fut) n))
    fut))

;; Join two ready futures with +; if either pending → pending.
(defn add-ready [a b]
  (if (if (ready? a) (ready? b) false)
    (ready (+ (unwrap a) (unwrap b)))
    (pending)))
