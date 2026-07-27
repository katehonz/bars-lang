;; TCP client: connect to 127.0.0.1:18765, send "ping", print reply.
;; Usage: ./net_client   (run after net_echo_server is listening)

(require "lib/net" :as net)

(defn main []
  (let [fd (net/connect "127.0.0.1" 18765)]
    (if (net/ok? fd)
      (let [_ (net/send fd "ping")
            r (net/recv fd 64)]
        (do (if (= r 0)
              (println "recv-fail")
              (println r))
            (net/close fd)
            0))
      (do (println "connect-fail")
          1))))
