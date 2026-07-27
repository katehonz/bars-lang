;; One-shot TCP echo server (accept one client, echo, exit).
;; Usage: ./net_echo_server   (listens on 18765)

(require "lib/net" :as net)

(defn main []
  (let [port 18765
        ln (net/listen port)]
    (if (net/ok? ln)
      (let [cl (net/accept ln)]
        (if (net/ok? cl)
          (let [msg (net/recv cl 4096)
                _ (if (= msg 0) 0 (net/send cl msg))]
            (do (net/close cl)
                (net/close ln)
                0))
          (do (net/close ln) 1)))
      1)))
