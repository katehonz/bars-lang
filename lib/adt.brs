;; Bars standard library — Algebraic Data Types
;; Option and Result types with helper functions

(deftype Option [Some i64] [None])

(defn is-some? [opt]
  (match opt
    (Some _) true
    None false))

(defn is-none? [opt]
  (match opt
    (Some _) false
    None true))

(defn unwrap-or [opt default]
  (match opt
    (Some v) v
    None default))

;; Result type for error handling
(deftype Result [Ok i64] [Err i64])

(defn is-ok? [res]
  (match res
    (Ok _) true
    (Err _) false))

(defn is-err? [res]
  (match res
    (Ok _) false
    (Err _) true))

(defn unwrap-ok [res]
  (match res
    (Ok v) v
    (Err _) 0))
