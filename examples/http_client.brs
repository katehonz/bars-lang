;; HTTP GET client against loopback http_server (:18766).
;; Usage: ./http_server & ; ./http_client  → prints status + body

(require "lib/http" :as http)

(defn main []
  (let [r (http/get-req "127.0.0.1" 18766 "/")]
    (if (= r 0)
      (do (println "http-fail") 1)
      (do (println (http/status r))
          (println (http/body r))
          0))))
