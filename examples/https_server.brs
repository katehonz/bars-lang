;; Minimal one-shot HTTPS server (GET → 200 hello) over TLS (Phase 17.54).
;; Usage: ./https_server <cert.pem> <key.pem>   (listens on 18443)

(require "lib/tls" :as tls)

(defn main []
  (let [port 18443
        cert (args-get 1)
        key (args-get 2)
        srv (tls/listen port cert key)]
    (if (tls/ok? srv)
      (let [cl (tls/accept srv)]
        (if (tls/ok? cl)
          (let [_ (tls/recv cl 4096)
                resp "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello"]
            (do (tls/send cl resp)
                (tls/close cl)
                (tls/close-server srv)
                0))
          (do (println "accept failed")
              (println (tls/last-error))
              (tls/close-server srv)
              1)))
      (do (println "listen failed")
          (println (tls/last-error))
          1))))
