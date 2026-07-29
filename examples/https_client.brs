;; HTTPS client over TLS (Phase 17.11) — loopback against openssl s_server.
;; Run with a local self-signed server on 127.0.0.1:18443 (see selfhost-test).
(require "lib/https" :as https)

(defn main []
  (let [r (https/get-insecure "127.0.0.1" 18443 "/")]
    (if (= r 0)
      (do (println 0) 1)
      (do (println (https/status r))
          0))))
