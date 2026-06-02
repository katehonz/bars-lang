# Чист Clojure: Изчерпателно Ръководство

## Съдържание

1. [Въведение в Clojure](#1-въведение-в-clojure)
2. [Първи стъпки](#2-първи-стъпки)
3. [Основен синтаксис и форми](#3-основен-синтаксис-и-форми)
4. [Структури от данни](#4-структури-от-данни)
5. [Функции](#5-функции)
6. [Управление на потока](#6-управление-на-потока)
7. [Серии и мързеливо оценяване](#7-серии-и-мързеливо-оценяване)
8. [Деструктуриране](#8-деструктуриране)
9. [Пространства от имена](#9-пространства-от-имена)
10. [Макроси](#10-макроси)
11. [Конкурентност](#11-конкурентност)
12. [Протоколи и записи](#12-протоколи-и-записи)
13. [Многометодни функции](#13-многометодни-функции)
14. [Тестване](#14-тестване)
15. [REPL](#15-repl)
16. [Core.async](#16-coreasync)
17. [Добри практики](#17-добри-практики)
18. [Индекс](#18-индекс)

---

## 1. Въведение в Clojure

### 1.1 Какво е Clojure?

Clojure е съвременен, динамичен и функционален език за програмиране, който работи на Java Virtual Machine (JVM), .NET Common Language Runtime (CLR) и JavaScript двигатели чрез ClojureScript. Създаден от Rich Hickey през 2007 г., Clojure е диалект на Lisp, който набляга на неизменяемостта, функционалното програмиране и кратката изразителност.

### 1.2 Ключови характеристики на Clojure

#### 1.2.1 Неизменяемост по подразбиране

В Clojure всички структури от данни са неизменяеми по подразбиране. Когато "модифицирате" структура от данни, вие всъщност създавате нова версия с желаните промени, докато оригиналът остава непроменен. Този подход води до по-безопасни конкурентни програми и по-чист код.

```clojure
(def original [1 2 3])
(def modified (conj original 4))
;; original => [1 2 3]
;; modified => [1 2 3 4]
```

#### 1.2.2 Функционално програмиране

Clojure насърчава чисти функции без странични ефекти. Функциите са обекти от първи клас, които могат да бъдат предавани като аргументи, връщани от други функции и композирани заедно.

```clojure
(def double (partial * 2))
(def add-ten (partial + 10))
(def transform (comp double add-ten))
(transform 5) ;; => 30
```

#### 1.2.3 Наследство от Lisp

Като диалект на Lisp, Clojure наследява силата на макросите и еднаквото представяне на код като данни. Всичко е израз, който връща стойност, а синтаксисът е прост и последователен.

#### 1.2.4 Полиморфизъм по време на изпълнение

Clojure предоставя множество механизми за полиморфизъм:
- **Протоколи**: Дефинират сигнатури на методи за типове данни
- **Многометодни функции**: Диспечират въз основа на произволни критерии
- **Записи**: Конкретни типове данни, които имплементират протоколи

### 1.3 Защо Чист Clojure?

Въпреки че Clojure работи на JVM и има отлична Java интеграция, тази книга се фокусира върху **чист Clojure** — основните функции на езика, които не разчитат на Java интеграция. Този подход:

- Учи фундаменталните концепции на Clojure
- Прави кода преносим (включително ClojureScript)
- Насърчава мисленето в парадигмата на Clojure
- Избягва ненужно смесване на парадигми

### 1.4 Философията на Clojure

Clojure се придържа към няколко принципа:

1. **Простота**: Трудните неща трябва да бъдат прости, простите неща трябва да бъдат тривиални
2. **Неизменяемост**: Предпочитайте неизменяеми структури от данни за безопасност и конкурентност
3. **Абстракция**: Изграждайте слоеве на абстракция за управление на сложността
4. **Ориентираност към изрази**: Всичко е израз, който връща стойност

---

## 2. Първи стъпки

### 2.1 Инсталация

#### 2.1.1 Използване на CLI инструменти

Препоръчителният начин за инсталиране на Clojure е чрез официалния CLI инструмент:

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

#### 2.1.2 Ръчна инсталация

Изтеглете Clojure JAR файла и го използвайте директно:
```bash
java -jar clojure-1.11.1.jar
```

### 2.2 Вашият първи Clojure проект

#### 2.2.1 Създаване на проект с deps.edn

Създайте нова директория за вашия проект и добавете файл `deps.edn`:

```clojure
{:deps {org.clojure/clojure {:mvn/version "1.11.1"}}}
```

Стартирайте Clojure:
```bash
clj -M
```

#### 2.2.2 Основи на REPL

REPL (Read-Eval-Print Loop) е вашата основна среда за разработка:

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

### 2.3 Настройка на редактора

Популярни редактори за Clojure разработка:

- **VS Code**: Разширение Calva
- **Emacs**: Режим CIDER
- **Vim/Neovim**: Добавка Conjure
- **IntelliJ**: Добавка Cursive

---

## 3. Основен синтаксис и форми

### 3.1 S-Изрази

Кодът на Clojure се пише като **s-изрази** (символни изрази), които са вложени списъци:

```clojure
(оператор операнди...)
```

Първият елемент е операторът (функция, макрос или специална форма), а останалите са операнди.

```clojure
(+ 1 2)        ;; Събиране: 3
(* 2 3 4)       ;; Умножение: 24
(< 1 2 3)       ;; Сравнение: true
(and true false) ;; Логическо И: false
```

### 3.2 Данни като код

В Lisp данните и кодът са едно и също нещо. Това означава, че можете да манипулирате програмите си като данни:

```clojure
'(+ 1 2 3)  ;; Цитиран списък: (+ 1 2 3)
(list + 1 2) ;; Списък със + функцията и числа
```

### 3.3 Специални форми

Специалните форми са примитиви, които не могат да бъдат изразени като функции, защото имат специални правила за оценяване.

#### 3.3.1 def

Дефинира глобална променлива:

```clojure
(def x 10)
(def name "Clojure")
(def items [1 2 3])
```

#### 3.3.2 let

Създава локални свързвания:

```clojure
(let [x 10
      y 20]
  (+ x y))  ;; => 30
```

#### 3.3.3 if

Условно изпълнение:

```clojure
(if условие
  тогава-израз
  else-израз)
```

#### 3.3.4 quote

Предотвратява оценяване:

```clojure
(quote (+ 1 2))  ;; => (+ 1 2)
'(+ 1 2)         ;; Кратка форма: (+ 1 2)
```

### 3.4 Правила за оценяване

1. Числа, низове, булеви стойности, nil и ключови думи **се оценяват като себе си**
2. Символи **се оценяват като стойността** на променливата, която именуват
3. Списъци **се оценяват като извиквания на функции** (ако първият елемент е извикаем)
4. Цитираните изрази **предотвратяват оценяване**

### 3.5 Коментари

```clojure
;; Едноредов коментар

;; Многоредов коментар
;; (няма специален многоредов синтаксис,
;;  просто използвайте няколко едноредови коментара)

(comment
  "Това е коментар блок, който няма да бъде оценен"
  (+ 1 2))
```

### 3.6 Интервали и форматиране

- Clojure е безразличен към интервалите (с изключение в рамките на символи)
- Стандартна конвенция: една интервал след отваряща скоба, преди затваряща
- Подравнявайте аргументите вертикално за четливост:

```clojure
(do-something arg1
              arg2
              arg3)
```

---

## 4. Структури от данни

Clojure предоставя богат набор от неизменяеми структури от данни. Разбирането им е фундаментално за писане на идиоматичен Clojure.

### 4.1 Числа

#### 4.1.1 Целочислени типове

```clojure
42        ;; Десетично
017       ;; Осмично (15)
0x2A      ;; Шестнадесетично (42)
2r101010  ;; Двоично (42)
```

#### 4.1.2 Числа с плаваща запетая

```clojure
3.14
6.022e23
```

#### 4.1.3 Рационални числа

Clojure запазва точността с рационални числа:

```clojure
1/3        ;; Тип рационално
22/7       ;; Приближение на pi
(/ 1 3)    ;; 1/3
```

### 4.2 Низове

```clojure
"Hello, World!"
"Multi-line
string"

;; Конкатенация
(str "Hello" " " "World")  ;; => "Hello World"

;; Подниз
(subs "Hello" 0 5)  ;; => "Hello"

;; Функции за низове
(count "Clojure")   ;; => 7
(reverse "Clojure") ;; => "erujolC"
```

### 4.3 Символи (Characters)

```clojure
\a      ;; Символ a
\newline ;; Нов ред
\space  ;; Интервал
```

### 4.4 Булеви стойности

```clojure
true
false
nil     ;; Представлява отсъствие на стойност
```

Правила за истинност:
- Всичко с изключение на `false` и `nil` е истина
- `and`, `or`, `if`, `when` използват това правило

### 4.5 Ключови думи (Keywords)

Ключовите думи са интернирани низове, използвани като идентификатори, често за ключове в map-ове:

```clojure
:foo
:bar
:user/name   ;; Пространство от имена на ключова дума
::local-key  ;; Автоматично с пространство от имена
```

Ключовите думи се оценяват като себе си и могат да се използват като функции за търсене на стойности в map-ове.

### 4.6 Символи (Symbols)

Символите се оценяват като променливите, които именуват:

```clojure
'x          ;; Символ x (цитиран)
(def x 10)  ;; Дефинира променлива x със стойност 10
x           ;; Оценява се до 10
```

### 4.7 Списъци (Lists)

Списъците са свързани списъци, ефективни за последователен достъп в началото:

```clojure
'(1 2 3)              ;; Цитирайте, за да предотвратите оценяване
(list 1 2 3)         ;; Създава списък
'(+ 1 2)             ;; Списък съдържащ символа +

;; Достъп
(first '(1 2 3))     ;; => 1
(second '(1 2 3))    ;; => 2
(rest '(1 2 3))      ;; => (2 3)
(nth '(1 2 3) 0)      ;; => 1

;; Модификация (връща нов списък)
(cons 0 '(1 2 3))    ;; => (0 1 2 3)
(concat '(1 2) '(3 4)) ;; => (1 2 3 4)
```

### 4.8 Вектори (Vectors)

Векторите са индексирани колекции, ефективни за случаен достъп:

```clojure
[1 2 3 4 5]
(vector 1 2 3)          ;; => [1 2 3]

;; Достъп
(get [10 20 30] 1)      ;; => 20
([10 20 30] 1)          ;; => 20 (достъп като с ключова дума)
(first [1 2 3])         ;; => 1
(second [1 2 3])        ;; => 2
(last [1 2 3])          ;; => 3

;; Модификация (връща нов вектор)
(conj [1 2] 3)          ;; => [1 2 3]
(pop [1 2 3])           ;; => [1 2]
(assoc [1 2 3] 1 20)    ;; => [1 20 3]
(subvec [1 2 3 4 5] 1 3) ;; => [2 3]
```

### 4.9 Map-ове (Maps)

Map-овете са асоциативни структури ключ-стойност:

```clojure
{:name "Alice" :age 30}
(hash-map :a 1 :b 2 :c 3)
(assoc {:a 1} :b 2)      ;; => {:a 1 :b 2}
(dissoc {:a 1 :b 2} :a) ;; => {:b 2}
(get {:a 1} :a)         ;; => 1
({:a 1} :a)             ;; => 1
(:a {:a 1})             ;; => 1 (ключовите думи са функции!)

;; Вложен достъп
(get-in {:user {:address {:city "Sofia"}}}
         [:user :address :city])  ;; => "Sofia"

;; Сливане
(merge {:a 1} {:b 2} {:c 3})  ;; => {:a 1 :b 2 :c 3}
```

### 4.10 Множества (Sets)

Множествата са колекции от уникални стойности:

```clojure
#{1 2 3}
(hash-set 1 2 3 2 1)    ;; => #{1 2 3}
(set [1 2 2 3 3 3])     ;; => #{1 2 3}

;; Операции
(conj #{1 2} 3)         ;; => #{1 2 3}
(disj #{1 2 3} 2)       ;; => #{1 3}
(contains? #{1 2 3} 2)  ;; => true
(get #{1 2 3} 2)        ;; => 2
(clojure.set/union #{1 2} #{2 3})    ;; => #{1 2 3}
(clojure.set/intersection #{1 2 3} #{2 3 4}) ;; => #{2 3}
(clojure.set/difference #{1 2 3} #{2 3})     ;; => #{1}
```

### 4.11 Структуриране на данни

```clojure
;; Представяне на потребител с map
(def user {:name "John"
           :email "john@example.com"
           :roles [:admin :user]})

;; Вложени данни
(def company {:name "TechCorp"
              :employees [{:name "Alice" :dept "Engineering"}
                          {:name "Bob" :dept "Sales"}]
              :locations {:HQ "New York"
                         :branch "Boston"}})
```

### 4.12 Библиотека за колекции

Основни функции за колекции, които работят еднакво върху различни структури:

```clojure
;; Предикати
(empty? [])            ;; => true
(empty? [1 2 3])       ;; => false
(every? even? [2 4 6])  ;; => true
(some odd? [2 4 5 6])   ;; => true
(not-empty [1 2 3])     ;; => [1 2 3]
(not-empty [])          ;; => nil

;; Брой
(count [1 2 3])         ;; => 3
(count {:a 1 :b 2})      ;; => 2

;; Конверсия
(vec '(1 2 3))          ;; => [1 2 3]
(list [1 2 3])          ;; => (1 2 3)
(set [1 2 2 3])          ;; => #{1 2 3}
(mapv inc [1 2 3])       ;; => [2 3 4]
```

---

## 5. Функции

### 5.1 Дефиниране на функции

#### 5.1.1 Основен синтаксис

```clojure
(defn greeting
  "Връща поздравително съобщение"
  [name]
  (str "Hello, " name "!"))

(greeting "World")  ;; => "Hello, World!"
```

#### 5.1.2 Множество арности

Функциите могат да имат различен брой аргументи:

```clojure
(defn add
  ([x] (add x 0))
  ([x y] (+ x y))
  ([x y z] (+ x y z)))

(add 5)    ;; => 5
(add 5 3)  ;; => 8
(add 1 2 3) ;; => 6
```

#### 5.1.3 Променлив брой аргументи

Използвайте `&` за останали параметри:

```clojure
(defn sum [& numbers]
  (reduce + numbers))

(sum 1 2 3 4 5)  ;; => 15
```

### 5.2 Анонимни функции

```clojure
(fn [x] (* x x))
#(* % %)                ;; Имплицитен аргумент
#(* %1 %2)              ;; Множество аргументи
#(reduce + %&)          ;; Останали аргументи
```

### 5.3 Функции от по-висок ред

Функции, които приемат или връщат други функции:

```clojure
(def double #( * % 2))
(def square #(* % %))

(map double [1 2 3 4])    ;; => (2 4 6 8)
(map square [1 2 3 4])    ;; => (1 4 9 16)

(filter even? [1 2 3 4 5 6])  ;; => (2 4 6)

(reduce + [1 2 3 4 5])   ;; => 15
(reduce max [3 1 4 1 5])  ;; => 5

;; Композиране на функции
(def transform (comp square double))
(transform 3)  ;; => 36 (3*2=6, 6*6=36)
```

### 5.4 Затваряния (Closures)

Функции, които улавят своята среда:

```clojure
(defn make-adder [x]
  (fn [y] (+ x y)))

(def add-5 (make-adder 5))
(add-5 10)  ;; => 15
(add-5 3)   ;; => 8

;; Пример за брояч
(defn make-counter []
  (let [count (atom 0)]
    {:increment #(swap! count inc)
     :decrement #(swap! count dec)
     :value #(deref count)}))
```

### 5.5 Пред- и пост-условия

```clojure
(defn absolute-value [n]
  {:pre [(number? n)]
   :post [(>= % 0)]}
  (if (neg? n)
    (- n)
    n))
```

### 5.6 Многометодни функции чрез defn

Въпреки че истинските многометодни функции използват `defmulti` и `defmethod`, обикновените функции могат да симулират dispatch по поведение:

```clojure
(defn process [x]
  (cond
    (string? x) (clojure.string/upper-case x)
    (number? x) (inc x)
    :else "unknown"))
```

---

## 6. Управление на потока

### 6.1 Разклоняване

#### 6.1.1 if / if-not

```clojure
(if условие
  тогава-израз
  else-израз)

(if (pos? -5)
  "положително"
  "не е положително")  ;; => "не е положително"

;; if-not е просто (if (not условие)...)
(if-not (even? 4)
  "нечетно"
  "четно")  ;; => "четно"
```

#### 6.1.2 when / when-not

Единично разклонение без else:

```clojure
(when (pos? 5)
  (println "Положително!")
  (inc 5))  ;; => 6

(when-not (neg? 3)
  "неотрицателно")  ;; => "неотрицателно"
```

#### 6.1.3 cond

Множество условия:

```clojure
(defn classify [n]
  (cond
    (neg? n) "отрицателно"
    (zero? n) "нула"
    (even? n) "положително четно"
    :else "положително нечетно"))

(classify -5)  ;; => "отрицателно"
(classify 0)   ;; => "нула"
(classify 4)   ;; => "положително четно"
(classify 7)   ;; => "положително нечетно"
```

#### 6.1.4 condp

Dispatch базиран на предикат:

```clojure
(defn respond [msg]
  (condp = msg
    "hello" "Здравей!"
    "bye" "Довиждане!"
    "how are you?" "Добре!"
    "Неизвестно съобщение"))

(respond "hello")  ;; => "Здравей!"
```

#### 6.1.5 case

Dispatch с константно време (използва хеш сравнение):

```clojure
(defn http-status [code]
  (case code
    200 "OK"
    301 "Преместен постоянно"
    404 "Не е намерен"
    500 "Вътрешна грешка на сървъра"
    "Неизвестен"))

(http-status 200)   ;; => "OK"
(http-status 999)   ;; => "Неизвестен"
```

### 6.2 Итерация

#### 6.2.1 Рекурсия

```clojure
(defn factorial [n]
  (if (<= n 1)
    1
    (* n (factorial (dec n)))))

;; Със recur (оптимизирано за опашка)
(defn factorial [n]
  (letfn [(fac [n acc]
            (if (<= n 1)
              acc
              (recur (dec n) (* acc n))))]
    (fac n 1)))
```

#### 6.2.2 loop/recur

Явна итерация с опашкова рекурсия:

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

#### 6.2.4 doseq (странични ефекти)

```clojure
(doseq [x (range 3)
        y (range 3)]
  (println [x y]))
;; Отпечатва:
;; [0 0]
;; [0 1]
;; [0 2]
;; ...
```

### 6.3 Обработка на изключения

```clojure
(try
  (/ 1 0)
  (catch ArithmeticException e
    (str "Грешка: " (.getMessage e)))
  (finally
    (println "Почистване")))

;; С throw
(try
  (throw (ex-info "Потребителска грешка" {:code 123}))
  (catch Exception e
    (ex-data e)))  ;; => {:code 123}
```

### 6.4 do

Изпълнява множество изрази, връща последния:

```clojure
(do
  (println "Страничен ефект")
  (println "Още един")
  (+ 1 2))  ;; => 3
```

---

## 7. Серии и мързеливо оценяване

### 7.1 Абстракцията Серия (Sequence)

Clojure предоставя унифициран интерфейс за последователни колекции. Ключовите функции са:
- `first` - Първи елемент
- `rest` - Всички елементи след първия
- `cons` - Добавя елемент в началото

```clojure
;; Работи върху списъци, вектори, низове, map-ове, множества и т.н.
(first [1 2 3])    ;; => 1
(rest [1 2 3])     ;; => (2 3)
(cons 0 [1 2 3])   ;; => (0 1 2 3)

(first "hello")    ;; => \h
(rest "hello")     ;; => (\e \l \l \o)
(first {:a 1 :b 2}) ;; => [:a 1]
```

### 7.2 Мързеливи серии

Мързеливите серии се изчисляват при поискване, което позволява:
-безкрайни серии
- ефективност на паметта
- оптимизация на производителността

```clojure
;; range произвежда безкрайна мързелива серия
(take 10 (range))  ;; => (0 1 2 3 4 5 6 7 8 9)

;; Поредица на Фибоначи
(def fibs
  (lazy-cat [0 1] (map + fibs (rest fibs))))

(take 10 fibs)  ;; => (0 1 1 2 3 5 8 13 21 34)

;; iterate
(take 5 (iterate inc 0))  ;; => (0 1 2 3 4)
(take 5 (iterate #(* 2 %) 1)) ;; => (1 2 4 8 16)
```

### 7.3 Функции за серии

#### 7.3.1 map

Трансформира всеки елемент:

```clojure
(map inc [1 2 3])      ;; => (2 3 4)
(map + [1 2 3] [4 5 6]) ;; => (5 7 9)
(map str "abc")        ;; => ("a" "b" "c")
```

#### 7.3.2 filter / remove

Селектира/отхвърля елементи:

```clojure
(filter even? (range 10))     ;; => (0 2 4 6 8)
(remove even? (range 10))     ;; => (1 3 5 7 9)
(filterv even? (range 10))   ;; => [0 2 4 6 8] (вектор)
```

#### 7.3.3 reduce

Обработва елементи с натрупване:

```clojure
(reduce + [1 2 3 4 5])        ;; => 15
(reduce + 10 [1 2 3])         ;; => 16 (с начална стойност)
(reduce (fn [[sum cnt] x]
          [(+ sum x) (inc cnt)])
        [0 0]
        [1 2 3 4 5])
;; => [15 5]
```

#### 7.3.4 fold

Паралелно намаляване (използва reducers):

```clojure
(require '[clojure.core.reducers :as r])
(r/fold + (range 1000))
```

#### 7.3.5 mapcat

Map-ва и след това изравнява:

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
(shuffle (range 5))         ;; => случайна наредба
```

### 7.4 Създаване на серии

```clojure
(range)           ;; Безкрайни 0, 1, 2, ...
(range 5)         ;; (0 1 2 3 4)
(range 1 10 2)    ;; (1 3 5 7 9) start, end, step
(repeat 5 :x)     ;; (:x :x :x :x :x)
(repeatedly 5 #(rand-int 100))  ;; Случайни стойности
(cycle [:a :b])   ;; Безкрайни (:a :b :a :b ...)
```

### 7.5 Обхождане на колекции

```clojure
;; tree-seq: обхожда вложена структура
(tree-seq sequential? seq [1 [2 [3 4]] 5])
;; => ([1 [2 [3 4]] 5] 1 [2 [3 4]] 2 [3 4] 3 4 5)

;; flatten работи с tree-seq
(flatten [1 [2 [3 4]] 5])  ;; => (1 2 3 4 5)

;; Postwalk и prewalk
(require '[clojure.walk :as walk])
(walk/postwalk #(if (number? %) (* 2 %) %) [1 [2 3] 4])
;; => [2 [4 6] 8]
```

---

## 8. Деструктуриране

Деструктурирането ви позволява да свързвате локални променливи към части от колекции.

### 8.1 Деструктуриране на вектори

```clojure
(let [[a b c] [1 2 3]]
  (+ a b c))  ;; => 6

;; Пропускане на елементи
(let [[a _ c] [1 2 3]]
  c)  ;; => 3

;; Останал pattern
(let [[a & rest] [1 2 3 4]]
  rest)  ;; => (2 3 4)

;; Със стойности по подразбиране
(let [[a b c d] [1 2]]
  [a b c d])  ;; => [1 2 nil nil]

;; Използване на :or за подразбиране
(let [[a b :or {b 10}] [1]]
  b)  ;; => 10
```

### 8.2 Деструктуриране на map-ове

```clojure
(let [{a :a b :b} {:a 1 :b 2}]
  (+ a b))  ;; => 3

;; Преименуване на ключове
(let [{x :a y :b :as original} {:a 1 :b 2}]
  [x y original])  ;; => [1 2 {:a 1 :b 2}]

;; Със стойности по подразбиране
(let [{name :name :or {name "Анонимен"}} {}]
  name)  ;; => "Анонимен"

;; Използване на :keys за автоматично именуване
(let [{:keys [name age city]} {:name "John" :age 30 :city "Boston"}]
  [name age city])  ;; => ["John" 30 "Boston"]

;; Използване на :strs за ключове низове
(let [{:strs [name age]} {"name" "John" "age" 30}]
  name)  ;; => "John"

;; Използване на :syms за ключове символи
(let [{:syms [x y]} {'x 1 'y 2}]
  x)  ;; => 1
```

### 8.3 Вложено деструктуриране

```clojure
(let [[[x y] [a b]] [[1 2] [3 4]]]
  (+ x y a b))  ;; => 10

(let [{name :user {:keys [city state]} :address}
      {:user "John" :address {:city "Boston" :state "MA"}}]
  city)  ;; => "Boston"
```

### 8.4 Деструктуриране в параметри на функции

```clojure
(defn process [[first second & rest]]
  {:first first
   :second second
   :rest rest})

(process [1 2 3 4 5])
;; => {:first 1 :second 2 :rest (3 4 5)}

(defn greet [{:keys [name age]}]
  (str "Здравей, " name "! На " age " години си."))

(greet {:name "Alice" :age 25})
;; => "Здравей, Alice! На 25 години си."
```

### 8.5 Деструктуриране с :as

```clojure
(defn total [{:keys [a b c] :as numbers}]
  (+ a b c))

(total {:a 1 :b 2 :c 3 :d 4})  ;; => 6, numbers все още има :d
```

---

## 9. Пространства от имена

### 9.1 Създаване и превключване на пространства от имена

```clojure
(ns myapp.core)

(ns myapp.utils
  (:require [clojure.string :as str]))

;; В REPL
(in-ns 'myapp.core)
```

### 9.2 Отнасяне и импортиране

```clojure
(ns myapp.core
  (:require [clojure.string :as str]
            [clojure.set :as set]
            [clojure.walk :as walk])
  (:import [java.util Date UUID]))  ;; Java interop, показано за пълнота
```

### 9.3 Често използвани директиви за namespace

```clojure
(:require [module :as alias])
(:require [module :refer [fn1 fn2]])
(:require [module :refer :all])  ;; Избягвайте в production

(:use [module])  ;; Остаряло, предпочитайте :require с :refer

(:import [java.util Date])  ;; Java interop
```

### 9.4 Опции на ns макроса

| Опция | Предназначение |
|--------|---------|
| `:require` | Зарежда модули с незадължителен alias |
| `:use` | Зарежда и отнася символи |
| `:import` | Импортира Java класове |
| `:refer-clojure` | Контролира referrals към core |
| `:load` | Зарежда произволен код |
| `:gen-class` | Генерира Java клас |

### 9.5 Работа с пространства от имена

```clojure
;; Създаване на var
(def x 10)

;; Вземане на текущото namespace
*ns*  ;; => #namespace[user]

;; Resolve на символ
(resolve 'x)  ;; => #'user/x

;; Създаване на namespace
(create-ns 'myapp.data)

;; Intern на var
(intern 'myapp.data (symbol "y") 20)

;; Вземане на всички vars в namespace
(ns-publics 'myapp.core)
```

### 9.6 Добри практики за namespace

1. Едно namespace на файл
2. Използвайте смислени имена (напр. `myapp.http.client`)
3. Използвайте последователно aliasing
4. Минимизирайте `:use`, предпочитайте `:require` с `:refer`
5. Събирайте свързани кодове заедно

---

## 10. Макроси

### 10.1 Какво са макросите?

Макросите са код, който трансформира код преди оценяване. Те получават неоценен код и връщат нов код за оценяване.

```clojure
;; Прост макрос
(defmacro unless [condition & body]
  `(if (not ~condition)
     (do ~@body)))

;; Употреба
(unless (= 1 2)
  (println "Математиката работи!")
  (+ 1 2))
```

### 10.2 Синтаксис цитат (Syntax Quote)

Обратната кавичка (`) предотвратява оценяване и позволява темплейти:

```clojure
(defmacro debug [expr]
  `(let [result ~expr]
     (println "Debug:" '~expr "=" result)
     result))
```

### 10.3 Unquoting

- `~` (unquote) - Оценява и вмъква
- `~@` (unquote-splicing) - Оценява и разгъва последователност

```clojure
(defmacro with-logging [expr]
  `(do
     (println "Изпълнява:" '~expr)
     (let [result ~expr]
       (println "Резултат:" result)
       result)))

;; Splicing пример
(defmacro chain [& forms]
  `(do ~@forms))

(chain
  (println "Първо")
  (println "Второ"))
```

### 10.4 Кога да използваме макроси

**Използвайте макроси когато:**
- Трябва да контролирате оценяването (като `if`, `when`, `unless`)
- Трябва да свързвате символи, не стойности (като `let`, `doseq`)
- Трябва да правите изчисления по време на компилация

**Използвайте функции когато:**
- Логиката може да се изрази като трансформация на данни
- Върнатата стойност е данни, не код

### 10.5 Разгъване на макроси

```clojure
;; Вижте какво произвежда макрос без да го изпълнявате
(macroexpand '(when (> x 10)
                (println "Голям")
                (inc x)))

;; macroexpand-1 за една стъпка
```

### 10.6 Често срещани модели за макроси

#### 10.6.1 Анафорични макроси (имплицитно свързване)

```clojure
(defmacro with-local-vars [& body]
  `(let []
     ~@(map (fn [form]
              `(quote ~(transform form)))
            body)))

;; По-прост: threading macros
(->> x
     (filter even?)
     (map inc)
     (take 5))
```

#### 10.6.2 Условна компилация

```clojure
(defmacro when-bind [[sym test] & body]
  `(let [~sym ~test]
     (when ~sym
       ~@body)))

(when-bind [x (find-value data)]
  (process x))
```

### 10.7 Хигиена

По подразбиране Clojure макросите са **хигиенични** - не изпускат нежелани свързвания. Въпреки това можете да създавате gensyms за ясен контрол:

```clojure
(defmacro my-macro []
  (let [temp# (gensym "temp")]
    `(let [~temp# 10]
       ~temp#)))

;; temp# auto-gensyms за всяка употреба
```

---

## 11. Конкурентност

Clojure предоставя множество безопасни модели за конкурентност. Всички структури от данни в Clojure са неизменяеми, което елиминира цели класове от грешки свързани с конкурентността.

### 11.1 Атоми (Atoms)

Атомите предоставят синхронна, независима работа със състояние:

```clojure
(def counter (atom 0))

;; Четете стойността
(deref counter)  ;; => 0
@counter         ;; => 0

;; Обновявате с функция
(swap! counter inc)  ;; => 1
(swap! counter + 5)   ;; => 6

;; Нулирате към стойност
(reset! counter 0)    ;; => 0

;; Обновяване с множество аргументи
(swap! counter + 1 2 3)  ;; => 6
```

### 11.2 Референции (Refs)

Референциите предоставят синхронизирано, координирано състояние чрез Software Transactional Memory (STM):

```clojure
(def account1 (ref 100))
(def account2 (ref 200))

;; dosync създава транзакция
(dosync
  (alter account1 - 50)
  (alter account2 + 50))

;; Refs могат да бъдат модифицирани само в рамките на dosync
```

### 11.3 Агенти (Agents)

Агентите предоставят асинхронни, независими обновления на състояние:

```clojure
(def logger (agent []))

;; Изпратете обновление (асинхронно)
(send logger conj "event-1")

;; Изчакайте завършване
(await logger)

;; Send-off за блокиращи операции
(send-off logger #(Thread/sleep 1000))
```

### 11.4 Променливи (Vars)

Vars предоставят thread-local и namespace-scoped състояние:

```clojure
(def ^:dynamic *max-connections* 100)

;; Динамично свързване
(binding [*max-connections* 50]
  (*max-connections*))  ;; => 50

;; Thread-local
(def ^:dynamic *thread-id* nil)

(defn get-thread-id []
  (binding [*thread-id* (java.lang.Thread/currentThread)]
    *thread-id*))
```

### 11.5 Futures

Futures изпълняват код конкурентно:

```clojure
(def my-future (future (+ 1 2 3)))

;; Dereference за да получите резултата
@my-future  ;; => 6

;; Проверете дали е завършило
(future-done? my-future)  ;; => true

;; Отказ (ако е възможно)
;; (future-cancel my-future)
```

### 11.6 Promises и Delivered

Promises са placeholders за единична стойност:

```clojure
(def p (promise))

;; Доставяте стойност
(deliver p 42)

;; Блокирате докато бъде доставено
@promise  ;; => 42

;; Timeout
(deref p 1000 :timeout)  ;; Връща :timeout след 1000ms
```

### 11.7 Threads

```clojure
;; Стартирате thread
(.start (Thread. #(println "Работи в thread")))

;; С повече контрол
(let [t (Thread. ^Runnable (fn []
                             (println "Thread тяло")))]
  (.start t))
```

### 11.8 Насоки за STM

1. Поддържайте транзакциите кратки
2. Избягвайте странични ефекти в транзакции
3. Използвайте commute за комутативни операции
4. Използвайте ref-set за прости присвоявания
5. Retry се случва автоматично при конфликт

```clojure
;; commute за комутативни операции (редът няма значение)
(dosync
  (commence total count operation))
```

---

## 12. Протоколи и записи

### 12.1 Протоколи

Протоколите дефинират сигнатури на методи, които типовете могат да имплементират:

```clojure
(defprotocol Shape
  (area [this])
  (perimeter [this]))

(defprotocol Movable
  (move [this dx dy]))
```

### 12.2 Записи

Записите са конкретни типове данни, които могат да имплементират протоколи:

```clojure
(defrecord Point [x y]
  Shape
  (area [this] 0)
  (perimeter [this] 0)
  Movable
  (move [this dx dy] (->Point (+ x dx) (+ y dy))))

;; Създаване на инстанция
(->Point 3 4)  ;; => #user.Point{:x 3 :y 4}
(Point. 3 4)   ;; Java-style конструктор

;; Factory функция (автогенерирана)
(map->Point {:x 10 :y 20})
```

### 12.3 Разширяване на съществуващи типове

Разширете типове да имплементират протоколи:

```clojure
(extend-protocol Shape
  java.awt.geom.Area
  (area [this] (.getBounds this))

  nil
  (area [this] 0))

;; extend за единични инстанции
(defmethod area :default [this]
  (when (sequential? this)
    (count this)))
```

### 12.4 Reify

Създавате анонимни инстанции:

```clojure
(def circle
  (reify Shape
    (area [this] (* Math/PI (.radius this) (.radius this)))
    (perimeter [this] (* 2 Math/PI (.radius this)))
    :radius 5))

;; Не може лесно да улови външно състояние - използвайте records за това
```

---

## 13. Многометодни функции

Многометодните функции предоставят полиморфизъм чрез произволен dispatch:

### 13.1 Дефиниране на многометодни функции

```clojure
(defmulti process type)

(defmethod process :default [x]
  (str "Неизвестно: " x))

(defmethod process Number [x]
  (inc x))

(defmethod process String [x]
  (clojure.string/upper-case x))
```

### 13.2 Функции за dispatch

```clojure
;; Dispatch по стойност
(defmulti kind identity)

;; Dispatch по множество стойности
(defmulti describe
  (fn [x y]
    [(type x) (type y)]))

;; Dispatch по property
(defrecord User [role])
(defmethod describe [:user :admin] [_] "Администратор")
(defmethod describe [:user :guest] [_] "Гост")
```

### 13.3 Йерархии

```clojure
;; Derive създава наследяване за dispatch
(derive ::rect ::shape)
(derive ::circle ::shape)
(derive ::square ::rect)

;; Dispatch работи с йерархията
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

## 14. Тестване

### 14.1 Clojure.test

```clojure
(ns myapp.core-test
  (:require [clojure.test :as t]
            [myapp.core :as core]))

(t/deftest addition-test
  (t/testing "основно събиране"
    (t/is (= 4 (+ 2 2)))
    (t/is (= 5 (+ 2 2)))  ;; Неуспех
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
  (направете нещо преди)
  (f)
  (направете нещо след))

(t/use-fixtures :each setup)  ;; Изпълнява за всеки тест
(t/use-fixtures :once setup)   ;; Изпълнява веднъж за всички тестове
```

### 14.3 Пускане на тестове

```bash
clojure -M:test
lein test
```

### 14.4 Генеративно тестване (test.check)

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

## 15. REPL

### 15.1 Команди на REPL

| Команда | Описание |
|---------|---------|
| `doc` | Преглед на документация |
| `find-doc` | Търсене в документите |
| `source` | Преглед на source код |
| `pst` | Отпечатване на stack trace |
| `apropos` | Търсене на символи |
| `dir` | Списък на vars в namespace |

### 15.2 REPL работен процес

```clojure
;; Зареждане на код
(require '[myapp.core :as core] :reload)

;; Изчистване на REPL състояние
(remove-all-methods multimethod :default)

;; Хващане на изключения
 CompilerException ...

;; Pretty print
(require '[clojure.pprint :as pp])
(pp/pprint data)
```

### 15.3 Интеграция с редактор

- **VS Code + Calva**: `:jack-in` за стартиране на REPL
- **Emacs + CIDER**: `cider-jack-in`
- **Vim + Conjure**: Свързва се автоматично

---

## 16. Core.async

Core.async предоставя асинхронно програмиране с канали.

### 16.1 Канали

```clojure
(require '[clojure.core.async :as async])

(def ch (async/chan))

;; Поставяне на стойност (блокира ако буферът е пълен)
(async/>!! ch "hello")

;; Вземане на стойност (блокира ако е празен)
(async/<!! ch)  ;; => "hello"

;; Затваряне на канал
(async/close! ch)
```

### 16.2 Threaded Channels

```clojure
;; >!! и <!! блокират OS threads (използвайте пестеливо)
;; >! и <! работят с go blocks (леки)
```

### 16.3 Go Blocks

```clojure
(async/go
  (let [msg (<! ch)]  ;; <! вместо <!!
    (println "Получено:" msg)))

;; Поставяне в go block
(async/go
  (>! out-ch "result"))
```

### 16.4 Buffers

```clojure
(async/chan 10)           ;; Фиксиран буфер
(async/chan (async/sliding-buffer 100))  ;; Пуска стари
(async/chan (async/dropping-buffer 100)) ;; Пуска нови
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

## 17. Добри практики

### 17.1 Организация на кода

```clojure
;; Типична структура на namespace
(ns myapp.core
  (:require [myapp.util :as util]
            [myapp.spec :as spec]
            [clojure.string :as str])
  (:import [java.util Date]))  ;; Показано само за пълнота
```

### 17.2 Неизменяеми данни

Предпочитайте неизменяеми структури от данни. Когато мутация е нужна:
- Използвайте atoms за независимо състояние
- Използвайте refs със STM за координирано състояние
- Избягвайте странични ефекти в чисти функции

### 17.3 Конвенции за именуване

| Тип | Конвенция | Пример |
|------|------------|--------|
| Vars | kebab-case | `defn calculate-total` |
| Класове/Записи | PascalCase | `defrecord UserProfile` |
| Константи | UPPER-SNAKE | `def MAX-RETRY` |
| Private vars | trailing underscore | `defn- internal-func` |
| Dynamic vars | *заобиколени* | `def *max-connections*` |

### 17.4 Обработка на грешки

```clojure
(defn safe-parse
  [s]
  (try
    (Long/parseLong s)
    (catch NumberFormatException _
      nil)))

;; С ex-info за структурирани грешки
(defn validate [x]
  (when (neg? x)
    (throw (ex-info "Трябва да е положително" {:value x}))))
```

### 17.5 Съвети за производителност

1. Използвайте `transduce` вместо `into` + трансформация
2. Използвайте `mapv` когато се нуждаете от векторен резултат
3. Използвайте `filterv` за филтрирани вектори
4. Използвайте `reduce-kv` за итерация върху map
5. Помислете за `transducers` за ефективни трансформации

### 17.6 Threading Macros

Направете кода по-четим:

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

## 18. Индекс

### A

- `atom` - [11.1](#11-атоми-atoms)
- `agent` - [11.3](#113-агенти-agents)
- `and` - [3.5](#35-специални-форми)
- `are` - [14.1](#141-clojuretest)
- `apply` - [7.3.3](#733-reduce)
- `as->` - [17.6](#176-threading-macros)
- `assert` - [5.5](#55-пред--и-пост-условия)
- `assoc` - [4.9](#49-map-ове-maps)
- `async/chan` - [16.1](#161-канали)

### B

- `binding` - [11.4](#114-променливи-vars)
- `butlast` - [7.3.7](#737-interpose--interleave)

### C

- `case` - [6.1.5](#615-case)
- `comment` - [3.5](#35-коментари)
- `comp` - [5.3](#53-функции-от-по-висок-ред)
- `concat` - [4.7](#47-списъци-lists)
- `cond` - [6.1.3](#613-cond)
- `condp` - [6.1.4](#614-condp)
- `conj` - [4.8](#48-вектори-vectors)
- `cons` - [4.7](#47-списъци-lists)
- `def` - [3.3.1](#331-def)
- `defmacro` - [10.1](#101-какво-са-макросите)
- `defmethod` - [13.1](#131-дефиниране-на-многометодни-функции)
- `defmulti` - [13.1](#131-дефиниране-на-многометодни-функции)
- `defn` - [5.1.1](#511-основен-синтаксис)
- `defprotocol` - [12.1](#121-протоколи)
- `defrecord` - [12.2](#122-записи)
- `defref` - [11.2](#112-референции-refs)
- `delay` - [11.6](#116-promises-и-delivered)
- `destructure` - [8](#8-деструктуриране)
- `disj` - [4.10](#410-множества-sets)
- `dissoc` - [4.9](#49-map-ове-maps)
- `doseq` - [6.2.4](#624-doseq-странични-ефекти)
- `dosync` - [11.2](#112-референции-refs)
- `dotimes` - [6.2.3](#623-for-list-comprehension)
- `drop` - [7.3.6](#736-take--drop)
- `drop-while` - [7.3.6](#736-take--drop)

### E

- `empty?` - [4.12](#412-библиотека-за-колекции)
- `extend-protocol` - [12.3](#123-разширяване-на-съществуващи-типове)
- `extend-type` - [12.3](#123-разширяване-на-съществуващи-типове)

### F

- `fdef` - [5.5](#55-пред--и-пост-условия)
- `filter` - [7.3.2](#732-filter--remove)
- `filterv` - [7.3.2](#732-filter--remove)
- `find-doc` - [15.1](#151-команди-на-repl)
- `first` - [4.7](#47-списъци-lists)
- `flatten` - [7.3.7](#737-interpose--interleave)
- `flip` - [11.2](#112-референции-refs)
- `fn` - [5.2](#52-анонимни-функции)
- `for` - [6.2.3](#623-for-list-comprehension)
- `force` - [11.6](#116-promises-и-delivered)
- `format` - [2.3](#23-настройка-на-редактора)
- `future` - [11.5](#115-futures)

### G

- `gen-class` - [9.4](#94-опции-на-ns-макроса)
- `get` - [4.8](#48-вектори-vectors)
- `get-in` - [4.9](#49-map-ове-maps)
- `group-by` - [7.3.7](#737-interpose--interleave)

### H

- `hash-map` - [4.9](#49-map-ове-maps)
- `hash-set` - [4.10](#410-множества-sets)

### I

- `if` - [3.3.3](#333-if)
- `if-let` - [6.1.2](#612-when--when-not)
- `if-not` - [6.1.1](#611-if--if-not)
- `import` - [9.3](#93-отнасяне-и-импортиране)
- `inc` - [4.2](#42-низове)
- `indexed` - [7.3.7](#737-interpose--interleave)
- `into` - [7.3.7](#737-interpose--interleave)
- `interleave` - [7.3.8](#738-interpose--interleave)
- `interpose` - [7.3.8](#738-interpose--interleave)
- `iterate` - [7.2](#72-мързеливи-серии)

### J

- `juxt` - [5.3](#53-функции-от-по-висок-ред)

### K

- `keys` - [8.2](#82-деструктуриране-на-map-ове)

### L

- `let` - [3.3.2](#332-let)
- `letfn` - [5.1.3](#513-променлив-брой-аргументи)
- `list` - [4.7](#47-списъци-lists)
- `list*` - [4.7](#47-списъци-lists)
- `load-file` - [15.2](#152-repl-работен-процес)
- `loop` - [6.2.2](#622-looprecur)

### M

- `macroexpand` - [10.5](#105-разгъване-на-макроси)
- `macroexpand-1` - [10.5](#105-разгъване-на-макроси)
- `map` - [7.3.1](#731-map)
- `map-indexed` - [7.3.1](#731-map)
- `mapcat` - [7.3.5](#735-mapcat)
- `mapv` - [7.3.1](#731-map)
- `max-key` - [5.3](#53-функции-от-по-висок-ред)
- `merge` - [4.9](#49-map-ове-maps)
- `merge-with` - [4.9](#49-map-ове-maps)
- `meta` - [3.3.1](#331-def)
- `min-key` - [5.3](#53-функции-от-по-висок-ред)
- `mod` - [4.1.1](#411-целочислени-типове)

### N

- `namespace` - [9.5](#95-работа-с-пространства-от-имена)
- `neg?` - [4.2](#42-низове)
- `nil?` - [4.4](#44-булеви-стойности)
- `not` - [4.4](#44-булеви-стойности)
- `not-empty` - [4.12](#412-библиотека-за-колекции)
- `ns` - [9.1](#91-създаване-и-превключване-на-пространства-от-имена)
- `ns-publics` - [9.5](#95-работа-с-пространства-от-имена)
- `ns-resolve` - [9.5](#95-работа-с-пространства-от-имена)

### O

- `or` - [3.5](#35-специални-форми)

### P

- `parallelize` - [11.7](#117-насоки-за-stm)
- `partition` - [7.3.7](#737-interpose--interleave)
- `partition-all` - [7.3.7](#737-interpose--interleave)
- `partition-by` - [7.3.7](#737-interpose--interleave)
- `partial` - [5.3](#53-функции-от-по-висок-ред)
- `peek` - [4.7](#47-списъци-lists)
- `persist` - [7.2](#72-мързеливи-серии)
- `pmap` - [7.3.1](#731-map)
- `pop` - [4.8](#48-вектори-vectors)
- `pos?` - [4.2](#42-низове)
- `promise` - [11.6](#116-promises-и-delivered)

### Q

- `quote` - [3.3.4](#334-quote)

### R

- `rand` - [7.4](#74-създаване-на-серии)
- `rand-int` - [7.4](#74-създаване-на-серии)
- `range` - [7.4](#74-създаване-на-серии)
- `recur` - [6.2.1](#621-рекурсия)
- `reduce` - [7.3.3](#733-reduce)
- `reduce-kv` - [7.3.3](#733-reduce)
- `reductions` - [7.3.3](#733-reduce)
- `ref` - [11.2](#112-референции-refs)
- `ref-set` - [11.2](#112-референции-refs)
- `release-pending-sends` - [11.3](#113-агенти-agents)
- `remove` - [7.3.2](#732-filter--remove)
- `repeat` - [7.4](#74-създаване-на-серии)
- `repeatedly` - [7.4](#74-създаване-на-серии)
- `replicate` - [7.4](#74-създаване-на-серии)
- `require` - [9.3](#93-отнасяне-и-импортиране)
- `reset!` - [11.1](#11-атоми-atoms)
- `rest` - [4.7](#47-списъци-lists)
- `reverse` - [7.3.9](#739-distinct--sort--shuffle)

### S

- `select-keys` - [4.9](#49-map-ове-maps)
- `send` - [11.3](#113-агенти-agents)
- `send-off` - [11.3](#113-агенти-agents)
- `seq` - [7.1](#71-абстракцията-серия-sequence)
- `set` - [4.10](#410-множества-sets)
- `set!` - [11.4](#114-променливи-vars)
- `short-circuit` - [3.5](#35-специални-форми)
- `shuffle` - [7.3.9](#739-distinct--sort--shuffle)
- `shutdown-agents` - [11.3](#113-агенти-agents)
- `some` - [7.3.2](#732-filter--remove)
- `some->` - [17.6](#176-threading-macros)
- `some-fn` - [5.3](#53-функции-от-по-висок-ред)
- `sort` - [7.3.9](#739-distinct--sort--shuffle)
- `sort-by` - [7.3.9](#739-distinct--sort--shuffle)
- `split-at` - [7.3.6](#736-take--drop)
- `split-with` - [7.3.6](#736-take--drop)
- `str` - [4.2](#42-низове)
- `subs` - [4.2](#42-низове)
- `superiors` - [13.3](#133-йерархии)
- `swap!` - [11.1](#11-атоми-atoms)

### T

- `take` - [7.3.6](#736-take--drop)
- `take-nth` - [7.3.6](#736-take--drop)
- `take-while` - [7.3.6](#736-take--drop)
- `test` - [14.1](#141-clojuretest)
- `thread-bound?` - [11.4](#114-променливи-vars)
- `throw` - [6.3](#63-обработка-на-изключения)
- `tree-seq` - [7.5](#75-обхождане-на-колекции)
- `try` - [6.3](#63-обработка-на-изключения)
- `type` - [12.2](#122-записи)

### U

- `update` - [4.9](#49-map-ове-maps)
- `update-in` - [4.9](#49-map-ове-maps)
- `use` - [9.3](#93-отнасяне-и-импортиране)

### V

- `val` - [7.1](#71-абстракцията-серия-sequence)
- `vals` - [4.9](#49-map-ове-maps)
- `var` - [3.3.1](#331-def)
- `var-get` - [11.4](#114-променливи-vars)
- `var-set` - [11.4](#114-променливи-vars)
- `vec` - [4.8](#48-вектори-vectors)
- `vector` - [4.8](#48-вектори-vectors)
- `vector-of` - [4.8](#48-вектори-vectors)
- `volatile!` - [11.1](#11-атоми-atoms)

### W

- `when` - [6.1.2](#612-when--when-not)
- `when-bind` - [10.6.2](#1062-условна-компилация)
- `when-first` - [6.1.2](#612-when--when-not)
- `when-let` - [6.1.2](#612-when--when-not)
- `when-not` - [6.1.2](#612-when--when-not)
- `while` - [6.2](#62-итерация)

### Z

- `zero?` - [4.2](#42-низове)
- `zipmap` - [4.9](#49-map-ове-maps)

---

## Приложение А: Бърза справка

### Основни функции

| Функция | Описание |
|----------|-------------|
| `inc` / `dec` | Инкремент / декремент |
| `+` / `-` / `*` / `/` | Аритметика |
| `=` / `==` / `not=` | Равенство |
| `<` / `>` / `<=` / `>=` | Сравнение |
| `and` / `or` / `not` | Логически |
| `first` / `rest` / `next` | Операции със серии |
| `cons` / `conj` / `concat` | Изграждане на колекции |
| `map` / `filter` / `reduce` | Трансдюсъри |
| `get` / `assoc` / `dissoc` | Операции с map |
| `get-in` / `assoc-in` | Вложени операции |
| `apply` / `partial` | Приложение на функция |
| `comp` / `juxt` / `memoize` | Комбинатори на функции |

### Обобщение на структурите от данни

| Тип | Литерал | Достъп | Неизменяем? |
|------|---------|--------|------------|
| Списък | `'(1 2 3)` | `first`, `nth` | Да |
| Вектор | `[1 2 3]` | `get`, `nth` | Да |
| Map | `{:a 1}` | `get`, `keys` | Да |
| Множество | `#{1 2 3}` | `get`, `contains?` | Да |

---

## Приложение Б: Речник

**Атом (Atom)** - Мутабилен контейнер, който осигурява синхронни, независими обновления.

**Затваряне (Closure)** - Функция, която улавя и запазва достъп до променливи от обграждащия си обхват.

**Деструктуриране (Destructuring)** - Свързване на локални променливи към части от колекция или map.

**Хигиеничен макрос (Hygienic Macro)** - Макрос, който не изпуска нежелани свързвания.

**Мързелива серия (Lazy Sequence)** - Серия, чиито елементи се изчисляват при поискване.

**Протокол (Protocol)** - Именовано множество от сигнатури на методи, които типовете могат да имплементират.

**Референция (Ref)** - Мутабилен контейнер, управляван от STM за координирани обновления.

**S-Израз (S-Expression)** - Списък с кръгли скоби в Lisp синтаксиса.

**STM** - Software Transactional Memory, модел за конкурентност използващ транзакции.

**Var** - Мутабилен контейнер, който осигурява thread-local и namespace-scoped състояние.

---

*Чист Clojure: Изчерпателно Ръководство*
*Версия 1.0*
