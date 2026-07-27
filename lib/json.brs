;; Bars Standard Library — JSON (Phase 14.1)
;; Pure Bars parser/generator for a practical subset.
;;
;; Tagged values (vectors):
;;   [0]           null
;;   [1 b]         bool   (b = 0|1)
;;   [2 n]         number (i64)
;;   [3 s]         string
;;   [4 elems]     array  (vector of tagged values)
;;   [5 pairs]     object (vector of [key-string tagged-value])
;;
;;   (require "lib/json" :as json)
;;   (json/stringify (json/parse "{\"a\":1}"))

;; ---- constructors ----

(defn j-null []
  (let [v (vector)] (do (push v 0) v)))

(defn j-bool [b]
  (let [v (vector)] (do (push v 1) (push v (if b 1 0)) v)))

(defn j-num [n]
  (let [v (vector)] (do (push v 2) (push v n) v)))

(defn j-str [s]
  (let [v (vector)] (do (push v 3) (push v s) v)))

(defn j-arr [elems]
  (let [v (vector)] (do (push v 4) (push v elems) v)))

(defn j-obj [pairs]
  (let [v (vector)] (do (push v 5) (push v pairs) v)))

(defn j-tag [v] (get v 0))
(defn j-payload [v] (get v 1))

;; ---- int → decimal string ----

(defn int-str [n]
  (let [d "0123456789"]
    (if (< n 0) (str-concat "-" (int-str (- 0 n)))
      (if (< n 10) (str-slice d n (+ n 1))
        (str-concat (int-str (/ n 10)) (str-slice d (% n 10) (+ (% n 10) 1)))))))

;; ---- stringify ----

(defn escape-str [s]
  (let [n (count s)]
    (loop [i 0 acc ""]
      (if (>= i n) acc
        (let [c (str-get s i)]
          (if (= c 34)
            (recur (+ i 1) (str-concat acc "\\\""))
            (if (= c 92)
              (recur (+ i 1) (str-concat acc "\\\\"))
              (if (= c 10)
                (recur (+ i 1) (str-concat acc "\\n"))
                (if (= c 13)
                  (recur (+ i 1) (str-concat acc "\\r"))
                  (if (= c 9)
                    (recur (+ i 1) (str-concat acc "\\t"))
                    (recur (+ i 1)
                      (str-concat acc (str-slice s i (+ i 1))))))))))))))

(defn stringify [v]
  (let [t (j-tag v)]
    (if (= t 0) "null"
      (if (= t 1)
        (if (= (j-payload v) 1) "true" "false")
        (if (= t 2) (int-str (j-payload v))
          (if (= t 3)
            (str-concat "\"" (str-concat (escape-str (j-payload v)) "\""))
            (if (= t 4) (stringify-arr (j-payload v))
              (if (= t 5) (stringify-obj (j-payload v))
                "null"))))))))

(defn stringify-arr [elems]
  (let [n (count elems)]
    (if (= n 0) "[]"
      (loop [i 0 acc "["]
        (if (>= i n)
          (str-concat acc "]")
          (let [piece (stringify (get elems i))
                next (if (= i 0)
                       (str-concat acc piece)
                       (str-concat acc (str-concat "," piece)))]
            (recur (+ i 1) next)))))))

(defn stringify-obj [pairs]
  (let [n (count pairs)]
    (if (= n 0) "{}"
      (loop [i 0 acc "{"]
        (if (>= i n)
          (str-concat acc "}")
          (let [pair (get pairs i)
                k (get pair 0)
                val (get pair 1)
                piece (str-concat "\""
                        (str-concat (escape-str k)
                          (str-concat "\":" (stringify val))))
                next (if (= i 0)
                       (str-concat acc piece)
                       (str-concat acc (str-concat "," piece)))]
            (recur (+ i 1) next)))))))

;; ---- parse helpers ----

(defn skip-ws [s i]
  (let [n (count s)]
    (loop [j i]
      (if (>= j n) j
        (let [c (str-get s j)]
          (if (if (= c 32) true
                (if (= c 9) true
                  (if (= c 10) true (= c 13))))
            (recur (+ j 1))
            j))))))

(defn starts-at? [s i lit]
  (let [n (count s)
        m (count lit)]
    (if (> (+ i m) n) false
      (= (str-starts-with? (str-slice s i (+ i m)) lit) 1))))

