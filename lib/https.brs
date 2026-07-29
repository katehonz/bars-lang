;; Bars Standard Library — HTTPS client (Phase 17.11)
;; HTTP/1.1 over TLS (lib/tls). Response parsing reused from lib/http.
;;
;; Response: vector [status-code body-string]; error: 0
;;
;;   (require "lib/https" :as https)
;;   (let [r (https/get-req "example.com" 443 "/")]
;;     (println (https/status r)))
;;
;; get-req/post verify the peer against the system CA store.
;; get-insecure/post-insecure skip verification — local dev only.

(require "lib/tls" :as tls)
(require "lib/http" :as http)

;; Read until close (empty chunk/0) or the 10MB cap; concat into acc.
(defn recv-until-close [h acc0]
  (loop [acc acc0]
    (if (>= (count acc) 10485760) acc
      (let [chunk (tls/recv h 8192)]
        (if (= chunk 0) acc
          (if (= (count chunk) 0) acc
            (recur (str-concat acc chunk))))))))

;; After headers, read body until Content-Length or connection close.
(defn finish-body [h headers body0]
  (let [cl (http/find-content-length headers)]
    (if (< cl 0)
      (let [body (recv-until-close h body0)]
        (http/mk-response (http/parse-status-line headers) body))
      (loop [b body0]
        (if (>= (count b) cl)
          (http/mk-response (http/parse-status-line headers) (str-slice b 0 cl))
          (let [chunk (tls/recv h 8192)]
            (if (= chunk 0)
              (http/mk-response (http/parse-status-line headers) b)
              (if (= (count chunk) 0)
                (http/mk-response (http/parse-status-line headers) b)
                (recur (str-concat b chunk))))))))))

(defn recv-response [h]
  (loop [acc ""]
    (let [chunk (tls/recv h 8192)]
      (if (= chunk 0)
        (if (= (count acc) 0) 0
          (http/mk-response 0 acc))
        (if (= (count chunk) 0)
          (if (= (count acc) 0) 0
            (http/mk-response 0 acc))
          (let [acc2 (str-concat acc chunk)
                sep (str-index-of acc2 "\r\n\r\n")]
            (if (< sep 0)
              (if (> (count acc2) 1048576)
                (http/mk-response 0 acc2)
                (recur acc2))
              (let [headers (str-slice acc2 0 sep)
                    body0 (str-slice acc2 (+ sep 4) (count acc2))]
                (finish-body h headers body0)))))))))

;; ---- public API ----

(defn request [method host port path body verify]
  (let [h (tls/connect host port verify)]
    (if (tls/ok? h)
      (let [req (http/build-request method host path body)
            sent (tls/send h req)]
        (if (< sent 0)
          (do (tls/close h) 0)
          (let [resp (recv-response h)]
            (do (tls/close h) resp))))
      0)))

(defn get-req [host port path]
  (request "GET" host port path "" 1))

(defn get-insecure [host port path]
  (request "GET" host port path "" 0))

(defn post [host port path body]
  (request "POST" host port path body 1))

(defn post-insecure [host port path body]
  (request "POST" host port path body 0))

;; Response accessors (same shape as lib/http responses)
(defn status [resp] (http/status resp))
(defn body [resp] (http/body resp))
(defn ok? [resp] (http/ok? resp))
