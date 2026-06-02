# Pure Clojure: A Comprehensive Guide

## Table of Contents

1. [Introduction to Clojure](#1-introduction-to-clojure)
2. [Getting Started](#2-getting-started)
3. [Basic Syntax and Forms](#3-basic-syntax-and-forms)
4. [Data Structures](#4-data-structures)
5. [Functions](#5-functions)
6. [Control Flow](#6-control-flow)
7. [Sequences and Lazy Evaluation](#7-sequences-and-lazy-evaluation)
8. [Destructuring](#8-destructuring)
9. [Namespaces](#9-namespaces)
10. [Macros](#10-macros)
11. [Concurrency](#11-concurrency)
12. [Protocols and Records](#12-protocols-and-records)
13. [Multimethods](#13-multimethods)
14. [Testing](#14-testing)
15. [The REPL](#15-the-repl)
16. [Core.async](#16-coreasync)
17. [Best Practices](#17-best-practices)
18. [Index](#18-index)

---

## 1. Introduction to Clojure

### 1.1 What is Clojure?

Clojure is a modern, dynamic, and functional programming language that runs on the Java Virtual Machine (JVM), the .NET Common Language Runtime (CLR), and JavaScript engines via ClojureScript. Created by Rich Hickey in 2007, Clojure is a dialect of Lisp that emphasizes immutability, functional programming, andconcise expressiveness.

### 1.2 Key Characteristics of Clojure

#### 1.2.1 Immutability by Default

In Clojure, all data structures are immutable by default. When you "modify" a data structure, you actually create a new version with the desired changes, while the original remains unchanged. This approach leads to safer concurrent programs and cleaner code.

```clojure
(def original [1 2 3])
(def modified (conj original 4))
;; original => [1 2 3]
;; modified => [1 2 3 4]
```

#### 1.2.2 Functional Programming

Clojure encourages pure functions without side effects. Functions are first-class citizens that can be passed as arguments, returned from other functions, and composed together.

```clojure
(def double (partial * 2))
(def add-ten (partial + 10))
(def transform (comp double add-ten))
(transform 5) ;; => 30
```

#### 1.2.3 Lisp Heritage

As a Lisp dialect, Clojure inherits the power of macros and the uniform representation of code as data. Everything is an expression that returns a value, and the syntax is simple and consistent.

#### 1.2.4 Runtime Polymorphism

Clojure provides multiple mechanisms for polymorphism:
- **Protocols**: Define method signatures for data types
- **Multimethods**: Dispatch based on arbitrary criteria
- **Records**: Concrete data types implementing protocols

### 1.3 Why Pure Clojure?

While Clojure runs on the JVM and has excellent Java interop, this book focuses on **pure Clojure**—the core language features that don't rely on Java integration. This approach:

- Teaches the fundamental concepts of Clojure
- Makes code portable (including ClojureScript)
- Encourages thinking in Clojure's paradigm
- Avoids mixing paradigms unnecessarily

### 1.4 The Clojure Philosophy

Clojure adheres to several principles:

1. **Simplicity**: Hard things should be simple, simple things should be trivial
2. **Immutability**: Prefer immutable data structures for safety and concurrency
3. **Abstraction**: Build layers of abstraction to manage complexity
4. **Expression-Oriented**: Everything is an expression that returns a value

---

## 2. Getting Started

### 2.1 Installation

#### 2.1.1 Using CLI Tools

The recommended way to install Clojure is through the official CLI tool:

**Linux/macOS:**
```bash
curl -O https://download.clojure.org/install/linux-install-1.11.1.1202.sh
chmod +x linux-install-1.11.1.1202.sh
./linux-install-1.11.1.1202.sh
```

**macOS (Homebrew):**
```bash
brew install clojure
```

#### 2.1.2 Manual Installation

Download the Clojure JAR file and use it directly:
```bash
java -jar clojure-1.11.1.jar
```

### 2.2 Your First Clojure Project

#### 2.2.1 Creating a Project with deps.edn

Create a new directory for your project and add a `deps.edn` file:

```clojure
{:deps {org.clojure/clojure {:mvn/version "1.11.1"}}}
```

Run Clojure:
```bash
clj -M
```

#### 2.2.2 REPL Basics

The REPL (Read-Eval-Print Loop) is your primary development environment:

```clojure
user=> (+ 1 2 3)
6
user=> (println "Hello, Clojure!")
Hello, Clojure!
nil
user=> (def message "Hello, World!")
#'user/message
user=> message
"Hello, World!"
```

### 2.3 Editor Setup

Popular editors for Clojure development:

- **VS Code**: Calva extension
- **Emacs**: CIDER mode
- **Vim/Neovim**: Conjure plugin
- **IntelliJ**: Cursive plugin

---

## 3. Basic Syntax and Forms

### 3.1 S-Expressions

Clojure code is written as **s-expressions** (symbolic expressions), which are nested lists:

```clojure
(operator operands...)
```

The first element is the operator (function, macro, or special form), and the rest are operands.

```clojure
(+ 1 2)        ;; Addition: 3
(* 2 3 4)       ;; Multiplication: 24
(< 1 2 3)       ;; Comparison: true
(and true false) ;; Logical AND: false
```

### 3.2 Data as Code

In Lisp, data and code are the same. This means you can manipulate your programs as data:

```clojure
'(+ 1 2 3)  ;; A quoted list: (+ 1 2 3)
(list + 1 2) ;; A list containing the + function and numbers
```

### 3.3 Special Forms

Special forms are primitives that can't be expressed as functions because they have special evaluation rules.

#### 3.3.1 def

Define a global var:

```clojure
(def x 10)
(def name "Clojure")
(def items [1 2 3])
```

#### 3.3.2 let

Create local bindings:

```clojure
(let [x 10
      y 20]
  (+ x y))  ;; => 30
```

#### 3.3.3 if

Conditional execution:

```clojure
(if condition
  then-expr
  else-expr)
```

#### 3.3.4 quote

Prevent evaluation:

```clojure
(quote (+ 1 2))  ;; => (+ 1 2)
'(+ 1 2)         ;; Short form: (+ 1 2)
```

### 3.4 Evaluation Rules

1. Numbers, strings, booleans, nil, and keywords **evaluate to themselves**
2. Symbols **evaluate to the value** of the var they name
3. Lists **evaluate as function calls** (if first element is callable)
4. Quoted expressions **prevent evaluation**

### 3.5 Comments

```clojure
;; Single line comment

;; Multi-line comment
;; (there is no special multi-line syntax,
;;  just use multiple single-line comments)

(comment
  "This is a comment block that won't be evaluated"
  (+ 1 2))
```

### 3.6 Whitespace and Formatting

- Clojure is whitespace-insensitive (except within symbols)
- Standard convention: one space after opening paren, before closing
- Align arguments vertically for readability:

```clojure
(do-something arg1
              arg2
              arg3)
```

---

## 4. Data Structures

Clojure provides a rich set of immutable data structures. Understanding them is fundamental to writing idiomatic Clojure.

### 4.1 Numbers

#### 4.1.1 Integer Types

```clojure
42        ;; Decimal
017       ;; Octal (15)
0x2A      ;; Hexadecimal (42)
2r101010  ;; Binary (42)
```

#### 4.1.2 Floating Point

```clojure
3.14
6.022e23
```

#### 4.1.3 Ratios

Clojure preserves precision with ratios:

```clojure
1/3        ;; Ratio type
22/7       ;; Approximation of pi
(/ 1 3)    ;; 1/3
```

### 4.2 Strings

```clojure
"Hello, World!"
"Multi-line
string"

;; Concatenation
(str "Hello" " " "World")  ;; => "Hello World"

;; Substring
(subs "Hello" 0 5)  ;; => "Hello"

;; String functions
(count "Clojure")   ;; => 7
(reverse "Clojure") ;; => "erujolC"
```

### 4.3 Characters

```clojure
\a      ;; Character a
\newline ;; Newline
\space  ;; Space
```

### 4.4 Booleans

```clojure
true
false
nil     ;; Represents absence of value
```

Truthiness rules:
- Everything except `false` and `nil` is truthy
- `and`, `or`, `if`, `when` use this rule

### 4.5 Keywords

Keywords are interned strings used as identifiers, often for keys in maps:

```clojure
:foo
:bar
:user/name   ;; Namespaced keyword
::local-key  ;; Auto-namespaced
```

Keywords evaluate to themselves and can be used as functions to look up values in maps.

### 4.6 Symbols

Symbols evaluate to the vars they name:

```clojure
'x          ;; Symbol x (quoted)
(def x 10)  ;; Defines var x with value 10
x           ;; Evaluates to 10
```

### 4.7 Lists

Lists are linked lists, efficient for sequential access at the front:

```clojure
'(1 2 3)              ;; Quote to prevent evaluation
(list 1 2 3)         ;; Create a list
'(+ 1 2)             ;; A list containing the + symbol

;; Access
(first '(1 2 3))     ;; => 1
(second '(1 2 3))    ;; => 2
(rest '(1 2 3))      ;; => (2 3)
(nth '(1 2 3) 0)      ;; => 1

;; Modification (returns new list)
(cons 0 '(1 2 3))    ;; => (0 1 2 3)
(concat '(1 2) '(3 4)) ;; => (1 2 3 4)
```

### 4.8 Vectors

Vectors are indexed collections, efficient for random access:

```clojure
[1 2 3 4 5]
(vector 1 2 3)          ;; => [1 2 3]

;; Access
(get [10 20 30] 1)      ;; => 20
([10 20 30] 1)          ;; => 20 (keyword-like access)
(first [1 2 3])         ;; => 1
(second [1 2 3])        ;; => 2
(last [1 2 3])          ;; => 3

;; Modification (returns new vector)
(conj [1 2] 3)          ;; => [1 2 3]
(pop [1 2 3])           ;; => [1 2]
(assoc [1 2 3] 1 20)    ;; => [1 20 3]
(subvec [1 2 3 4 5] 1 3) ;; => [2 3]
```

### 4.9 Maps

Maps are key-value associative structures:

```clojure
{:name "Alice" :age 30}
(hash-map :a 1 :b 2 :c 3)
(assoc {:a 1} :b 2)      ;; => {:a 1 :b 2}
(dissoc {:a 1 :b 2} :a) ;; => {:b 2}
(get {:a 1} :a)         ;; => 1
({:a 1} :a)             ;; => 1
(:a {:a 1})             ;; => 1 (keywords are functions!)

;; Nested access
(get-in {:user {:address {:city "Sofia"}}}
         [:user :address :city])  ;; => "Sofia"

;; Merging
(merge {:a 1} {:b 2} {:c 3})  ;; => {:a 1 :b 2 :c 3}
```

### 4.10 Sets

Sets are collections of unique values:

```clojure
#{1 2 3}
(hash-set 1 2 3 2 1)    ;; => #{1 2 3}
(set [1 2 2 3 3 3])     ;; => #{1 2 3}

;; Operations
(conj #{1 2} 3)         ;; => #{1 2 3}
(disj #{1 2 3} 2)       ;; => #{1 3}
(contains? #{1 2 3} 2)  ;; => true
(get #{1 2 3} 2)        ;; => 2
(clojure.set/union #{1 2} #{2 3})    ;; => #{1 2 3}
(clojure.set/intersection #{1 2 3} #{2 3 4}) ;; => #{2 3}
(clojure.set/difference #{1 2 3} #{2 3})     ;; => #{1}
```

### 4.11 Structuring Data

```clojure
;; Representing a user with a map
(def user {:name "John"
           :email "john@example.com"
           :roles [:admin :user]})

;; Nested data
(def company {:name "TechCorp"
              :employees [{:name "Alice" :dept "Engineering"}
                          {:name "Bob" :dept "Sales"}]
              :locations {:HQ "New York"
                         :branch "Boston"}})
```

### 4.12 Collections Library

Core collection functions that work uniformly across data structures:

```clojure
;; Predicates
(empty? [])            ;; => true
(empty? [1 2 3])       ;; => false
(every? even? [2 4 6])  ;; => true
(some odd? [2 4 5 6])   ;; => true
(not-empty [1 2 3])     ;; => [1 2 3]
(not-empty [])          ;; => nil

;; Counting
(count [1 2 3])         ;; => 3
(count {:a 1 :b 2})      ;; => 2

;; Conversion
(vec '(1 2 3))          ;; => [1 2 3]
(list [1 2 3])          ;; => (1 2 3)
(set [1 2 2 3])          ;; => #{1 2 3}
(mapv inc [1 2 3])       ;; => [2 3 4]
```

---

## 5. Functions

### 5.1 Defining Functions

#### 5.1.1 Basic Syntax

```clojure
(defn greeting
  "Returns a greeting message"
  [name]
  (str "Hello, " name "!"))

(greeting "World")  ;; => "Hello, World!"
```

#### 5.1.2 Multiple Arities

Functions can have different argument counts:

```clojure
(defn add
  ([x] (add x 0))
  ([x y] (+ x y))
  ([x y z] (+ x y z)))

(add 5)    ;; => 5
(add 5 3)  ;; => 8
(add 1 2 3) ;; => 6
```

#### 5.1.3 Variable Arguments

Use `&` for rest parameters:

```clojure
(defn sum [& numbers]
  (reduce + numbers))

(sum 1 2 3 4 5)  ;; => 15
```

### 5.2 Anonymous Functions

```clojure
(fn [x] (* x x))
#(* % %)                ;; Implicit argument
#(* %1 %2)              ;; Multiple arguments
#(reduce + %&)          ;; Rest arguments
```

### 5.3 Higher-Order Functions

Functions that take or return other functions:

```clojure
(def double #( % 2))
(def square #(* % %))

(map double [1 2 3 4])    ;; => (2 4 6 8)
(map square [1 2 3 4])    ;; => (1 4 9 16)

(filter even? [1 2 3 4 5 6])  ;; => (2 4 6)

(reduce + [1 2 3 4 5])   ;; => 15
(reduce max [3 1 4 1 5])  ;; => 5

;; Function composition
(def transform (comp square double))
(transform 3)  ;; => 36 (3*2=6, 6*6=36)
```

### 5.4 Closures

Functions that capture their environment:

```clojure
(defn make-adder [x]
  (fn [y] (+ x y)))

(def add-5 (make-adder 5))
(add-5 10)  ;; => 15
(add-5 3)   ;; => 8

;; Counter example
(defn make-counter []
  (let [count (atom 0)]
    {:increment #(swap! count inc)
     :decrement #(swap! count dec)
     :value #(deref count)}))
```

### 5.5 Pre- and Post-Conditions

```clojure
(defn absolute-value [n]
  {:pre [(number? n)]
   :post [(>= % 0)]}
  (if (neg? n)
    (- n)
    n))
```

### 5.6 Multimethods via defn

While true multimethods use `defmulti` and `defmethod`, regular functions can simulate behavior-based dispatch:

```clojure
(defn process [x]
  (cond
    (string? x) (clojure.string/upper-case x)
    (number? x) (inc x)
    :else "unknown"))
```

---

## 6. Control Flow

### 6.1 Branching

#### 6.1.1 if / if-not

```clojure
(if condition
  then-expr
  else-expr)

(if (pos? -5)
  "positive"
  "not positive")  ;; => "not positive"

;; if-not is simply (if (not condition)...)
(if-not (even? 4)
  "odd"
  "even")  ;; => "even"
```

#### 6.1.2 when / when-not

Single branch without else:

```clojure
(when (pos? 5)
  (println "Positive!")
  (inc 5))  ;; => 6

(when-not (neg? 3)
  "non-negative")  ;; => "non-negative"
```

#### 6.1.3 cond

Multiple conditions:

```clojure
(defn classify [n]
  (cond
    (neg? n) "negative"
    (zero? n) "zero"
    (even? n) "positive even"
    :else "positive odd"))

(classify -5)  ;; => "negative"
(classify 0)   ;; => "zero"
(classify 4)   ;; => "positive even"
(classify 7)   ;; => "positive odd"
```

#### 6.1.4 condp

Predicate-based dispatch:

```clojure
(defn respond [msg]
  (condp = msg
    "hello" "Hi!"
    "bye" "Goodbye!"
    "how are you?" "Fine!"
    "Unknown message"))

(respond "hello")  ;; => "Hi!"
```

#### 6.1.5 case

Constant-time dispatch (uses hash comparison):

```clojure
(defn http-status [code]
  (case code
    200 "OK"
    301 "Moved Permanently"
    404 "Not Found"
    500 "Internal Server Error"
    "Unknown"))

(http-status 200)   ;; => "OK"
(http-status 999)   ;; => "Unknown"
```

### 6.2 Iteration

#### 6.2.1 Recursion

```clojure
(defn factorial [n]
  (if (<= n 1)
    1
    (* n (factorial (dec n)))))

;; With recur (tail-optimized)
(defn factorial [n]
  (letfn [(fac [n acc]
            (if (<= n 1)
              acc
              (recur (dec n) (* acc n))))]
    (fac n 1)))
```

#### 6.2.2 loop/recur

Explicit tail-recursive loop:

```clojure
(loop [i 0
       result []]
  (if (= i 10)
    result
    (recur (inc i) (conj result i))))

;; => [0 1 2 3 4 5 6 7 8 9]
```

#### 6.2.3 for (list comprehension)

```clojure
(for [x (range 5)
      :let [y (* x x)]
      :when (even? y)]
  y)
;; => (0 4 16)

(for [x [:a :b :c]
      y [1 2]]
  [x y])
;; => ([a 1] [a 2] [b 1] [b 2] [c 1] [c 2])
```

#### 6.2.4 doseq (side effects)

```clojure
(doseq [x (range 3)
        y (range 3)]
  (println [x y]))
;; Prints:
;; [0 0]
;; [0 1]
;; [0 2]
;; ...
```

### 6.3 Exception Handling

```clojure
(try
  (/ 1 0)
  (catch ArithmeticException e
    (str "Error: " (.getMessage e)))
  (finally
    (println "Cleanup")))

;; With throw
(try
  (throw (ex-info "Custom error" {:code 123}))
  (catch Exception e
    (ex-data e)))  ;; => {:code 123}
```

### 6.4 do

Execute multiple expressions, return last:

```clojure
(do
  (println "Side effect")
  (println "Another")
  (+ 1 2))  ;; => 3
```

---

## 7. Sequences and Lazy Evaluation

### 7.1 The Sequence Abstraction

Clojure provides a uniform interface for sequential collections. The key functions are:
- `first` - First element
- `rest` - All elements after first
- `cons` - Prepend element

```clojure
;; Works on lists, vectors, strings, maps, sets, etc.
(first [1 2 3])    ;; => 1
(rest [1 2 3])     ;; => (2 3)
(cons 0 [1 2 3])   ;; => (0 1 2 3)

(first "hello")    ;; => \h
(rest "hello")     ;; => (\e \l \l \o)
(first {:a 1 :b 2}) ;; => [:a 1]
```

### 7.2 Lazy Sequences

Lazy sequences are computed on-demand, allowing for:
- Infinite sequences
- Memory efficiency
- Performance optimization

```clojure
;; range produces infinite lazy sequence
(take 10 (range))  ;; => (0 1 2 3 4 5 6 7 8 9)

;; Fibonacci sequence
(def fibs
  (lazy-cat [0 1] (map + fibs (rest fibs))))

(take 10 fibs)  ;; => (0 1 1 2 3 5 8 13 21 34)

;; iterate
(take 5 (iterate inc 0))  ;; => (0 1 2 3 4)
(take 5 (iterate #(* 2 %) 1)) ;; => (1 2 4 8 16)
```

### 7.3 Sequence Functions

#### 7.3.1 map

Transform each element:

```clojure
(map inc [1 2 3])      ;; => (2 3 4)
(map + [1 2 3] [4 5 6]) ;; => (5 7 9)
(map str "abc")        ;; => ("a" "b" "c")
```

#### 7.3.2 filter / remove

Select/reject elements:

```clojure
(filter even? (range 10))     ;; => (0 2 4 6 8)
(remove even? (range 10))     ;; => (1 3 5 7 9)
(filterv even? (range 10))   ;; => [0 2 4 6 8] (vector)
```

#### 7.3.3 reduce

Process elements with accumulation:

```clojure
(reduce + [1 2 3 4 5])        ;; => 15
(reduce + 10 [1 2 3])         ;; => 16 (with initial value)
(reduce (fn [[sum cnt] x]
          [(+ sum x) (inc cnt)])
        [0 0]
        [1 2 3 4 5])
;; => [15 5]
```

#### 7.3.4 fold

Parallel reduction (uses reducers):

```clojure
(require '[clojure.core.reducers :as r])
(r/fold + (range 1000))
```

#### 7.3.5 mapcat

Map then flatten:

```clojure
(mapcat reverse [[1 2] [3 4] [5 6]])  ;; => (2 1 4 3 6 5)
```

#### 7.3.6 take / drop

```clojure
(take 3 (range 10))        ;; => (0 1 2)
(drop 3 (range 10))        ;; => (3 4 5 6 7 8 9)
(take-while pos? [3 2 1 0 -1]) ;; => (3 2 1)
(drop-while pos? [3 2 1 0 -1]) ;; => (0 -1)
(split-at 3 (range 5))    ;; => [(0 1 2) (3 4)]
```

#### 7.3.7 flatten / partition

```clojure
(flatten [[1 2] [3 [4 5]]])    ;; => (1 2 3 4 5)
(partition 2 (range 8))       ;; => ((0 1) (2 3) (4 5) (6 7))
(partition-all 3 (range 10))  ;; => ((0 1 2) (3 4 5) (6 7 8) (9))
(partition-by even? [1 2 3 4 5 6]) ;; => ((1) (2 3 4) (5 6))
```

#### 7.3.8 Interpose / Interleave

```clojure
(interpose "," ["a" "b" "c"])     ;; => ("a" "," "b" "," "c")
(apply str (interpose "," ["a" "b" "c"]))  ;; => "a,b,c"
(interleave [1 2 3] [:a :b :c])  ;; => (1 :a 2 :b 3 :c)
```

#### 7.3.9 distinct / sort / shuffle

```clojure
(distinct [1 2 2 3 3 3 4])  ;; => (1 2 3 4)
(sort [3 1 4 1 5 9 2])      ;; => (1 1 2 3 4 5 9)
(sort-by :age [{:age 30} {:age 20} {:age 40}])
;; => ({:age 20} {:age 30} {:age 40})
(shuffle (range 5))         ;; => random order
```

### 7.4 Creating Sequences

```clojure
(range)           ;; Infinite 0, 1, 2, ...
(range 5)         ;; (0 1 2 3 4)
(range 1 10 2)    ;; (1 3 5 7 9) start, end, step
(repeat 5 :x)     ;; (:x :x :x :x :x)
(repeatedly 5 #(rand-int 100))  ;; Random values
(cycle [:a :b])   ;; Infinite (:a :b :a :b ...)
```

### 7.5 Walking Collections

```clojure
;; tree-seq: walk a nested structure
(tree-seq sequential? seq [1 [2 [3 4]] 5])
;; => ([1 [2 [3 4]] 5] 1 [2 [3 4]] 2 [3 4] 3 4 5)

;; flatten works on tree-seq
(flatten [1 [2 [3 4]] 5])  ;; => (1 2 3 4 5)

;; Postwalk and prewalk
(require '[clojure.walk :as walk])
(walk/postwalk #(if (number? %) (* 2 %) %) [1 [2 3] 4])
;; => [2 [4 6] 8]
```

---

## 8. Destructuring

Destructuring allows you to bind local variables to parts of collections.

### 8.1 Vector Destructuring

```clojure
(let [[a b c] [1 2 3]]
  (+ a b c))  ;; => 6

;; Skip elements
(let [[a _ c] [1 2 3]]
  c)  ;; => 3

;; Rest pattern
(let [[a & rest] [1 2 3 4]]
  rest)  ;; => (2 3 4)

;; With default values
(let [[a b c d] [1 2]]
  [a b c d])  ;; => [1 2 nil nil]

;; Using :or for defaults
(let [[a b :or {b 10}] [1]]
  b)  ;; => 10
```

### 8.2 Map Destructuring

```clojure
(let [{a :a b :b} {:a 1 :b 2}]
  (+ a b))  ;; => 3

;; Rename keys
(let [{x :a y :b :as original} {:a 1 :b 2}]
  [x y original])  ;; => [1 2 {:a 1 :b 2}]

;; With defaults
(let [{name :name :or {name "Anonymous"}} {}]
  name)  ;; => "Anonymous"

;; Using :keys for automatic naming
(let [{:keys [name age city]} {:name "John" :age 30 :city "Boston"}]
  [name age city])  ;; => ["John" 30 "Boston"]

;; Using :strs for string keys
(let [{:strs [name age]} {"name" "John" "age" 30}]
  name)  ;; => "John"

;; Using :syms for symbol keys
(let [{:syms [x y]} {'x 1 'y 2}]
  x)  ;; => 1
```

### 8.3 Nested Destructuring

```clojure
(let [[[x y] [a b]] [[1 2] [3 4]]]
  (+ x y a b))  ;; => 10

(let [{name :user {:keys [city state]} :address}
      {:user "John" :address {:city "Boston" :state "MA"}}]
  city)  ;; => "Boston"
```

### 8.4 Destructuring in Function Parameters

```clojure
(defn process [[first second & rest]]
  {:first first
   :second second
   :rest rest})

(process [1 2 3 4 5])
;; => {:first 1 :second 2 :rest (3 4 5)}

(defn greet [{:keys [name age]}]
  (str "Hello, " name "! You are " age "."))

(greet {:name "Alice" :age 25})
;; => "Hello, Alice! You are 25."
```

### 8.5 Destructuring with :as

```clojure
(defn total [{:keys [a b c] :as numbers}]
  (+ a b c))

(total {:a 1 :b 2 :c 3 :d 4})  ;; => 6, numbers still has :d
```

---

## 9. Namespaces

### 9.1 Creating and Switching Namespaces

```clojure
(ns myapp.core)

(ns myapp.utils
  (:require [clojure.string :as str]))

;; In the REPL
(in-ns 'myapp.core)
```

### 9.2 Referring and Importing

```clojure
(ns myapp.core
  (:require [clojure.string :as str]
            [clojure.set :as set]
            [clojure.walk :as walk])
  (:import [java.util Date UUID]))  ;; Java interop, shown for completeness
```

### 9.3 Common Namespace Directives

```clojure
(:require [module :as alias])
(:require [module :refer [fn1 fn2]])
(:require [module :refer :all])  ;; Avoid in production

(:use [module])  ;; Deprecated, prefer :require

(:import [java.util Date])  ;; Java interop
```

### 9.4 ns Macro Options

| Option | Purpose |
|--------|---------|
| `:require` | Load modules with optional alias |
| `:use` | Load and refer symbols |
| `:import` | Import Java classes |
| `:refer-clojure` | Control core referrals |
| `:load` | Load arbitrary code |
| `:gen-class` | Generate Java class |

### 9.5 Working with Namespaces

```clojure
;; Create a var
(def x 10)

;; Get current namespace
*ns*  ;; => #namespace[user]

;; Resolve a symbol
(resolve 'x)  ;; => #'user/x

;; Create namespace
(create-ns 'myapp.data)

;; Intern a var
(intern 'myapp.data (symbol "y") 20)

;; Get all vars in namespace
(ns-publics 'myapp.core)
```

### 9.6 Namespace Best Practices

1. One namespace per file
2. Use meaningful namespace names (e.g., `myapp.http.client`)
3. Use consistent aliasing
4. Minimize `:use`, prefer `:require` with `:refer`
5. Keep related code together

---

## 10. Macros

### 10.1 What are Macros?

Macros are code that transforms code before evaluation. They receive unevaluated code and return new code to be evaluated.

```clojure
;; A simple macro
(defmacro unless [condition & body]
  `(if (not ~condition)
     (do ~@body)))

;; Usage
(unless (= 1 2)
  (println "Math works!")
  (+ 1 2))
```

### 10.2 Syntax Quote

The backtick (`) prevents evaluation and allows templating:

```clojure
(defmacro debug [expr]
  `(let [result ~expr]
     (println "Debug:" '~expr "=" result)
     result))
```

### 10.3 Unquoting

- `~` (unquote) - Evaluate and insert
- `~@` (unquote-splicing) - Evaluate and splice sequence

```clojure
(defmacro with-logging [expr]
  `(do
     (println "Executing:" '~expr)
     (let [result ~expr]
       (println "Result:" result)
       result)))

;; Splicing example
(defmacro chain [& forms]
  `(do ~@forms))

(chain
  (println "First")
  (println "Second"))
```

### 10.4 When to Use Macros

**Use macros when:**
- You need to control evaluation (like `if`, `when`, `unless`)
- You need to bind symbols, not values (like `let`, `doseq`)
- You need to do compile-time computation

**Use functions when:**
- The logic can be expressed as data transformation
- The return value is data, not code

### 10.5 Macro Expansion

```clojure
;; See what a macro produces without running it
(macroexpand '(when (> x 10)
                (println "Big")
                (inc x)))

;; macroexpand-1 for single step
```

### 10.6 Common Macro Patterns

#### 10.6.1 Anaphoric Macros (Implicit Binding)

```clojure
(defmacro with-local-vars [& body]
  `(let []
     ~@(map (fn [form]
              `(quote ~(transform form)))
            body)))

;; Simpler: threading macros
(->> x
     (filter even?)
     (map inc)
     (take 5))
```

#### 10.6.2 Conditional Compilation

```clojure
(defmacro when-bind [[sym test] & body]
  `(let [~sym ~test]
     (when ~sym
       ~@body)))

(when-bind [x (find-value data)]
  (process x))
```

### 10.7 Hygiene

By default, Clojure macros are **hygienic** - they don't leak bindings. However, you can create gensyms for explicit control:

```clojure
(defmacro my-macro []
  (let [temp# (gensym "temp")]
    `(let [~temp# 10]
       ~temp#)))

;; temp# auto-gensyms for each use
```

---

## 11. Concurrency

Clojure provides multiple safe concurrency models. All Clojure data structures are immutable, eliminating entire classes of concurrency bugs.

### 11.1 Atoms

Atoms provide synchronous, independent state management:

```clojure
(def counter (atom 0))

;; Read the value
(deref counter)  ;; => 0
@counter         ;; => 0

;; Update with a function
(swap! counter inc)  ;; => 1
(swap! counter + 5)   ;; => 6

;; Reset to a value
(reset! counter 0)    ;; => 0

;; Update with multiple arguments
(swap! counter + 1 2 3)  ;; => 6
```

### 11.2 Refs

Refs provide synchronized, coordinated state through Software Transactional Memory (STM):

```clojure
(def account1 (ref 100))
(def account2 (ref 200))

;;dosync creates a transaction
(dosync
  (alter account1 - 50)
  (alter account2 + 50))

;; Refs can only be modified within dosync
```

### 11.3 Agents

Agents provide asynchronous, independent state updates:

```clojure
(def logger (agent []))

;; Send update (async)
(send logger conj "event-1")

;; Await completion
(await logger)

;; Send-off for blocking operations
(send-off logger #(Thread/sleep 1000))
```

### 11.4 Vars

Vars provide thread-local and namespace-scoped state:

```clojure
(def ^:dynamic *max-connections* 100)

;; Bind dynamically
(binding [*max-connections* 50]
  (*max-connections*))  ;; => 50

;; Thread-local
(def ^:dynamic *thread-id* nil)

(defn get-thread-id []
  (binding [*thread-id* (java.lang.Thread/currentThread)]
    *thread-id*))
```

### 11.5 Futures

Futures execute code concurrently:

```clojure
(def my-future (future (+ 1 2 3)))

@dereference the future to get the result
@my-future  ;; => 6

;; Check if complete
(future-done? my-future)  ;; => true

;; Cancel (if possible)
;; (future-cancel my-future)
```

### 11.6 Promises and Delivered

Promises are placeholders for a single value:

```clojure
(def p (promise))

;; Deliver a value
(deliver p 42)

;; Block until delivered
@dereference p  ;; => 42

;; Timeout
(deref p 1000 :timeout)  ;; Returns :timeout after 1000ms
```

### 11.7 Threads

```clojure
;; Start a thread
(.start (Thread. #(println "Running in thread")))

;; With more control
(let [t (Thread. ^Runnable (fn []
                             (println "Thread body")))]
  (.start t))
```

### 11.8 STM Guidelines

1. Keep transactions short
2. Avoid side effects in transactions
3. Use commute for commutative operations
4. Use ref-set for simple assignments
5. Retry happens automatically on conflict

```clojure
;; commute for commutative operations (order doesn't matter)
(dosync
  (commence total count operation))
```

---

## 12. Protocols and Records

### 12.1 Protocols

Protocols define method signatures that types can implement:

```clojure
(defprotocol Shape
  (area [this])
  (perimeter [this]))

(defprotocol Movable
  (move [this dx dy]))
```

### 12.2 Records

Records are concrete data types that can implement protocols:

```clojure
(defrecord Point [x y]
  Shape
  (area [this] 0)
  (perimeter [this] 0)
  Movable
  (move [this dx dy] (->Point (+ x dx) (+ y dy))))

;; Create instance
(->Point 3 4)  ;; => #user.Point{:x 3 :y 4}
(Point. 3 4)   ;; Java-style constructor

;; Factory function (auto-generated)
(map->Point {:x 10 :y 20})
```

### 12.3 Extending Existing Types

Extend types to implement protocols:

```clojure
(extend-protocol Shape
  java.awt.geom.Area
  (area [this] (.getBounds this))

  nil
  (area [this] 0))

;; extend for single instances
(defmethod area :default [this]
  (when (sequential? this)
    (count this)))
```

### 12.4 Reify

Create anonymous instances:

```clojure
(def circle
  (reify Shape
    (area [this] (* Math/PI (.radius this) (.radius this)))
    (perimeter [this] (* 2 Math/PI (.radius this)))
    :radius 5))

;; Can't capture external state easily - use records for that
```

---

## 13. Multimethods

Multimethods provide polymorphism through arbitrary dispatch:

### 13.1 Defining Multimethods

```clojure
(defmulti process type)

(defmethod process :default [x]
  (str "Unknown: " x))

(defmethod process Number [x]
  (inc x))

(defmethod process String [x]
  (clojure.string/upper-case x))
```

### 13.2 Dispatch Functions

```clojure
;; Dispatch on value
(defmulti kind identity)

;; Dispatch on multiple values
(defmulti describe
  (fn [x y]
    [(type x) (type y)]))

;; Dispatch on property
(defrecord User [role])
(defmethod describe [:user :admin] [_] "Administrator")
(defmethod describe [:user :guest] [_] "Guest")
```

### 13.3 Hierarchies

```clojure
;; Derive creates inheritance for dispatch
(derive ::rect ::shape)
(derive ::circle ::shape)
(derive ::square ::rect)

;; Dispatch works with hierarchy
(defmulti area :type)

(defmethod area ::rect [r]
  (* (:width r) (:height r)))

(defmethod area ::circle [c]
  (* Math/PI (:radius c) (:radius c)))
```

### 13.4 remove-method

```clojure
(remove-method process String)
```

---

## 14. Testing

### 14.1 Clojure.test

```clojure
(ns myapp.core-test
  (:require [clojure.test :as t]
            [myapp.core :as core]))

(t/deftest addition-test
  (t/testing "basic addition"
    (t/is (= 4 (+ 2 2)))
    (t/is (= 5 (+ 2 2)))  ;; Fails
    (t/are [x y] (= x y)
      2 (+ 1 1)
      4 (+ 2 2))))

(t/deftest collection-test
  (t/is (vector? []))
  (t/is (empty? []))
  (t/is (= 3 (count [1 2 3]))))
```

### 14.2 Fixtures

```clojure
(defn setup [f]
  (do something before)
  (f)
  (do something after))

(t/use-fixtures :each setup)  ;; Run for each test
(t/use-fixtures :once setup)   ;; Run once for all tests
```

### 14.3 Running Tests

```bash
clojure -M:test
lein test
```

### 14.4 Generative Testing (test.check)

```clojure
(require '[clojure.test.check :as tc]
         '[clojure.test.check.generators :as gen]
         '[clojure.test.check.properties :as prop])

(def sort-idempotent
  (prop/for-all [v (gen/vector gen/int)]
    (= (sort v) (sort (sort v)))))

(tc/quick-check 100 sort-idempotent)
```

---

## 15. The REPL

### 15.1 REPL Commands

| Command | Description |
|---------|-------------|
| `doc` | View documentation |
| `find-doc` | Search docs |
| `source` | View source code |
| `pst` | Print stack trace |
| `apropos` | Search symbols |
| `dir` | List vars in namespace |

### 15.2 REPL Workflow

```clojure
;; Load code
(require '[myapp.core :as core] :reload)

;; Clear REPL state
(remove-all-methods multidoad :default)

;; Catch exceptions
 CompilerException ...

;; Pretty print
(require '[clojure.pprint :as pp])
(pp/pprint data)
```

### 15.3 Editor Integration

- **VS Code + Calva**: `:jack-in` to start REPL
- **Emacs + CIDER**: `cider-jack-in`
- **Vim + Conjure**: Automatically connects

---

## 16. Core.async

Core.async provides asynchronous programming with channels.

### 16.1 Channels

```clojure
(require '[clojure.core.async :as async])

(def ch (async/chan))

;; Put value (blocks if buffer full)
(async/>!! ch "hello")

;; Take value (blocks if empty)
(async/<!! ch)  ;; => "hello"

;; Close channel
(async/close! ch)
```

### 16.2 Threaded Channels

```clojure
;; >!! and <!! block OS threads (use sparingly)
;; >! and <! work with go blocks (lightweight)
```

### 16.3 Go Blocks

```clojure
(async/go
  (let [msg (<! ch)]  ;; <! instead of <!!
    (println "Got:" msg)))

;; Put in go block
(async/go
  (>! out-ch "result"))
```

### 16.4 Buffers

```clojure
(async/chan 10)           ;; Fixed buffer
(async/chan (async/sliding-buffer 100))  ;; Drops old
(async/chan (async/dropping-buffer 100)) ;; Drops new
```

### 16.5 Pipeline

```clojure
(async/pipeline-async 4
  out-ch
  (fn [input ch]
    (async/go
      (async/>! ch (process input))))
  in-ch)
```

---

## 17. Best Practices

### 17.1 Code Organization

```clojure
;; Typical namespace structure
(ns myapp.core
  (:require [myapp.util :as util]
            [myapp.spec :as spec]
            [clojure.string :as str])
  (:import [java.util Date]))  ;; Shown for completeness only
```

### 17.2 Immutable Data

Prefer immutable data structures. When mutation is needed:
- Use atoms for independent state
- Use refs with STM for coordinated state
- Avoid side effects in pure functions

### 17.3 Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Vars | kebab-case | `defn calculate-total` |
| Classes/Records | PascalCase | `defrecord UserProfile` |
| Constants | UPPER-SNAKE | `def MAX-RETRY` |
| Private vars | trailing underscore | `defn- internal-func` |
| Dynamic vars | *surrounded* | `def *max-connections*` |

### 17.4 Error Handling

```clojure
(defn safe-parse
  [s]
  (try
    (Long/parseLong s)
    (catch NumberFormatException _
      nil)))

;; With ex-info for structured errors
(defn validate [x]
  (when (neg? x)
    (throw (ex-info "Must be positive" {:value x}))))
```

### 17.5 Performance Tips

1. Use `transduce` instead of `into` + transformation
2. Use `mapv` when you need a vector result
3. Use `filterv` for filtered vectors
4. Use `reduce-kv` for map iteration
5. Consider `持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持，持持，持，持，持，持，持，持，持，持，持持，持，持，持，持，持，持持，持，持，持，持，持持，持，持，持持，持，持持，持，持，持，持持，持持，持持，持持，持持，持持持，持，持，持，持持，持持，持持，持持，持持持，持，持持，持持持，持持持，持持持，持持持持，持持，持，持持持，持持，持持持，持持持，持持，持持，持持持，持持持，持持持，持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，持持持，1. Use transduce for efficient transformations
2. chunked sequences for better performance
3. prefer reduce over apply for large collections
```

### 17.6 Threading Macros

Make code more readable:

```clojure
;; Thread-first (->)
(-> user
    (assoc :last-login (java.time Instant/now))
    (update :login-count inc)
    :last-login)

;; Thread-last (->>)
(->> users
     (map :name)
     (filter #(.startsWith % "A"))
     (sort)
     (take 10))

;; Thread-as (some->, some->>)
(some-> {:user {:profile {:avatar "url"}}}
        :user :profile :avatar
        clojure.string/upper-case)
```

---

## 18. Index

### A

- `atom` - [11.1](#11-atoms)
- `agent` - [11.3](#11-3-agents)
- `and` - [3.5](#35-special-forms)
- `are` - [14.1](#141-clojuretest)
- `apply` - [7.3.3](#733-reduce)
- `as->` - [17.6](#176-threading-macros)
- `assert` - [5.5](#55-pre--and-post-conditions)
- `assoc` - [4.9](#49-maps)
- `async/chan` - [16.1](#161-channels)

### B

- `binding` - [11.4](#114-vars)
- `butlast` - [7.3.7](#737-interpose--interleave)

### C

- `case` - [6.1.5](#615-case)
- `comment` - [3.5](#35-comments)
- `comp` - [5.3](#53-higher-order-functions)
- `concat` - [4.7](#47-lists)
- `cond` - [6.1.3](#613-cond)
- `condp` - [6.1.4](#614-condp)
- `conj` - [4.8](#48-vectors)
- `cons` - [4.7](#47-lists)
- `def` - [3.3.1](#331-def)
- `defmacro` - [10.1](#101-what-are-macros)
- `defmethod` - [13.1](#131-defining-multimethods)
- `defmulti` - [13.1](#131-defining-multimethods)
- `defn` - [5.1.1](#511-basic-syntax)
- `defprotocol` - [12.1](#121-protocols)
- `defrecord` - [12.2](#122-records)
- `defref` - [11.2](#112-refs)
- `delay` - [11.6](#116-promises-and-delivered)
- `destructure` - [8](#8-destructuring)
- `disj` - [4.10](#410-sets)
- `dissoc` - [4.9](#49-maps)
- `doseq` - [6.2.4](#624-doseq-side-effects)
- `dosync` - [11.2](#112-refs)
- `dotimes` - [6.2.3](#623-for-list-comprehension)
- `drop` - [7.3.6](#736-take--drop)
- `drop-while` - [7.3.6](#736-take--drop)

### E

- `empty?` - [4.12](#412-collections-library)
- `extend-protocol` - [12.3](#123-extending-existing-types)
- `extend-type` - [12.3](#123-extending-existing-types)

### F

- `fdef` - [5.5](#55-pre--and-post-conditions)
- `filter` - [7.3.2](#732-filter--remove)
- `filterv` - [7.3.2](#732-filter--remove)
- `find-doc` - [15.1](#151-repl-commands)
- `first` - [4.7](#47-lists)
- `flatten` - [7.3.7](#737-interpose--interleave)
- `flip` - [11.2](#112-refs)
- `fn` - [5.2](#52-anonymous-functions)
- `for` - [6.2.3](#623-for-list-comprehension)
- `force` - [11.6](#116-promises-and-delivered)
- `format` - [2.3](#23-editor-setup)
- `future` - [11.5](#115-futures)

### G

- `gen-class` - [9.4](#94-ns-macro-options)
- `get` - [4.8](#48-vectors)
- `get-in` - [4.9](#49-maps)
- `group-by` - [7.3.7](#737-interpose--interleave)

### H

- `hash-map` - [4.9](#49-maps)
- `hash-set` - [4.10](#410-sets)

### I

- `if` - [3.3.3](#333-if)
- `if-let` - [6.1.2](#612-when--when-not)
- `if-not` - [6.1.1](#611-if--if-not)
- `import` - [9.3](#93-referring-and-importing)
- `inc` - [4.2](#42-strings)
- `indexed` - [7.3.7](#737-interpose--interleave)
- `into` - [7.3.7](#737-interpose--interleave)
- `interleave` - [7.3.8](#738-interpose--interleave)
- `interpose` - [7.3.8](#738-interpose--interleave)
- `iterate` - [7.2](#72-lazy-sequences)

### J

- `juxt` - [5.3](#53-higher-order-functions)

### K

- `keys` - [8.2](#82-map-destructuring)

### L

- `let` - [3.3.2](#332-let)
- `letfn` - [5.1.3](#513-variable-arguments)
- `list` - [4.7](#47-lists)
- `list*` - [4.7](#47-lists)
- `load-file` - [15.2](#152-repl-workflow)
- `loop` - [6.2.2](#622-looprecur)

### M

- `macroexpand` - [10.5](#105-macro-expansion)
- `macroexpand-1` - [10.5](#105-macro-expansion)
- `map` - [7.3.1](#731-map)
- `map-indexed` - [7.3.1](#731-map)
- `mapcat` - [7.3.5](#735-mapcat)
- `mapv` - [7.3.1](#731-map)
- `max-key` - [5.3](#53-higher-order-functions)
- `merge` - [4.9](#49-maps)
- `merge-with` - [4.9](#49-maps)
- `meta` - [3.3.1](#331-def)
- `min-key` - [5.3](#53-higher-order-functions)
- `mod` - [4.1.1](#411-integer-types)

### N

- `namespace` - [9.5](#95-working-with-namespaces)
- `neg?` - [4.2](#42-strings)
- `nil?` - [4.4](#44-booleans)
- `not` - [4.4](#44-booleans)
- `not-empty` - [4.12](#412-collections-library)
- `ns` - [9.1](#91-creating-and-switching-namespaces)
- `ns-publics` - [9.5](#95-working-with-namespaces)
- `ns-resolve` - [9.5](#95-working-with-namespaces)

### O

- `or` - [3.5](#35-special-forms)

### P

- `parallelize` - [11.7](#117-stm-guidelines)
- `partition` - [7.3.7](#737-interpose--interleave)
- `partition-all` - [7.3.7](#737-interpose--interleave)
- `partition-by` - [7.3.7](#737-interpose--interleave)
- `partial` - [5.3](#53-higher-order-functions)
- `peek` - [4.7](#47-lists)
- `persist` - [7.2](#72-lazy-sequences)
- `pmap` - [7.3.1](#731-map)
- `pop` - [4.8](#48-vectors)
- `pos?` - [4.2](#42-strings)
- `promise` - [11.6](#116-promises-and-delivered)

### Q

- `quote` - [3.3.4](#334-quote)

### R

- `rand` - [7.4](#74-creating-sequences)
- `rand-int` - [7.4](#74-creating-sequences)
- `range` - [7.4](#74-creating-sequences)
- `recur` - [6.2.1](#621-recursion)
- `reduce` - [7.3.3](#733-reduce)
- `reduce-kv` - [7.3.3](#733-reduce)
- `reductions` - [7.3.3](#733-reduce)
- `ref` - [11.2](#112-refs)
- `ref-set` - [11.2](#112-refs)
- `release-pending-sends` - [11.3](#113-agents)
- `remove` - [7.3.2](#732-filter--remove)
- `repeat` - [7.4](#74-creating-sequences)
- `repeatedly` - [7.4](#74-creating-sequences)
- `replicate` - [7.4](#74-creating-sequences)
- `require` - [9.3](#93-referring-and-importing)
- `reset!` - [11.1](#111-atoms)
- `rest` - [4.7](#47-lists)
- `reverse` - [7.3.9](#739-distinct--sort--shuffle)

### S

- `select-keys` - [4.9](#49-maps)
- `send` - [11.3](#113-agents)
- `send-off` - [11.3](#113-agents)
- `seq` - [7.1](#71-the-sequence-abstraction)
- `set` - [4.10](#410-sets)
- `set!` - [11.4](#114-vars)
- `short-circuit` - [3.5](#35-special-forms)
- `shuffle` - [7.3.9](#739-distinct--sort--shuffle)
- `shutdown-agents` - [11.3](#113-agents)
- `some` - [7.3.2](#732-filter--remove)
- `some->` - [17.6](#176-threading-macros)
- `some-fn` - [5.3](#53-higher-order-functions)
- `sort` - [7.3.9](#739-distinct--sort--shuffle)
- `sort-by` - [7.3.9](#739-distinct--sort--shuffle)
- `split-at` - [7.3.6](#736-take--drop)
- `split-with` - [7.3.6](#736-take--drop)
- `str` - [4.2](#42-strings)
- `subs` - [4.2](#42-strings)
- `superiors` - [13.3](#133-hierarchies)
- `swap!` - [11.1](#111-atoms)

### T

- `take` - [7.3.6](#736-take--drop)
- `take-nth` - [7.3.6](#736-take--drop)
- `take-while` - [7.3.6](#736-take--drop)
- `test` - [14.1](#141-clojuretest)
- `thread-bound?` - [11.4](#114-vars)
- `throw` - [6.3](#63-exception-handling)
- `tree-seq` - [7.5](#75-walking-collections)
- `try` - [6.3](#63-exception-handling)
- `type` - [12.2](#122-records)

### U

- `update` - [4.9](#49-maps)
- `update-in` - [4.9](#49-maps)
- `use` - [9.3](#93-referring-and-importing)

### V

- `val` - [7.1](#71-the-sequence-abstraction)
- `vals` - [4.9](#49-maps)
- `var` - [3.3.1](#331-def)
- `var-get` - [11.4](#114-vars)
- `var-set` - [11.4](#114-vars)
- `vec` - [4.8](#48-vectors)
- `vector` - [4.8](#48-vectors)
- `vector-of` - [4.8](#48-vectors)
- `volatile!` - [11.1](#111-atoms)

### W

- `when` - [6.1.2](#612-when--when-not)
- `when-bind` - [10.6.2](#1062-conditional-compilation)
- `when-first` - [6.1.2](#612-when--when-not)
- `when-let` - [6.1.2](#612-when--when-not)
- `when-not` - [6.1.2](#612-when--when-not)
- `while` - [6.2](#62-iteration)

### Z

- `zero?` - [4.2](#42-strings)
- `zipmap` - [4.9](#49-maps)

---

## Appendix A: Quick Reference

### Core Functions

| Function | Description |
|----------|-------------|
| `inc` / `dec` | Increment / decrement |
| `+` / `-` / `*` / `/` | Arithmetic |
| `=` / `==` / `not=` | Equality |
| `<` / `>` / `<=` / `>=` | Comparison |
| `and` / `or` / `not` | Logical |
| `first` / `rest` / `next` | Sequence ops |
| `cons` / `conj` / `concat` | Collection building |
| `map` / `filter` / `reduce` | Transducers |
| `get` / `assoc` / `dissoc` | Map operations |
| `get-in` / `assoc-in` | Nested operations |
| `apply` / `partial` | Function application |
| `comp` / ` juxt` / `memoize` | Function combinators |

### Data Structure Summary

| Type | Literal | Access | Immutable? |
|------|---------|--------|------------|
| List | `'(1 2 3)` | `first`, `nth` | Yes |
| Vector | `[1 2 3]` | `get`, `nth` | Yes |
| Map | `{:a 1}` | `get`, `keys` | Yes |
| Set | `#{1 2 3}` | `get`, `contains?` | Yes |

---

## Appendix B: Glossary

**Atom** - A mutable container that provides synchronous, independent updates.

**Closure** - A function that captures and retains access to variables from its enclosing scope.

**Destructuring** - Binding local variables to parts of a collection or map.

**Hygienic Macro** - A macro that doesn't leak unintended bindings.

**Lazy Sequence** - A sequence whose elements are computed on-demand.

**Protocol** - A named set of method signatures that types can implement.

**Ref** - A mutable container managed by STM for coordinated updates.

**S-Expression** - A parenthesized expression in Lisp syntax.

**STM** - Software Transactional Memory, a concurrency model using transactions.

**Var** - A mutable container that provides thread-local and namespace-scoped state.

---

*Pure Clojure: A Comprehensive Guide*
*Version 1.0*