;; Returns [tagged-value next-index] or 0 on error.
(defn parse-at [s i0]
  (let [i (skip-ws s i0)
        n (count s)]
    (if (>= i n) 0
      (let [c (str-get s i)]
        (if (= c 110)
          (if (starts-at? s i "null")
            (let [out (vector)] (do (push out (j-null)) (push out (+ i 4)) out))
            0)
          (if (= c 116)
            (if (starts-at? s i "true")
              (let [out (vector)] (do (push out (j-bool true)) (push out (+ i 4)) out))
              0)
            (if (= c 102)
              (if (starts-at? s i "false")
                (let [out (vector)] (do (push out (j-bool false)) (push out (+ i 5)) out))
                0)
              (if (= c 34) (parse-string s i)
                (if (= c 91) (parse-array s i)
                  (if (= c 123) (parse-object s i)
                    (if (if (= c 45) true
                          (if (if (>= c 48) (<= c 57) false) true false))
                      (parse-number s i)
                      0)))))))))))

(defn parse-number [s i0]
  (let [n (count s)
        neg (if (= (str-get s i0) 45) true false)
        start (if neg (+ i0 1) i0)]
    (if (>= start n) 0
      (loop [j start acc 0]
        (if (>= j n)
          (let [val (if neg (- 0 acc) acc)
                out (vector)]
            (do (push out (j-num val)) (push out j) out))
          (let [c (str-get s j)]
            (if (if (>= c 48) (<= c 57) false)
              (recur (+ j 1) (+ (* acc 10) (- c 48)))
              (if (= j start) 0
                (let [val (if neg (- 0 acc) acc)
                      out (vector)]
                  (do (push out (j-num val)) (push out j) out))))))))))

(defn parse-string [s i0]
  ;; i0 points at opening "
  (let [n (count s)]
    (loop [j (+ i0 1) acc ""]
      (if (>= j n) 0
        (let [c (str-get s j)]
          (if (= c 34)
            (let [out (vector)]
              (do (push out (j-str acc)) (push out (+ j 1)) out))
             (if (= c 92)
               (if (>= (+ j 1) n) 0
                 (let [e (str-get s (+ j 1))
                       ch (if (= e 110) "\n"
                            (if (= e 116) "\t"
                              (if (= e 114) "\r"
                                (if (= e 34) "\""
                                  (if (= e 92) "\\"
                                    (if (= e 98) (code-char 8)
                                      (if (= e 102) (code-char 12)
                                        (if (= e 47) "/"
                                          (str-slice s (+ j 1) (+ j 2)))))))))))]
                   (recur (+ j 2) (str-concat acc ch))))
              (recur (+ j 1) (str-concat acc (str-slice s j (+ j 1)))))))))))

(defn parse-array [s i0]
  ;; i0 at [
  (let [elems (vector)
        i1 (skip-ws s (+ i0 1))
        n (count s)]
    (if (if (< i1 n) (= (str-get s i1) 93) false)
      (let [out (vector)]
        (do (push out (j-arr elems)) (push out (+ i1 1)) out))
      (loop [i i1]
        (let [r (parse-at s i)]
          (if (= r 0) 0
            (let [val (get r 0)
                  j (get r 1)]
              (do (push elems val)
                  (let [k (skip-ws s j)]
                    (if (>= k n) 0
                      (let [c (str-get s k)]
                        (if (= c 44)
                          (recur (skip-ws s (+ k 1)))
                          (if (= c 93)
                            (let [out (vector)]
                              (do (push out (j-arr elems)) (push out (+ k 1)) out))
                            0)))))))))))))

(defn parse-object [s i0]
  ;; i0 at {
  (let [pairs (vector)
        i1 (skip-ws s (+ i0 1))
        n (count s)]
    (if (if (< i1 n) (= (str-get s i1) 125) false)
      (let [out (vector)]
        (do (push out (j-obj pairs)) (push out (+ i1 1)) out))
      (loop [i i1]
        (let [ks (parse-at s i)]
          (if (= ks 0) 0
            (let [knode (get ks 0)
                  j (get ks 1)]
              (if (!= (j-tag knode) 3) 0
                (let [k (j-payload knode)
                      j2 (skip-ws s j)]
                  (if (if (< j2 n) (= (str-get s j2) 58) false)
                    (let [vs (parse-at s (+ j2 1))]
                      (if (= vs 0) 0
                        (let [vnode (get vs 0)
                              j3 (get vs 1)
                              pair (vector)]
                          (do (push pair k)
                              (push pair vnode)
                              (push pairs pair)
                              (let [j4 (skip-ws s j3)]
                                (if (>= j4 n) 0
                                  (let [c (str-get s j4)]
                                    (if (= c 44)
                                      (recur (skip-ws s (+ j4 1)))
                                      (if (= c 125)
                                        (let [out (vector)]
                                          (do (push out (j-obj pairs))
                                              (push out (+ j4 1))
                                              out))
                                        0)))))))))
                    0))))))))))

;; Parse full JSON document → tagged value, or 0 on error.
(defn parse [s]
  (let [r (parse-at s 0)]
    (if (= r 0) 0
      (let [v (get r 0)
            j (skip-ws s (get r 1))]
        (if (>= j (count s)) v
          0)))))
