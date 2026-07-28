;; SHA-256 via lib/crypto (Phase 17.3) — known test vectors.
(require "lib/crypto" :as crypto)

(defn main []
  (do (println (crypto/sha256 ""))
      (println (crypto/sha256 "abc"))
      (println (crypto/sha256 "The quick brown fox jumps over the lazy dog"))))
