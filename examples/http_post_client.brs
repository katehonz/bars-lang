;; HTTP POST client against http_echo_server (:18767).
;; Usage: ./http_echo_server & ; ./http_post_client  → 200 / ping

(require "lib/http" :as http)

(defn main []
  (let [r (http/post "127.0.0.1" 18767 "/echo" "ping")]
    (if (= r 0)
      (do (println "http-fail") 1)
      (do (println (http/status r))
          (println (http/body r))
          0))))
