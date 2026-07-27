;; Bars Standard Library — HTTP/1.1 client (Phase 15.1)
;; Pure Bars over lib/net (sync TCP). No TLS.
;;
;; Response: vector [status-code body-string]
;; Error: 0
;;
;;   (require "lib/http" :as http)
;;   (let [r (http/get-req "127.0.0.1" 8080 "/")]
;;     (println (http/status r))
;;     (println (http/body r)))
;;
;; Note: named get-req (not get) so it does not shadow vector get in this module.

(require "lib/net" :as net)

;; ---- helpers ----

(defn int-str [n]
  (let [d "0123456789"]
    (if (< n 0) (str-concat "-" (int-str (- 0 n)))
      (if (< n 10) (str-slice d n (+ n 1))
        (str-concat (int-str (/ n 10)) (str-slice d (% n 10) (+ (% n 10) 1)))))))

(defn parse-int [s]
  (let [n (count s)]
    (loop [i 0 acc 0 started 0]
      (if (>= i n) acc
        (let [c (str-get s i)]
          (if (if (>= c 48) (<= c 57) false)
            (recur (+ i 1) (+ (* acc 10) (- c 48)) 1)
            (if (= started 1) acc
              (recur (+ i 1) acc 0))))))))

(defn crlf []
  "\r\n")

(defn crlf2 []
  "\r\n\r\n")

;; ---- request builder ----

(defn build-request [method host path body]
  (let [blen (count body)
        has-body (if (> blen 0) 1 0)
        req0 (str-concat method (str-concat " " (str-concat path " HTTP/1.1")))
        req1 (str-concat req0 (str-concat (crlf) (str-concat "Host: " host)))
        req2 (str-concat req1 (str-concat (crlf) "Connection: close"))
        req3 (if (= has-body 1)
               (str-concat req2
                 (str-concat (crlf)
                   (str-concat "Content-Length: "
                     (str-concat (int-str blen)
                       (str-concat (crlf) "Content-Type: text/plain")))))
               req2)
        head (str-concat req3 (crlf2))]
    (if (= has-body 1) (str-concat head body) head)))

;; ---- response parse ----

(defn parse-status-line [headers]
  ;; "HTTP/1.1 200 OK" → 200
  (let [sp (str-index-of headers " ")]
    (if (< sp 0) 0
      (let [rest (str-slice headers (+ sp 1) (count headers))]
        (parse-int rest)))))

(defn find-content-length [headers]
  (let [p1 (str-index-of headers "Content-Length")
        p2 (str-index-of headers "content-length")
        p (if (>= p1 0) p1 p2)]
    (if (< p 0) -1
      (let [rest (str-slice headers (+ p 14) (count headers))
            after-colon (str-trim rest)]
        (if (if (> (count after-colon) 0) (= (str-get after-colon 0) 58) false)
          (parse-int (str-trim (str-slice after-colon 1 (count after-colon))))
          (parse-int after-colon))))))

(defn mk-response [status body]
  (let [v (vector)]
    (do (push v status) (push v body) v)))

(defn status [resp]
  (get resp 0))

(defn body [resp]
  (get resp 1))

(defn ok? [resp]
  (if (= resp 0) false
    (let [s (status resp)]
      (if (>= s 200) (< s 300) false))))

;; Read until EOF (empty chunk) or error; concat into acc.
;; Capped at 10MB to prevent memory exhaustion from malicious servers.
(defn recv-until-close [fd acc0]
  (loop [acc acc0]
    (if (>= (count acc) 10485760) acc
      (let [chunk (net/recv fd 8192)]
        (if (= chunk 0) acc
          (if (= (count chunk) 0) acc
            (recur (str-concat acc chunk))))))))

;; After headers, read body until Content-Length or connection close.
(defn finish-body [fd headers body0]
  (let [cl (find-content-length headers)]
    (if (< cl 0)
      (let [body (recv-until-close fd body0)]
        (mk-response (parse-status-line headers) body))
      (loop [b body0]
        (if (>= (count b) cl)
          (mk-response (parse-status-line headers) (str-slice b 0 cl))
          (let [chunk (net/recv fd 8192)]
            (if (= chunk 0)
              (mk-response (parse-status-line headers) b)
              (if (= (count chunk) 0)
                (mk-response (parse-status-line headers) b)
                (recur (str-concat b chunk))))))))))

(defn recv-response [fd]
  (loop [acc ""]
    (let [chunk (net/recv fd 8192)]
      (if (= chunk 0)
        (if (= (count acc) 0) 0
          (mk-response 0 acc))
        (if (= (count chunk) 0)
          (if (= (count acc) 0) 0
            (mk-response 0 acc))
          (let [acc2 (str-concat acc chunk)
                sep (str-index-of acc2 (crlf2))]
            (if (< sep 0)
              (if (> (count acc2) 1048576)
                (mk-response 0 acc2)
                (recur acc2))
              (let [headers (str-slice acc2 0 sep)
                    body0 (str-slice acc2 (+ sep 4) (count acc2))]
                (finish-body fd headers body0)))))))))

;; ---- public API ----

(defn request [method host port path body]
  (let [fd (net/connect host port)]
    (if (net/ok? fd)
      (let [req (build-request method host path body)
            sent (net/send fd req)]
        (if (< sent 0)
          (do (net/close fd) 0)
          (let [resp (recv-response fd)]
            (do (net/close fd) resp))))
      0)))

(defn get-req [host port path]
  (request "GET" host port path ""))

(defn post [host port path body]
  (request "POST" host port path body))
