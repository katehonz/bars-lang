;; Pure-integer factorial for WASM backend (no println).
;; BARS_BACKEND_WASM=1 ./bars-self examples/wasm_fact.brs /tmp/f
;; → /tmp/f.wat  (main returns 120)

(defn factorial [n]
  (if (<= n 1)
    1
    (* n (factorial (- n 1)))))

(defn main []
  (factorial 5))
