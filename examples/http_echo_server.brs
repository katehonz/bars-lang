;; One-shot HTTP server: responds 200 with body = request body (POST)
;; or fixed "ok" for empty body. Port 18767.
;; Usage: ./http_echo_server

(require "lib/net" :as net)

(defn int-str [n] (str-from-i64 n))

(defn main []
  (let [port 18767
        ln (net/listen port)]
    (if (net/ok? ln)
      (let [cl (net/accept ln)]
        (if (net/ok? cl)
          (let [raw (net/recv cl 8192)
                sep (if (= raw 0) -1 (str-index-of raw "\r\n\r\n"))
                body (if (< sep 0) "ok"
                       (let [b (str-slice raw (+ sep 4) (count raw))]
                         (if (= (count b) 0) "ok" b)))
                resp (str-concat "HTTP/1.1 200 OK\r\nContent-Length: "
                       (str-concat (int-str (count body))
                         (str-concat "\r\nConnection: close\r\n\r\n" body)))]
            (do (net/send cl resp)
                (net/close cl)
                (net/close ln)
                0))
          (do (net/close ln) 1)))
      1)))
