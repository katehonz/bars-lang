;; Bars Standard Library — HTTP/1.1 server helpers (Phase 17.4)
;; Sync, one-connection-at-a-time primitives over lib/net. No TLS.
;;
;; Request:  [method path body]   (strings; body may be "")
;; Response: raw HTTP message string ready for net/send
;;
;;   (require "lib/http_server" :as hs)
;;   (require "lib/net" :as net)
;;
;;   (defn main []
;;     (let [ln (net/listen 8080)
;;           cl (net/accept ln)
;;           raw (net/recv cl 8192)
;;           req (hs/parse-request raw)
;;           resp (hs/ok "hello")]
;;       (do (net/send cl resp)
;;           (net/close cl)
;;           (net/close ln)
;;           0)))

(require "lib/net" :as net)

;; Re-export common net ops so apps can `(require "lib/http_server" :as hs)` alone
;; (duplicate require of lib/net from the same program is rejected by modules).
(defn listen [port] (net/listen port))
(defn ok? [fd] (net/ok? fd))
(defn close [fd] (net/close fd))
(defn send [fd data] (net/send fd data))
(defn recv [fd n] (net/recv fd n))

(defn int-str [n] (str-from-i64 n))

(defn crlf [] "\r\n")
(defn crlf2 [] "\r\n\r\n")

;; ---- request parse ----

(defn parse-request-line [line]
  ;; "GET /path HTTP/1.1" → [method path]
  (let [sp1 (str-index-of line " ")]
    (if (< sp1 0) 0
      (let [method (str-slice line 0 sp1)
            rest (str-slice line (+ sp1 1) (count line))
            sp2 (str-index-of rest " ")]
        (if (< sp2 0)
          (let [v (vector)]
            (do (push v method) (push v rest) v))
          (let [path (str-slice rest 0 sp2)
                v (vector)]
            (do (push v method) (push v path) v)))))))

(defn parse-request [raw]
  ;; → [method path body] or 0 on failure
  (if (if (= raw 0) true (= (count raw) 0))
    0
    (let [sep (str-index-of raw (crlf2))
          head (if (< sep 0) raw (str-slice raw 0 sep))
          body (if (< sep 0) ""
                 (str-slice raw (+ sep 4) (count raw)))
          nl (str-index-of head (crlf))
          line (if (< nl 0) head (str-slice head 0 nl))
          mp (parse-request-line line)]
      (if (= mp 0) 0
        (let [v (vector)]
          (do (push v (get mp 0))
              (push v (get mp 1))
              (push v body)
              v))))))

(defn method [req] (get req 0))
(defn path [req] (get req 1))
(defn body [req] (get req 2))

(defn method-eq? [req m]
  (let [a (method req)]
    (if (!= (count a) (count m)) false
      (= (str-starts-with? a m) 1))))

(defn path-eq? [req p]
  (let [a (path req)]
    (if (!= (count a) (count p)) false
      (= (str-starts-with? a p) 1))))

;; ---- response builders ----

(defn response [status reason body]
  (let [blen (count body)]
    (str-concat "HTTP/1.1 "
      (str-concat (int-str status)
        (str-concat " "
          (str-concat reason
            (str-concat (crlf)
              (str-concat "Content-Length: "
                (str-concat (int-str blen)
                  (str-concat (crlf)
                    (str-concat "Connection: close"
                      (str-concat (crlf2) body))))))))))))

(defn ok [body]
  (response 200 "OK" body))

(defn created [body]
  (response 201 "Created" body))

(defn bad-request [body]
  (response 400 "Bad Request" body))

(defn not-found [body]
  (response 404 "Not Found" body))

(defn server-error [body]
  (response 500 "Internal Server Error" body))

(defn text-ok [body]
  ;; Alias of ok (plain body; Content-Type not set — keep minimal)
  (ok body))

;; ---- one-shot serve helpers ----

;; Listen → accept one client → return [client-fd request] or 0.
;; Caller must net/close both listen fd and client (listen returned separately).
(defn accept-request [listen-fd]
  (let [cl (net/accept listen-fd)]
    (if (net/ok? cl)
      (let [raw (net/recv cl 16384)
            req (parse-request raw)]
        (if (= req 0)
          (let [v (vector)]
            (do (push v cl) (push v 0) v))
          (let [v (vector)]
            (do (push v cl) (push v req) v))))
      0)))

;; Send response string and close client fd.
(defn reply [client-fd resp]
  (do (net/send client-fd resp)
      (net/close client-fd)
      0))

;; Full one-shot: listen on port, accept one, send fixed response, close all.
;; Returns 0 on success, 1 on listen/accept failure.
(defn serve-once [port resp]
  (let [ln (net/listen port)]
    (if (net/ok? ln)
      (let [pack (accept-request ln)]
        (if (= pack 0)
          (do (net/close ln) 1)
          (let [cl (get pack 0)
                _ (reply cl resp)]
            (do (net/close ln) 0))))
      1)))
