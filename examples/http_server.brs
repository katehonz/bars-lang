;; Minimal one-shot HTTP/1.1 server (GET → 200 hello).
;; Usage: ./http_server   (listens on 18766)

(require "lib/net" :as net)

(defn main []
  (let [port 18766
        ln (net/listen port)]
    (if (net/ok? ln)
      (let [cl (net/accept ln)]
        (if (net/ok? cl)
          (let [_ (net/recv cl 4096)
                resp "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello"]
            (do (net/send cl resp)
                (net/close cl)
                (net/close ln)
                0))
          (do (net/close ln) 1)))
      1)))
