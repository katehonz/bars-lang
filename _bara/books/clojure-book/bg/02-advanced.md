# Чист Clojure: Разширени теми

## Съдържание

1. [Разширени функции](#1-разширени-функции)
2. [Мързеливи серии - задълбочено](#2-мързеливи-серии---задълбочено)
3. [Трансдюсъри](#3-трансдюсъри)
4. [Specs и валидация](#4-specs-и-валидация)
5. [Протоколът Collection](#5-протоколът-collection)
6. [Reducibles](#6-reducibles)
7. [Паралелизъм](#7-паралелизъм)
8. [Оптимизация на производителността](#8-оптимизация-на-производителността)
9. [Индекс](#9-индекс)

---

## 1. Разширени функции

### 1.1 Вариадични функции

Функциите могат да приемат променлив брой аргументи:

```clojure
(defn print-all [& args]
  (doseq [arg args]
    (println arg)))

(print-all "a" "b" "c")

;; С задължителни аргументи
(defn greet [name & greeting-parts]
  (str (clojure.string/join " " greeting-parts) ", " name "!"))

(greet "World" "Hello" "Good morning")  ;; => "Hello Good morning, World!"
```

### 1.2 Rest параметри в детайли

Символът `&` улавя останалите аргументи като серия:

```clojure
(defn my-apply [f & args]
  (apply f args))

;; Използване с деструктуриране
(defn first-two [[a b & rest]]
  {:first a :second b :rest rest})

(first-two [1 2 3 4 5])
;; => {:first 1 :second 2 :rest (3 4 5)}
```

### 1.3 Аргументи от тип ключова дума

Clojure поддържа аргументи от тип ключова дума чрез деструктуриране:

```clojure
(defn configure [name & {:keys [debug verbose output]
                         :or {debug false verbose false output "stdout"}}]
  {:name name :debug debug :verbose verbose :output output})

(configure "test" :debug true :verbose true :output "file.txt")
;; => {:name "test" :debug true :verbose true :output "file.txt"}
```

### 1.4 Взаимна рекурсия

Функциите могат да се извикват една друга:

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

### 1.5 Мемоизация

Кеширане на резултати от функции:

```clojure
(defn slow-fib [n]
  (if (<= n 1)
    n
    (+ (slow-fib (- n 1))
       (slow-fib (- n 2)))))

(def memo-fib (memoize slow-fib))

;; Разликата във времето е драматична за по-големи n
(time (memo-fib 35))  ;; Много по-бързо
```

### 1.6 Пред- и пост-условия

Валидиране на входове и изходи:

```clojure
(defn absolute-value [n]
  {:pre [(number? n)]
   :post [(number? %)
          (>= % 0)]}
  (if (neg? n)
    (- n)
    n))

(defn divide [a b]
  {:pre [(not (zero? b)) "Делителят не може да е нула"]}
  (/ a b))
```

### 1.7 Метаданни на функции

Функциите могат да имат метаданни:

```clojure
(defn ^:private internal-helper [x]
  x)

(defn ^:deprecated old-function [x]
  x)

;; Проверете метаданните
(meta #'internal-helper)
;; => {:private true, ...}
```

### 1.8 Арности и претоварване

```clojure
(defn arity-error []
  (throw (ex-info "Невалидна арност" {})))

(defn complete
  ([x] (complete x 1))
  ([x y] (+ x y))
  ([x y z] (+ x y z)))
```

---

## 2. Мързеливи серии - задълбочено

### 2.1 Реализиране на серии

Мързеливите серии се реализират (оценяват) при необходимост:

```clojure
(def lazy-nats (range))  ;; Безкрайни

(take 10 lazy-nats)  ;; Реализира първите 10

;; Принудете пълна реализация
(doall lazy-nats)   ;; Опасно: безкрайна!
(doall (take 1000 lazy-nats))
```

### 2.2 Chunked серии

Мързеливите серии на Clojure са chunked (типично 32 елемента):

```clojure
;; Range създава chunked серии
(class (range 100))  ;; => clojure.lang.LongRange

;; Всеки chunk се реализира наведнъж
```

### 2.3 Lazy Cons и реализация

```clojure
;; cons създава мързелива серия
(def custom-seq (cons 1 (lazy-seq (cons 2 ()))))

;; lazy-seq отлага изчисленията
(defn fibs []
  (cons 0
        (cons 1
              (map + (fibs) (rest (fibs))))))
```

### 2.4 Seqable обекти

Всеки обект може да бъде направен последователен чрез имплементиране на `seq`:

```clojure
(extend-type String
  clojure.core.protocols/Coll
  (coll [s] (seq s)))

;; Сега низовете работят със серийни функции
(map clojure.string/upper-case "hello")
;; => (\H \E \L \L \O)
```

### 2.5 Безкрайни серии

```clojure
;; Повтарящ се цикъл
(def repeating (cycle [:a :b :c]))

;; Повтаряне завинаги
(def ones (repeatedly 1))
(def randoms (repeatedly #(rand-int 100)))

;; Iterate - прилага функция към предишния резултат
(def powers-of-two (iterate #(* 2 %) 1))
(def collatz (iterate #(if (even? %) (/ % 2) (inc (* 3 %))) 1))
```

### 2.6 Производителност на сериите

```clojure
;; Не дръжте head на мързелива серия
(defn bad-sum []
  (let [large-seq (range 10000000)]
    (reduce + (take 10 large-seq))))  ;; Държи референция към цялата серия

(defn good-sum []
  (reduce + (take 10 (range 10000000))))  ;; Head може да бъде GC'd
```

### 2.7 Eager vs Lazy

```clojure
;; mapcat може да бъде eager
(mapcat reverse [[1 2] [3 4]])  ;; => (2 1 4 3)

;; into принуждава реализация
(into [] (map inc (range 1000)))

;; into е ефективен - не създава междинни колекции
```

---

## 3. Трансдюсъри

Трансдюсърите са съставни, мързеливи трансформации, независими от входния контекст.

### 3.1 Създаване на трансдюсъри

```clojure
;; Без контекст
(def increment (map inc))
(def only-evens (filter even?))

;; Съставяне на трансдюсъри
(def transform (comp
                 (filter even?)
                 (map inc)
                 (take 10)))
```

### 3.2 Използване на трансдюсъри

```clojure
;; С всякаква последователна колекция
(transduce transform + (range 100))
;; => Сума на първите 10 четни числа + 1

(into [] transform (range 100))
;; => [3 5 7 9 11 13 15 17 19 21]

(sequence transform (range 100))
;; => Връща мързелива серия
```

### 3.3 Завършващи редукции

Някои трансдюсъри трябва да направят нещо в края:

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

### 3.4 Ранно прекратяване

```clojure
;; reduced увива стойност за спиране рано
(transduce (filter odd?) + (range 10))
;; => 25 (1+3+5+7+9)

;; Използвайте reduced? за проверка
(reduced? (reduced 5))  ;; => true
```

### 3.5 Cat и завършване

```clojure
(require '[clojure.core.protocols :as p])

;; Завършващата арност на редуциращата функция
(transduce
  (map inc)
  (fn
    ([result] result)  ;; завършваща арност
    ([result input] (rf result input)))
  []
  (range 5))
```

---

## 4. Specs и валидация

### 4.1 Въведение в Spec

Spec предоставя валидация по време на изпълнение и генеративно тестване (чрез `clojure.spec.gen`).

### 4.2 Дефиниране на Specs

```clojure
(require '[clojure.spec.alpha :as s])

(s/def ::name string?)
(s/def ::age (s/and int? #(>= % 0)))
(s/def ::person (s/keys :req [::name ::age]))
```

### 4.3 Конформиране

```clojure
(s/conform ::age 25)    ;; => 25
(s/conform ::age -5)    ;; => :clojure.spec.alpha/invalid

(s/conform ::person {::name "John" ::age 30})
;; => {::name "John" ::age 30}
```

### 4.4 Валидация с `valid?`

```clojure
(s/valid? ::age 25)     ;; => true
(s/valid? ::age -5)     ;; => false
(s/valid? ::person {::name "John" ::age 30})  ;; => true
```

### 4.5 Генеративно тестване

```clojure
(require '[clojure.spec.gen.alpha :as gen])

;; Генериране на стойности
(gen/generate (s/gen ::age))
(gen/sample (s/gen ::age))

;; Тестване със spec
(s/def ::email (s/and string?
                       #(re-find #"@" %)))

(s/fdef greet
  :args (s/cat :name ::name)
  :ret string?)

;; Пускане на генеративни тестове
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

## 5. Протоколът Collection

### 5.1 Йерархия на колекциите

```
IPersistentCollection
  IPersistentList
  IPersistentVector
  IPersistentMap
  IPersistentSet
```

### 5.2 Ключови протоколи

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

### 5.3 Разширяване на колекции

```clojure
;; Използване на reify
(def my-collection
  (reify
    clojure.core.protocols/Coll
    (coll [this] this)
    clojure.core.protocols/Indexed
    (nth [this i] (get [10 20 30] i))))

(nth my-collection 1)  ;; => 20
```

### 5.4 Персонализирани Reducibles

```clojure
(defrecord Range [start end]
  clojure.core.protocols/Coll
  (coll [this] (seq (range start end)))

(reduce + (Range. 1 10))  ;; => 45
```

---

## 6. Reducibles

Reduciers предоставят начин за извършване на паралелни редукции без мързеливи серии.

### 6.1 Използване на Reducers

```clojure
(require '[clojure.core.reducers :as r])

;; Паралелна map (автоматично паралелизира в fold)
(r/map inc (range 1000))

;; fold използва паралелна редукция
(r/fold + (r/map inc (range 1000000)))
```

### 6.2 Персонализирани Reducers

```clojure
;; fold изисква foldable колекция и комбинираща функция
(r/fold
  (fn ([] 0) ([x y] (+ x y)))
  (fn ([x] x) ([x y] (+ x y)))
  (range 1000))
```

---

## 7. Паралелизъм

### 7.1 pmap

Паралелна map (мързелива):

```clojure
;; Като map, но се изпълнява паралелно
(time
  (doall (pmap #(do (Thread/sleep 100) %) (range 10))))
;; Много по-бързо от обикновена map със задръстващи операции
```

### 7.2 Reducers за паралелизъм

```clojure
;; Сгъване с множество ядра
(r/fold 100 + (range 10000000))

;; Персонализирана комбинираща функция
(r/fold
  100
  (fn ([] 0) ([a b] (+ a b)))
  (fn ([] 0) ([a b] (+ a b)))
  (range 10000000))
```

### 7.3 Futures

```clojure
;; Независими паралелни задачи
(let [a (future (compute-a))
      b (future (compute-b))]
  [@a @b])  ;; Изчаква и двете
```

### 7.4 CompletableFuture (само бележка)

Забележка: Java's `CompletableFuture` изисква Java interop. Чисти алтернативи на Clojure включват:
- Core.async канали
- Manifold библиотека
- Promises с futures

---

## 8. Оптимизация на производителността

### 8.1 Persistent структури от данни

Persistent структурите от данни на Clojure споделят структура:

```clojure
;; Добавяне към вектор споделя повечето структура
(def v1 [1 2 3 4 5])
(def v2 (conj v1 6))

;; v1 и v2 споделят [1 2 3 4 5]
;; Само нови възли се създават за пътя към новия елемент
```

### 8.2 Transient структури от данни

За локални, временни мутации:

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

(time (count (slow-accumulation)))   ;; По-бавно
(time (count (fast-accumulation)))   ;; По-бързо
```

### 8.3 Chunked операции

```clojure
;; Предпочитайте chunked операции
(into [] (map inc (range 1000)))        ;; Създава една междинна серия
(into [] (mapcat list (range 100)))     ;; Изравнява мързеливо
```

### 8.4 Поддържане на аргументи eager

```clojure
;; Лошо: дръж head на серията
(def bad-result (map f large-collection))

;; Добро: обработвайте незабавно
(into [] (map f large-collection))
```

### 8.5 Batch обработка

```clojure
;; Вместо много малки операции
(doseq [x items]
  (update-db x))

;; Помислете за batch-ване
(batch-update items)
```

### 8.6 Предварително зареждане и кеширане

```clojure
;; Мемоизация за скъпи изчисления
(def cached-expensive-lookup
  (memoize (fn [k]
             (compute-expensively k))))

;; Предварително зареждане при стартиране
(def initialized-data
  (delay (load-and-process-data)))
```

### 8.7 Бенчмаркинг

```clojure
(require '[criterium.core :as c])

(c/quick-bench (reduce + (range 10000)))
;; Докладва mean, std deviation и т.н.
```

---

## 9. Индекс

### A

- `arity` - [1.8](#18-арности-и-претоварване)
- `assert` - [1.6](#16-пред--и-пост-условия)

### C

- `chunked-seq?` - [2.2](#22-chunked-серии)
- `coll` - [5.3](#53-разширяване-на-колекции)
- `complement` - [1.3](#13-аргументи-от-тип-ключова-дума)
- `comp` - [1.3](#13-аргументи-от-тип-ключова-дума)

### D

- `delay` - [2.6](#26-производителност-на-сериите)
- `delayed?` - [2.6](#26-производителност-на-сериите)
- `deref` - [2.6](#26-производителност-на-сериите)

### F

- `force` - [2.6](#26-производителност-на-сериите)
- `fnil` - [1.3](#13-аргументи-от-тип-ключова-дума)
- `fold` - [6.2](#62-използване-на-reducers)
- `fpartial` - [1.3](#13-аргументи-от-тип-ключова-дума)

### G

- `gen` - [4.5](#45-генеративно-тестване)
- `generate` - [4.5](#45-генеративно-тестване)

### I

- `into` - [3.2](#32-използване-на-трансдюсъри)
- `iterate` - [2.5](#25-безкрайни-серии)

### L

- `lazy-cat` - [2.3](#23-lazy-cons-и-реализация)
- `lazy-seq` - [2.3](#23-lazy-cons-и-реализация)
- `let` - [1.2](#12-rest-параметри-в-детайли)

### M

- `memoize` - [1.5](#15-мемоизация)
- `multi-spec` - [4.6](#46-multi-spec)
- `mmerge` - [6.1](#61-използване-на-reducers)

### N

- `nested` - [5.3](#53-разширяване-на-колекции)
- `next` - [5.2](#52-ключови-протоколи)

### P

- `parallelize` - [7.2](#72-reducers-за-паралелизъм)
- `partial` - [1.3](#13-аргументи-от-тип-ключова-дума)
- `pmap` - [7.1](#71-pmap)
- `promote` - [6.2](#62-използване-на-reducers)

### R

- `realized?` - [2.1](#21-реализиране-на-серии)
- `reduced` - [3.4](#34-ранно-прекратяване)
- `reduced?` - [3.4](#34-ранно-прекратяване)
- `reductions` - [3.3](#33-завършващи-редукции)

### S

- `sample` - [4.5](#45-генеративно-тестване)
- `sequence` - [3.2](#32-използване-на-трансдюсъри)
- `spec` - [4.1](#41-въведение-в-spec)
- `split-with` - [2.6](#26-производителност-на-сериите)

### T

- `test` - [4.5](#45-генеративно-тестване)
- `transduce` - [3.2](#32-използване-на-трансдюсъри)
- `transient` - [8.2](#82-transient-структури-от-данни)
- `tree-seq` - [2.6](#26-производителност-на-сериите)

### V

- `volatile!` - [1.7](#17-метаданни-на-функции)
- `volatile?` - [1.7](#17-метаданни-на-функции)

---

*Чист Clojure: Разширени теми*
