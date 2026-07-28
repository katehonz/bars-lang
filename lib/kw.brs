;; Bars Standard Library — Keyword-argument helpers (Phase 17.3c)
;;
;; Call sites pack options with the compiler built-in:
;;   (kwargs :name "Ada" :times 3)  →  vector ["name" "Ada" "times" 3]
;;
;;   (require "lib/kw" :as kw)
;;   (defn greet [msg opts]
;;     (let [name (kw/lookup opts "name")]
;;       (println name)))
;;   (greet "hi" (kwargs :name "Ada"))
;;
;; Keys are bare keyword names (no leading ':'). Values keep their types.
;; Named lookup (not get) so vector get is not shadowed inside this module.

(defn str-eq? [a b]
  (if (!= (count a) (count b)) false
    (= (str-starts-with? a b) 1)))

;; Lookup key in flat [k v k v ...] vector. Returns value or 0 if missing.
(defn lookup [opts key]
  (let [n (count opts)]
    (loop [i 0]
      (if (>= i n) 0
        (if (if (< (+ i 1) n) (str-eq? (get opts i) key) false)
          (get opts (+ i 1))
          (recur (+ i 2)))))))

(defn has? [opts key]
  (let [n (count opts)]
    (loop [i 0]
      (if (>= i n) false
        (if (if (< (+ i 1) n) (str-eq? (get opts i) key) false)
          true
          (recur (+ i 2)))))))

;; Like lookup, but return default when key is absent.
(defn lookup-or [opts key default]
  (if (has? opts key)
    (lookup opts key)
    default))

;; Number of key/value pairs.
(defn count-pairs [opts]
  (/ (count opts) 2))
