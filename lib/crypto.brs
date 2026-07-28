;; Bars Standard Library — Crypto (Phase 17.3)
;; SHA-256 in the C runtime; hex digest as a string.
;;
;;   (require "lib/crypto" :as crypto)
;;   (crypto/sha256 "abc")
;;   ;; → "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

(defn sha256 [s]
  (bars_sha256 s))
