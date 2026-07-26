;; Bars Standard Library — Time (Phase 14.1)
;;
;;   (require "lib/time" :as time)
;;   (time/now)      ; Unix seconds
;;   (time/now-ms)   ; Unix milliseconds
;;   (time/sleep-ms 100)

(defn now []
  (bars_time_unix))

(defn now-ms []
  (bars_time_ms))

(defn sleep-ms [ms]
  (bars_sleep_ms ms))

;; Elapsed ms between two now-ms readings (handles wrap poorly — fine for short spans).
(defn elapsed-ms [start-ms]
  (- (bars_time_ms) start-ms))
