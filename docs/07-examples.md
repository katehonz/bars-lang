# Examples

## Hello World

```clojure
;; examples/hello.brs
(defn main []
  (println "Hello, World!"))
```

```bash
bars run examples/hello.brs
```

## Math and Recursion

```clojure
;; examples/math.brs
(defn add [a b]
  (+ a b))

(defn factorial [n]
  (if (<= n 1)
    1
    (* n (factorial (- n 1)))))

(defn main []
  (println (add 3 4))
  (println (factorial 5)))
```

```bash
bars run examples/math.brs
# 7
# 120
```

## Loop / Recur

```clojure
;; examples/loop_demo.brs
(defn main []
  (let [result (loop [i 0 acc 0]
                 (if (= i 10)
                   acc
                   (recur (+ i 1) (+ acc i))))]
    (println result)
    0))
```

```bash
bars run examples/loop_demo.brs
# 45
```

## Using the Standard Library

```clojure
;; examples/stdlib_demo.brs
(load "lib/core.brs")
(load "lib/math.brs")
(load "lib/vector.brs")

(defn main []
  (println (square 5))
  (println (factorial 5))
  (let [v (range 1 5)]
    (println (sum v))
    (println (reverse v))
    (println (contains? v 3)))
  0)
```

```bash
bars run examples/stdlib_demo.brs
# 25
# 120
# 10
# <vector pointer>
# 1
```

## Vectors

```clojure
;; examples/vector.brs
(defn main []
  (let [v (vector)]
    (push v 10)
    (push v 20)
    (push v 30)
    (println (count v))
    (println (get v 1))
    0))
```

```bash
bars run examples/vector.brs
# 3
# 20
```

## Maps

```clojure
;; examples/map.brs
(defn main []
  (let [m (map)]
    (map-set m 1 100)
    (map-set m 2 200)
    (println (map-count m))
    (println (map-get m 1))
    (println (map-get m 2))
    0))
```

```bash
bars run examples/map.brs
# 2
# 100
# 200
```

## Cond Macro

```clojure
;; examples/cond_demo.brs
(load "lib/core.brs")

(defn main []
  (let [x 2]
    (println (cond
               (= x 1) 10
               (= x 2) 20
               :else   30))
    (println (cond
               (= x 3) 100
               :else   200))
    0))
```

```bash
bars run examples/cond_demo.brs
# 20
# 200
```

## REPL Session

```bash
$ bars repl
Bars REPL v0.1.0 (Cranelift JIT)
Press Ctrl+D to exit.

bars> (+ 1 2 3)
6
bars> (defn square [x] (* x x))
bars> (square 7)
49
bars> (loop [i 0 acc 0] (if (= i 5) acc (recur (+ i 1) (+ acc i))))
10
bars>
Goodbye!
```

## Ownership Check

```clojure
;; examples/ownership.brs
(defn use-once [^i64 data]
  (println data))

(defn main []
  (let [x 42]
    (use-once x)
    (use-once x)    ;; immutable borrow — OK
    0))
```

```bash
bars check examples/ownership.brs
# ✅ Ownership checks passed.
```
