# Pure Clojure: Advanced Topics

## Table of Contents

1. [Advanced Functions](#1-advanced-functions)
2. [Lazy Sequences Deep Dive](#2-lazy-sequences-deep-dive)
3. [Transducers](#3-transducers)
4. [Specs and Validation](#4-specs-and-validation)
5. [The Collection Protocol](#5-the-collection-protocol)
6. [Reducibles](#6-reducibles)
7. [Parallelism](#7-parallelism)
8. [Performance Optimization](#8-performance-optimization)
9. [Index](#9-index)

---

## 1. Advanced Functions

### 1.1 Variadic Functions

Functions can accept variable numbers of arguments:

```clojure
(defn print-all [& args]
  (doseq [arg args]
    (println arg)))

(print-all "a" "b" "c")

;; With required arguments
(defn greet [name & greeting-parts]
  (str (clojure.string/join " " greeting-parts) ", " name "!"))

(greet "World" "Hello" "Good morning")  ;; => "Hello Good morning, World!"
```

### 1.2 Rest Parameters in Detail

The `&` symbol captures remaining arguments as a sequence:

```clojure
(defn my-apply [f & args]
  (apply f args))

;; Using with destructuring
(defn first-two [[a b & rest]]
  {:first a :second b :rest rest})

(first-two [1 2 3 4 5])
;; => {:first 1 :second 2 :rest (3 4 5)}
```

### 1.3 Keyword Arguments

Clojure supports keyword arguments via destructuring:

```clojure
(defn configure [name & {:keys [debug verbose output]
                         :or {debug false verbose false output "stdout"}}]
  {:name name :debug debug :verbose verbose :output output})

(configure "test" :debug true :verbose true :output "file.txt")
;; => {:name "test" :debug true :verbose true :output "file.txt"}
```

### 1.4 Mutual Recursion

Functions can call each other:

```clojure
(defn even? [n]
  (if (zero? n)
    true
    (odd? (dec n))))

(defn odd? [n]
  (if (zero? n)
    false
    (even? (dec n))))

(even? 4)  ;; => true
(odd? 3)   ;; => true
```

### 1.5 Memoization

Cache function results:

```clojure
(defn slow-fib [n]
  (if (<= n 1)
    n
    (+ (slow-fib (- n 1))
       (slow-fib (- n 2)))))

(def memo-fib (memoize slow-fib))

;; Time difference is dramatic for larger n
(time (memo-fib 35))  ;; Much faster
```

### 1.6 Preconditions and Postconditions

Validate inputs and outputs:

```clojure
(defn absolute-value [n]
  {:pre [(number? n)]
   :post [(number? %)
          (>= % 0)]}
  (if (neg? n)
    (- n)
    n))

(defn divide [a b]
  {:pre [(not (zero? b)) "Divisor cannot be zero"]}
  (/ a b))
```

### 1.7 Function Metadata

Functions can have metadata:

```clojure
(defn ^:private internal-helper [x]
  x)

(defn ^:deprecated old-function [x]
  x)

;; Check metadata
(meta #'internal-helper)
;; => {:private true, ...}
```

### 1.8 Arities and Overloading

```clojure
(defn arity-error []
  (throw (ex-info "Invalid arity" {})))

(defn complete
  ([x] (complete x 1))
  ([x y] (+ x y))
  ([x y z] (+ x y z)))
```

---

## 2. Lazy Sequences Deep Dive

### 2.1 Realizing Sequences

Lazy sequences are realized (evaluated) as needed:

```clojure
(def lazy-nats (range))  ;; Infinite

(take 10 lazy-nats)  ;; Realizes first 10

;; Force full realization
(doall lazy-nats)   ;; Danger: infinite!
(doall (take 1000 lazy-nats))
```

### 2.2 Chunked Sequences

Clojure's lazy sequences are chunked (typically 32 elements):

```clojure
;; Range creates chunked sequences
(class (range 100))  ;; => clojure.lang.LongRange

;; Each chunk is realized at once
```

### 2.3 Lazy Cons and Realization

```clojure
;; cons creates a lazy sequence
(def custom-seq (cons 1 (lazy-seq (cons 2 ()))))

;; lazy-seq defers computation
(defn fibs []
  (cons 0
        (cons 1
              (map + (fibs) (rest (fibs))))))
```

### 2.4 Seqable Objects

Any object can be made sequential by implementing the `seq` method:

```clojure
(extend-type String
  clojure.core.protocols/Coll
  (coll [s] (seq s)))

;; Now strings work with sequence functions
(map clojure.string/upper-case "hello")
;; => (\H \E \L \L \O)
```

### 2.5 Infinite Sequences

```clojure
;; Repeated cycle
(def repeating (cycle [:a :b :c]))

;; Repeat forever
(def ones (repeatedly 1))
(def randoms (repeatedly #(rand-int 100)))

;; Iterate - apply function to previous result
(def powers-of-two (iterate #(* 2 %) 1))
(def collatz (iterate #(if (even? %) (/ % 2) (inc (* 3 %))) 1))
```

### 2.6 Sequence Performance

```clojure
;; Don't hold onto head of lazy sequence
(defn bad-sum []
  (let [large-seq (range 10000000)]
    (reduce + (take 10 large-seq))))  ;; Holds reference to entire seq

(defn good-sum []
  (reduce + (take 10 (range 10000000))))  ;; Head can be GC'd
```

### 2.7 Eager vs Lazy

```clojure
;; mapcat can be eager
(mapcat reverse [[1 2] [3 4]])  ;; => (2 1 4 3)

;; into forces realization
(into [] (map inc (range 1000)))

;;顽固 (into) is efficient - doesn't create intermediate collections
```

---

## 3. Transducers

Transducers are composable, lazy transformations independent of input context.

### 3.1 Creating Transducers

```clojure
;; Without context
(def increment (map inc))
(def only-evens (filter even?))

;; Composing transducers
(def transform (comp
                 (filter even?)
                 (map inc)
                 (take 10)))
```

### 3.2 Using Transducers

```clojure
;; With any sequence-like collection
(transduce transform + (range 100))
;; => Sum of first 10 even numbers + 1

(into [] transform (range 100))
;; => [3 5 7 9 11 13 15 17 19 21]

(sequence transform (range 100))
;; => Returns lazy sequence
```

### 3.3 Completing Reductions

Some transducers need to do something at the end:

```clojure
(def taking-transform
  (fn [rf]
    (let [n (volatile! 5)]
      (fn
        ([] (rf))
        ([result] (rf result))
        ([result input]
         (if (pos? @n)
           (do (vswap! n dec)
               (rf result input))
           (reduced result)))))))

(transduce taking-transform + (range 100))  ;; => 10
```

### 3.4 Early Termination

```clojure
;; reduced wraps a value to stop early
(transduce (filter odd?) + (range 10))
;; => 25 (1+3+5+7+9)

;; Use reduced? to check
(reduced? (reduced 5))  ;; => true
```

### 3.5 Cat and Completing

```clojure
(require '[clojure.core.protocols :as p])

;; The completing arity of the reducing function
(transduce
  (map inc)
  (fn
    ([result] result)  ;; completing arity
    ([result input] (rf result input)))
  []
  (range 5))
```

---

## 4. Specs and Validation

### 4.1 Introduction to Spec

Spec provides runtime validation and generative testing (via `clojure.spec.gen`).

### 4.2 Defining Specs

```clojure
(require '[clojure.spec.alpha :as s])

(s/def ::name string?)
(s/def ::age (s/and int? #(>= % 0)))
(s/def ::person (s/keys :req [::name ::age]))
```

### 4.3 Conforming

```clojure
(s/conform ::age 25)    ;; => 25
(s/conform ::age -5)    ;; => :clojure.spec.alpha/invalid

(s/conform ::person {::name "John" ::age 30})
;; => {::name "John" ::age 30}
```

### 4.4 Validation with `valid?`

```clojure
(s/valid? ::age 25)     ;; => true
(s/valid? ::age -5)     ;; => false
(s/valid? ::person {::name "John" ::age 30})  ;; => true
```

### 4.5 Generative Testing

```clojure
(require '[clojure.spec.gen.alpha :as gen])

;; Generate values
(gen/generate (s/gen ::age))
(gen/sample (s/gen ::age))

;; Test with spec
(s/def ::email (s/and string?
                       #(re-find #"@" %)))

(s/fdef greet
  :args (s/cat :name ::name)
  :ret string?)

;; Run generative tests
(stest/instrument `greet)
```

### 4.6 Multi-spec

```clojure
(s/def ::shape (s/multi-spec :type keyword?))

(defmethod shape-spec :circle [_]
  (s/keys :req [:radius]))

(defmethod shape-spec :rect [_]
  (s/keys :req [:width :height]))
```

---

## 5. The Collection Protocol

### 5.1 Collection Hierarchy

```
IPersistentCollection
  IPersistentList
  IPersistentVector
  IPersistentMap
  IPersistentSet
```

### 5.2 Key Protocols

```clojure
;; Sequential
(first coll)
(rest coll)
(next coll)
(cons item coll)

;; Counted
(count coll)

;; Indexed (Vectors)
(nth coll index)
(get coll index)

;; Associative (Maps)
(assoc coll key val)
(dissoc coll key)
(find coll key)
(keys coll)
(vals coll)
```

### 5.3 Extending Collections

```clojure
;; Using reify
(def my-collection
  (reify
    clojure.core.protocols/Coll
    (coll [this] this)
    clojure.core.protocols/Indexed
    (nth [this i] (get [10 20 30] i))))

(nth my-collection 1)  ;; => 20
```

### 5.4 Custom Reducibles

```clojure
(defrecord Range [start end]
  clojure.core.protocols/Coll
  (coll [this] (seq (range start end)))

(reduce + (Range. 1 10))  ;; => 45
```

---

## 6. Reducibles

Reducers provide a way to perform parallel reductions without lazy sequences.

### 6.1 Using Reducers

```clojure
(require '[clojure.core.reducers :as r])

;; Parallel map (parallelizes automatically in fold)
(r/map inc (range 1000))

;; fold uses parallel reduction
(r/fold + (r/map inc (range 1000000)))
```

### 6.2 Custom Reducers

```clojure
;; fold requires a foldable coll and combining function
(r/fold
  (fn ([] 0) ([x y] (+ x y)))
  (fn ([x] x) ([x y] (+ x y)))
  (range 1000))
```

---

## 7. Parallelism

### 7.1 pmap

Parallel map (lazy):

```clojure
;; Like map but evaluates in parallel
(time
  (doall (pmap #(do (Thread/sleep 100) %) (range 10))))
;; Much faster than regular map with blocking operations
```

### 7.2 Reducers for Parallelism

```clojure
;; Folding with multiple cores
(r/fold 100 + (range 10000000))

;; Custom combiner
(r/fold
  100
  (fn ([] 0) ([a b] (+ a b)))
  (fn ([] 0) ([a b] (+ a b)))
  (range 10000000))
```

### 7.3 Futures

```clojure
;; Independent parallel tasks
(let [a (future (compute-a))
      b (future (compute-b))]
  [@a @b])  ;; Waits for both
```

### 7.4 CompletableFuture (via Java interop - noted only)

Note: Java's `CompletableFuture` requires Java interop. Pure Clojure alternatives include:
- Core.async channels
- Manifold library
- Promises with futures

---

## 8. Performance Optimization

### 8.1 Persistent Data Structures

Clojure's persistent data structures share structure:

```clojure
;; Adding to vector shares most structure
(def v1 [1 2 3 4 5])
(def v2 (conj v1 6))

;; v1 and v2 share [1 2 3 4 5]
;; Only new nodes created for path to new element
```

### 8.2 Transient Data Structures

For local, temporary mutations:

```clojure
(defn slow-accumulation []
  (loop [coll []
         i 0]
    (if (= i 100000)
      coll
      (recur (conj coll i) (inc i)))))

(defn fast-accumulation []
  (persistent!
    (loop [coll (transient [])
           i 0]
      (if (= i 100000)
        coll
        (recur (conj! coll i) (inc i))))))

(time (count (slow-accumulation)))   ;; Slower
(time (count (fast-accumulation)))   ;; Faster
```

### 8.3 Chunked Operations

```clojure
;; Prefer chunked operations
(into [] (map inc (range 1000)))        ;; Creates one intermediate seq
(into [] (mapcat list (range 100)))     ;; Flattens lazily
```

### 8.4 Keep Args Eager

```clojure
;; Bad: holds head of sequence
(def bad-result (map f large-collection))

;; Good: process immediately
(into [] (map f large-collection))
```

### 8.5 Batch Processing

```clojure
;; Instead of many small operations
(doseq [x items]
  (update-db x))

;; Consider batching
(batch-update items)
```

### 8.6 Preload and Cache

```clojure
;; Memoization for expensive computations
(def cached expensive-lookup
  (memoize (fn [k]
             (compute-expensively k))))

;; Preload on startup
(def initialized-data
  (delay (load-and-process-data)))
```

### 8.7 Bencharking

```clojure
(require '[criterium.core :as c])

(c/quick-bench (reduce + (range 10000)))
;; Reports mean, std deviation, etc.
```

---

## 9. Index

### A

- `arity` - [1.8](#18-arities-and-overloading)
- `assert` - [1.6](#16-preconditions-and-postconditions)

### C

- `chunked-seq?` - [2.2](#22-chunked-sequences)
- `coll` - [5.3](#53-extending-collections)
- `complement` - [1.3](#13-keyword-arguments)
- `comp` - [1.3](#13-keyword-arguments)

### D

- `delay` - [2.6](#26-sequence-performance)
- `delayed?` - [2.6](#26-sequence-performance)
- `deref` - [2.6](#26-sequence-performance)

### F

- `force` - [2.6](#26-sequence-performance)
- `fnil` - [1.3](#13-keyword-arguments)
- `fold` - [6.2](#62-using-reducers)
- `fpartial` - [1.3](#13-keyword-arguments)

### G

- `gen` - [4.5](#45-generative-testing)
- `generate` - [4.5](#45-generative-testing)

### I

- `into` - [3.2](#32-using-transducers)
- `iterate` - [2.5](#25-infinite-sequences)

### L

- `lazy-cat` - [2.3](#23-lazy-cons-and-realization)
- `lazy-seq` - [2.3](#23-lazy-cons-and-realization)
- `let` - [1.2](#12-rest-parameters-in-detail)

### M

- `memoize` - [1.5](#15-memoization)
- `multi-spec` - [4.6](#46-multi-spec)
- `mmerge` - [6.1](#61-using-reducers)

### N

- `nested` - [5.3](#53-extending-collections)
- `next` - [5.2](#52-key-protocols)

### P

- `parallelize` - [7.2](#72-reducers-for-parallelism)
- `partial` - [1.3](#13-keyword-arguments)
- `pmap` - [7.1](#71-pmap)
- `promote` - [6.2](#62-using-reducers)

### R

- `realized?` - [2.1](#21-realizing-sequences)
- `reduced` - [3.4](#34-early-termination)
- `reduced?` - [3.4](#34-early-termination)
- `reductions` - [3.3](#33-completing-reductions)

### S

- `sample` - [4.5](#45-generative-testing)
- `sequence` - [3.2](#32-using-transducers)
- `spec` - [4.1](#41-introduction-to-spec)
- `split-with` - [2.6](#26-sequence-performance)

### T

- `test` - [4.5](#45-generative-testing)
- `transduce` - [3.2](#32-using-transducers)
- `transient` - [8.2](#82-transient-data-structures)
- `tree-seq` - [2.6](#26-sequence-performance)

### V

- `volatile!` - [1.7](#17-function-metadata)
- `volatile?` - [1.7](#17-function-metadata)

---

*Pure Clojure: Advanced Topics*
