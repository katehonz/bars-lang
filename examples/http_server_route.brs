;; HTTP server with path routing via lib/http_server (Phase 17.4)
;; Usage: ./http_server_route & ; curl -s localhost:18768/ ; curl -s localhost:18768/ping
;; One connection per run (one-shot).
(require "lib/http_server" :as hs)

(defn handle [req]
  (if (= req 0)
    (hs/bad-request "bad request")
    (if (hs/path-eq? req "/")
      (hs/ok "home")
      (if (hs/path-eq? req "/ping")
        (hs/ok "pong")
        (hs/not-found "nope")))))

(defn main []
  (let [port 18768
        ln (hs/listen port)]
    (if (hs/ok? ln)
      (let [pack (hs/accept-request ln)]
        (if (= pack 0)
          (do (hs/close ln) 1)
          (let [cl (get pack 0)
                req (get pack 1)
                resp (handle req)]
            (do (hs/reply cl resp)
                (hs/close ln)
                0))))
      1)))
