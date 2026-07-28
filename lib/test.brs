;; Bars stdlib — Test framework (Phase 17.1 + 17.2 deftest)
;;
;;   (require "lib/test" :as t)
;;
;;   (t/deftest test-math
;;     (do
;;       (t/is ctx (= (+ 1 2) 3) "add")
;;       (t/is-eq ctx 42 (* 6 7) "mul")))
;;
;;   (defn main []
;;     (let [ctx (t/suite "math")]
;;       (test-math ctx)
;;       (t/finish ctx)))
;;
;; Keys in the suite map (i64): 0=passed, 1=failed
;;
;; deftest expands to (defn name [ctx] body) via user defmacro (self-host 17.2).

;; (deftest name body) → (defn name [ctx] body)
;; Body may use free `ctx`. Wrap multi-statements in (do ...).
(defmacro deftest [name body]
  `(defn ~name [ctx]
     ~body))

(defn make []
  (let [m (map)]
    (do
      (map-set m 0 0)
      (map-set m 1 0)
      m)))

;; Start a named suite: prints a header, returns a fresh context.
(defn suite [name]
  (do
    (println (str-concat "=== " name))
    (make)))

;; Optional subsection label (no counters).
(defn section [name]
  (do
    (println (str-concat "-- " name))
    0))

(defn passed [ctx]
  (map-get ctx 0))

(defn failed [ctx]
  (map-get ctx 1))

(defn total [ctx]
  (+ (map-get ctx 0) (map-get ctx 1)))

;; Core check: ok is a boolean expression result; msg is a string label.
;; Returns 1 on pass, 0 on fail (also updates counters).
(defn is [ctx ok msg]
  (if ok
    (do
      (map-set ctx 0 (+ (map-get ctx 0) 1))
      (println (str-concat "  ok   " msg))
      1)
    (do
      (map-set ctx 1 (+ (map-get ctx 1) 1))
      (println (str-concat "  FAIL " msg))
      0)))

;; Equality check with expected / actual printed on failure.
(defn is-eq [ctx expected actual msg]
  (if (= expected actual)
    (do
      (map-set ctx 0 (+ (map-get ctx 0) 1))
      (println (str-concat "  ok   " msg))
      1)
    (do
      (map-set ctx 1 (+ (map-get ctx 1) 1))
      (println (str-concat "  FAIL " msg))
      (println "       expected:")
      (println expected)
      (println "       actual:")
      (println actual)
      0)))

;; Inverse of is.
(defn is-not [ctx ok msg]
  (is ctx (not ok) msg))

;; True if value is non-zero (i64 truthiness).
(defn is-truthy [ctx val msg]
  (is ctx (not (= val 0)) msg))

(defn is-zero [ctx val msg]
  (is ctx (= val 0) msg))

;; Print summary; returns failed count (does not exit).
(defn report [ctx]
  (let [p (map-get ctx 0)
        f (map-get ctx 1)]
    (do
      (println "---- results ----")
      (println "passed:")
      (println p)
      (println "failed:")
      (println f)
      f)))

;; Report and exit 1 if any failure; otherwise return 0.
;; (exit is void — both if-branches return i64 for the host typechecker.)
(defn finish [ctx]
  (let [f (report ctx)]
    (if (= f 0)
      0
      (do (exit 1) 1))))

;; ---- one-shot helpers (no suite) ----

;; Soft assert: print OK/FAIL, return 1/0 (legacy-compatible shape).
(defn assert [ok]
  (if ok
    (do (println "OK:") 1)
    (do (println "FAIL:") 0)))

;; Hard assert: exit process on failure.
(defn assert! [ok msg]
  (if ok
    1
    (do
      (println (str-concat "ASSERT: " msg))
      (exit 1)
      0)))
