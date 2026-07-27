;; Bars Standard Library — TCP networking (Phase 14.7)
;; Thin wrappers over C runtime sockets. Sync only.
;;
;;   (require "lib/net" :as net)
;;   (let [fd (net/connect "127.0.0.1" 8080)]
;;     (net/send fd "hi")
;;     (println (net/recv fd 1024))
;;     (net/close fd))
;;
;; fd is i64; -1 means error for connect/listen/accept.
;; recv returns string or 0 on error; empty string on peer close.

(defn connect [host port]
  (bars_tcp_connect host port))

(defn listen [port]
  (bars_tcp_listen port))

(defn accept [listen-fd]
  (bars_tcp_accept listen-fd))

(defn send [fd data]
  (bars_tcp_send fd data))

(defn recv [fd max-len]
  (bars_tcp_recv fd max-len))

(defn close [fd]
  (bars_tcp_close fd))

(defn ok? [fd]
  (>= fd 0))
