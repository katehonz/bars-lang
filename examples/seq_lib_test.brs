;; lib/test coverage for the 17.40–17.48 seq/map/string functions.
;; Exit code matters: finish exits 1 on any failure (selfhost-test checks it).
(require "lib/test" :as t)

(defn seq-tests [ctx]
  (do
    (t/section "seq ops")
    (t/is-eq ctx 4 (count (reverse (vector 1 2 3 4))) "reverse count")
    (t/is-eq ctx 4 (get (reverse (vector 1 2 3 4)) 0) "reverse first")
    (t/is-eq ctx 5 (count (concat (vector 1 2) (vector 3 4 5))) "concat 2")
    (t/is-eq ctx 4 (count (concat (vector 1) (vector 2) (vector 3) (vector 4))) "concat variadic")
    (t/is-eq ctx 3 (count (distinct (vector 1 2 2 3 1))) "distinct")
    (t/is-eq ctx 5 (count (interpose 0 (vector 1 2 3))) "interpose")
    (t/is-eq ctx 2 (count (partition 2 (vector 1 2 3 4 5))) "partition chunks")
    (t/is-eq ctx 0 (count (partition 0 (vector 1 2 3))) "partition 0 guard")
    (t/is-eq ctx 4 (count (flatten (vector 1 (vector 2 (vector 3)) 4))) "flatten deep")
    (t/is-eq ctx 6 (count (mapcat (fn [x] (vector x x)) (vector 1 2 3))) "mapcat")
    (t/is-eq ctx 2 (count (keep (fn [x] (if (> x 1) x 0)) (vector 1 2 3))) "keep")
    (t/is-eq ctx 3 (count (map-indexed (fn [i x] (* i x)) (vector 1 1 1))) "map-indexed count")
    (t/is-eq ctx 12 (get (map-indexed (fn [i x] (+ i x)) (vector 10 10 10)) 2) "map-indexed val")
    (t/is-eq ctx 3 (count (take-nth 3 (vector 1 2 3 4 5 6 7))) "take-nth count")
    (t/is-eq ctx 4 (get (take-nth 3 (vector 1 2 3 4 5 6 7)) 1) "take-nth val")
    (t/is-eq ctx 0 (count (take-nth 0 (vector 1 2))) "take-nth 0 guard")
    (t/is-eq ctx 4 (count (dedupe (vector 1 1 2 2 2 3 1 1))) "dedupe consecutive")
    (t/is-eq ctx 3 (count (dedupe (vector 1 2 1))) "dedupe keeps non-consecutive")))

(defn sort-tests [ctx]
  (do
    (t/section "sort")
    (t/is-eq ctx 1 (get (sort (vector 3 1 2)) 0) "sort default first")
    (t/is-eq ctx 3 (get (sort (vector 3 1 2)) 2) "sort default last")
    (t/is-eq ctx 3 (get (sort (fn [a b] (> a b)) (vector 1 3 2)) 0) "sort cmp desc")
    (t/is-eq ctx 1 (get (sort (fn [a b] (> a b)) (vector 1 3 2)) 2) "sort cmp last")
    (t/is-eq ctx 1 (get (sort-by abs (vector -3 1 -2)) 0) "sort-by abs")))

(defn map-tests [ctx]
  (do
    (t/section "map ops")
    (t/is-eq ctx 3 (map-get (frequencies (vector 1 1 1)) 1) "frequencies")
    (t/is-eq ctx 2 (map-count (group-by (fn [x] (% x 2)) (vector 1 2 3 4))) "group-by")
    (t/is-eq ctx 20 (map-get (zipmap (vector 1 2) (vector 10 20)) 2) "zipmap")
    (t/is-eq ctx 1 (map-count (select-keys (zipmap (vector 1 2) (vector 10 20)) (vector 1))) "select-keys")
    (t/is-eq ctx 99 (map-get (merge (zipmap (vector 1) (vector 1)) (zipmap (vector 1) (vector 99))) 1) "merge wins")
    (t/is-eq ctx 1 (map-count (dissoc (zipmap (vector 1 2) (vector 10 20)) 2)) "dissoc")
    (t/is-eq ctx 60 (get-in (assoc-in (map) (vector 1 6) 60) (vector 1 6)) "assoc-in + get-in")
    (t/is-eq ctx 15 (get-in (update-in (assoc-in (map) (vector 1 2) 10) (vector 1 2) (fn [x] (+ x 5))) (vector 1 2)) "update-in")
    (t/is-eq ctx 60 (reduce-kv (fn [acc k v] (+ acc v)) 0 (zipmap (vector 1 2 3) (vector 10 20 30))) "reduce-kv")
    (t/is-eq ctx 2 (count (keys (zipmap (vector 1 2) (vector 10 20)))) "keys")
    (t/is-eq ctx 2 (count (vals (zipmap (vector 1 2) (vector 10 20)))) "vals")))

(defn str-tests [ctx]
  (do
    (t/section "string ops")
    (t/is ctx (str-eq? (str-upper "aBc1") "ABC1") "str-upper")
    (t/is ctx (str-eq? (str-lower "aBc1") "abc1") "str-lower")
    (t/is ctx (= (str-includes? "hello world" "world") 1) "str-includes? hit")
    (t/is ctx (= (str-includes? "hello" "xyz") 0) "str-includes? miss")
    (t/is-eq ctx 3 (count (str-split "a,b,c" ",")) "str-split")
    (t/is ctx (str-eq? (str-join (str-split "a,b,c" ",") "-") "a-b-c") "str-join")))

;; 17.53 review-fix coverage: arity gates, non-mutating update,
;; assoc-in over non-map intermediate, vector-set, sqrt/pow
(defn fix-tests [ctx]
  (do
    (t/section "review fixes")
    (t/is-eq ctx 0 (map-count (merge)) "merge 0-arity → {}")
    (t/is-eq ctx 7 (map-get (merge (zipmap (vector 1) (vector 7))) 1) "merge 1-arity → identity")
    (t/is-eq ctx 2 (map-count (dissoc (zipmap (vector 1 2) (vector 10 20)))) "dissoc 1-key-arity → same")
    (t/is-eq ctx 10
      (let [m (zipmap (vector 1) (vector 10))]
        (do (update m 1 (fn [x] (+ x 5)))
            (map-get m 1)))
      "update preserves input")
    (t/is-eq ctx 15 (map-get (update (zipmap (vector 1) (vector 10)) 1 (fn [x] (+ x 5))) 1) "update result")
    (t/is-eq ctx 9 (get-in (assoc-in (zipmap (vector 1) (vector 5)) (vector 1 2) 9) (vector 1 2)) "assoc-in over non-map")
    (t/is-eq ctx 42 (get-in (assoc-in (map) (vector 1 2 3) 42) (vector 1 2 3)) "assoc-in 3-level")
    (t/is-eq ctx 9 (let [v (vector 1 2 3)] (do (vector-set v 0 9) (get v 0))) "vector-set mutating")
    (t/is-eq ctx 5 (sqrt 26) "sqrt trunc")
    (t/is-eq ctx 1024 (pow 2 10) "pow")
    (t/is-eq ctx 2 (map-count (zipmap (vector 1 2 3) (vector 10 20))) "zipmap shorter side")))

(defn main []
  (let [ctx (t/suite "seq_lib")]
    (do (seq-tests ctx)
        (sort-tests ctx)
        (map-tests ctx)
        (str-tests ctx)
        (fix-tests ctx)
        (t/finish ctx))))
