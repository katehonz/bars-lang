;; Bars Standard Library — TLS transport (Phase 17.11)
;; OpenSSL-backed client over bars_tls_* (runtime/bars_tls.c).
;; Mirrors the lib/net TCP API so higher layers can switch transports.
;;
;;   (require "lib/tls" :as tls)
;;   (let [h (tls/connect "example.com" 443 1)]
;;     (tls/send h "GET / HTTP/1.1\r\n…")
;;     (println (tls/recv h 8192))
;;     (tls/close h))
;;
;; verify=1 → peer verified against the system CA store (production).
;; verify=0 → no verification (local dev / self-signed servers only!).
;;
;; Note: requiring this module makes the linker pull runtime/bars_tls.o
;; and OpenSSL (-lssl -lcrypto) — build.brs handles it automatically.

;; handle is i64; -1 means error (TCP connect, CA paths, or handshake failed).
(defn connect [host port verify]
  (bars_tls_connect host port verify))

(defn ok? [h]
  (if (>= h 0) true false))

;; bytes sent, or -1 on error
(defn send [h data]
  (bars_tls_send h data))

;; string or 0 on error/close (same contract as net/recv)
(defn recv [h max-len]
  (bars_tls_recv h max-len))

(defn close [h]
  (bars_tls_close h))
