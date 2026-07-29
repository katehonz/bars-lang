;; Persistent / COW collection helpers (Phase 17.14).
;; Thin names over runtime builtins — originals are never mutated.
;;
;; Vectors:
;;   (vector-clone v)     → shallow copy
;;   (conj v x)           → copy + append x
;;   (v-assoc v i x)      → copy with index i = x
;;   (v-pop v)            → copy without last element
;;
;; Maps:
;;   (map-clone m)        → shallow copy
;;   (map-assoc m k v)    → copy with k → v
;;
;; Builtins are wired in LLVM/C backends; this package is for docs + aliasing.

(defn clone [v] (vector-clone v))
(defn assoc [v i x] (v-assoc v i x))
(defn m-assoc [m k v] (map-assoc m k v))
(defn m-clone [m] (map-clone m))
