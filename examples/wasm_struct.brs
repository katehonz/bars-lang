;; Minimal WASM struct test — uses raw fieldload/fieldstore
;; Alloc is a no-op in WASM backend (returns 0), but fieldload/store work

(defstruct Point [x y])

(defn main []
  ;; This will allocate (returns 0 in WASM) but fieldstore/fieldload use real memory
  (let [p (Point 42 99)
        a (.x p)
        b (.y p)]
    (+ a b)))
