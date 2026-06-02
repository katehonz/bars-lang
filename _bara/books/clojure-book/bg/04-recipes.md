# Чист Clojure: Практически рецепти

## Съдържание

1. [Често срещани модели](#1-често-срещани-модели)
2. [Рецепти за трансформация на данни](#2-рецепти-за-трансформация-на-данни)
3. [Рецепти за управление на състояние](#3-рецепти-за-управление-на-състояние)
4. [Async рецепти](#4-async-рецепти)
5. [Рецепти за валидация](#5-рецепти-за-валидация)
6. [Модели за дизайн на API](#6-модели-за-дизайн-на-api)
7. [Рецепти за тестване](#7-рецепти-за-тестване)
8. [Рецепти за производителност](#8-рецепти-за-производителност)

---

## 1. Често срещани модели

### 1.1 Maybe/Option модел

```clojure
(defn safe-divide [a b]
  (if (zero? b)
    nil
    (/ a b)))

(defn map-safe [f coll]
  (sequence (comp (filter some?)
                  (map f))
            coll))

(map-safe #(safe-divide 10 %) [2 0 4 0 5])
;; => (5 2 2)
```

### 1.2 Either/Result модел

```clojure
(defn parse-int [s]
  (try
    {:success (Long/parseLong s)}
    (catch NumberFormatException _
      {:error "Невалидно число"})))

(defn bind [result f]
  (if (:error result)
    result
    (f (:success result))))

(-> (parse-int "42")
    (bind #(* % 2))
    (bind #(+ % 1)))
;; => {:success 85}
```

### 1.3 Модел State Machine

```clojure
(defprotocol StateMachine
  (transition [state event])
  (current-state [state]))

(defrecord TrafficLight [state]
  StateMachine
  (transition [_ event]
    (case [state event]
      [:green :timeout] (->TrafficLight :yellow)
      [:yellow :timeout] (->TrafficLight :red)
      [:red :timeout] (->TrafficLight :green)
      _))
  (current-state [_] state))
```

### 1.4 Builder модел

```clojure
(defn make-builder [defaults]
  (let [state (atom defaults)]
    (reify
      Object
      (toString [_] (str @state))
      clojure.core.protocols/Coll
      (coll [_] (seq @state))
      clojure.lang.IFn
      (invoke [_ k v]
        (swap! state assoc k v)
        this)
      (invoke [_ m]
        (swap! state merge m)
        this))))

(def builder (make-builder {:debug false :timeout 5000}))
(-> builder
    (assoc :host "localhost")
    (merge {:port 8080})
    str)
```

---

## 2. Рецепти за трансформация на данни

### 2.1 Вложен достъп до данни

```clojure
(defn get-in-safe [m keys default]
  (try
    (get-in m keys)
    (catch NullPointerException _
      default)))

;; Със spec валидация
(get-in-safe {:user {:address {:city "Sofia"}}}
             [:user :address :city]
             "Неизвестно")

;; Дълбоко обновление
(defn update-in-safe [m keys f & args]
  (if (get-in m keys)
    (apply update-in m keys f args)
    m))
```

### 2.2 Групиране и агрегиране

```clojure
;; Групиране по множество ключове
(defn group-by-multiple [ks coll]
  (reduce
    (fn [acc item]
      (update-in acc (map item ks) conj item))
    {}
    coll))

(group-by-multiple [:department :role]
                   [{:name "Alice" :department "Eng" :role "Dev"}
                    {:name "Bob" :department "Eng" :role "Dev"}
                    {:name "Carol" :department "Sales" :role "Mgr"}])

;; Rolling агрегации
(defn rolling [f n coll]
  (let [window (vec (take n coll))]
    (lazy-seq
      (cons (f window)
            (rolling f n (rest coll))))))
```

### 2.3 Pivot Tables

```clojure
(defn pivot-table [data row-key col-key value-fn]
  (reduce
    (fn [table row]
      (let [r (row-key row)
            c (col-key row)
            v (value-fn row)]
        (assoc-in table [r c] v)))
    {}
    data))

(pivot-table [{:month "Jan" :region "East" :sales 100}
              {:month "Jan" :region "West" :sales 150}
              {:month "Feb" :region "East" :sales 200}]
            :month :region :sales)
;; => {"Jan" {"East" 100 "West" 150}
       "Feb" {"East" 200}}
```

### 2.4 Операции с дървета

```clojure
;; Сума на всички числови листа
(defn tree-sum [tree]
  (reduce + 0
          (tree-seq sequential? seq tree)))

;; Map върху дърво
(defn tree-map [f tree]
  (postwalk #(if (sequential? %) (mapv f %) %) tree))

;; Намиране в дърво
(defn tree-find [pred tree]
  (first (filter pred (tree-seq sequential? seq tree))))
```

---

## 3. Рецепти за управление на състояние

### 3.1 Service модел с Atoms

```clojure
(defprotocol Service
  (start [this])
  (stop [this])
  (process [this input]))

(defn make-service [config]
  (let [state (atom {:config config
                     :running false
                     :cache {}})]
    (reify
      Service
      (start [_]
        (swap! state assoc :running true))
      (stop [_]
        (swap! state assoc :running false))
      (process [_ input]
        (when-not (:running @state)
          (throw (ex-info "Service не е стартиран" {})))
        (if-let [cached (get-in @state [:cache input])]
          cached
          (let [result (compute input)]
            (swap! state assoc-in [:cache input] result)
            result))))))
```

### 3.2 Event Sourcing

```clojure
(defn make-event-store []
  (let [events (atom [])
        snapshots (atom {})]
    (reify
      Object
      (toString [_] (pr-str @events))
      clojure.core.protocols/Coll
      (coll [_] (seq @events))
      clojure.lang.IFn
      (invoke [_ event]
        (let [new-state (apply-event @snapshots event)]
          (swap! events conj event)
          (when (seq? new-state)
            (reset! snapshots new-state))))
      (invoke [_ n]
        (get @snapshots n)))))

(defn apply-event [state event]
  (case (:type event)
    :created (assoc state (:id event) (:data event))
    :updated (update state (:id event) merge (:data event))
    :deleted (dissoc state (:id event))
    state))
```

### 3.3 Cooldown механизъм

```clojure
(defn make-cooldown [timeout-ms]
  (let [last-call (atom 0)]
    (fn []
      (let [now (System/currentTimeMillis)]
        (when (> (- now @last-call) timeout-ms)
          (reset! last-call now)
          true)))))

(def rate-limiter (make-cooldown 1000))

;; Употреба
(when (rate-limiter)
  (do-something))
```

### 3.4 Circuit Breaker

```clojure
(defn make-circuit-breaker [failure-threshold reset-timeout]
  (let [state (atom {:status :closed
                     :failures 0
                     :last-failure 0})]
    (fn [f]
      (let [current @state]
        (case (:status current)
          :open
          (if (> (- (System/currentTimeMillis) (:last-failure current))
                 reset-timeout)
            (do (swap! state assoc :status :half-open)
                (try
                  (let [result (f)]
                    (swap! state assoc :status :closed :failures 0)
                    result)
                  (catch Exception e
                    (swap! state assoc :status :open :last-failure (System/currentTimeMillis))
                    (throw e))))
            (throw (ex-info "Circuit open" {})))
          :half-open
          (try
            (let [result (f)]
              (swap! state assoc :status :closed :failures 0)
              result)
            (catch Exception e
              (swap! state assoc :status :open :last-failure (System/currentTimeMillis)
)
              (throw e)))
          :closed
          (try
            (let [result (f)]
              (swap! state assoc :failures 0)
              result)
            (catch Exception e
              (let [failures (inc (:failures current))]
                (swap! state assoc :failures failures
                                          :last-failure (System/currentTimeMillis))
                (when (>= failures failure-threshold)
                  (swap! state assoc :status :open))
                (throw e)))))))))
```

---

## 4. Async рецепти

### 4.1 Channel Pipeline

```clojure
(defn channel-pipeline [in-f out-f & channels]
  (doseq [ch channels]
    (async/go
      (loop []
        (when-let [value (<! ch)]
          (out-f value)
          (recur))))))

;; Употреба
(let [input-chan (async/chan 100)
      process-chan (async/chan 100)
      output-chan (async/chan 100)]
  (async/pipeline 10 process-chan (map process-item) input-chan)
  (async/pipeline 10 output-chan (map format-output) process-chan))
```

### 4.2 Multiplexing канали

```clojure
(defn multiplex [in-chan & out-chans]
  (async/go
    (loop [value (<! in-chan)]
      (when-not (nil? value)
        (doseq [ch out-chans]
          (>! ch value))
        (recur (<! in-chan))))))

;; Употреба
(let [input (async/chan)
      out1 (async/chan)
      out2 (async/chan)]
  (multiplex input out1 out2)
  ;; Сега input се broadcast-ва към двата изхода
  )
```

### 4.3 Timeout модели

```clojure
;; Timeout на операция
(async/go
  (let [result (async/alts!! [work-chan
                              (async/timeout 5000)])]
    (if (= result :timed-out)
      {:status :timeout}
      {:status :success :value (first result)})))

;; Retry с exponential backoff
(defn with-retry [f max-attempts delay-ms]
  (async/go
    (loop [attempts 0]
      (let [result (async/<! (async/timeout delay-ms))]
        (if (= :failure result)
          (if (< attempts max-attempts)
            (recur (inc attempts))
            {:status :failed})
          {:status :success :value result})))))
```

### 4.4 Windowing

```clojure
(defn windowed [in size overlap]
  (let [out (async/chan)]
    (async/go
      (loop [window (vec (take size (async/<! in)))]
        (when (seq window)
          (>! out window)
          (let [next-items (vec (take overlap (rest window)))
                remaining (- size overlap)
                new-items (vec (take remaining (async/<! in)))]
            (recur (into next-items new-items))))))
    out))
```

---

## 5. Рецепти за валидация

### 5.1 Многоетапна валидация

```clojure
(defn validate-stages [data & validators]
  (reduce
    (fn [result validator]
      (let [errors (validator result)]
        (if (seq errors)
          (reduced {:status :error :errors errors})
          result)))
    {:status :ok :data data}
    validators))

(defn non-blank [field]
  (fn [result]
    (when (clojure.string/blank? (get-in result [:data field]))
      [field "не може да е празно"])))

(defn max-length [field length]
  (fn [result]
    (when (> (count (get-in result [:data field])) length)
      [field (str "трябва да е най-много" length "символа")])))

(validate-stages
  {:name ""}
  (non-blank :name)
  (max-length :name 50))
;; => {:status :error :errors [:name "не може да е празно"]}
```

### 5.2 Schema валидация

```clojure
(def email-regex #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")

(defn validate-email [email]
  (when-not (re-find email-regex email)
    "Невалиден email формат"))

(defn validate-user [user]
  (reduce-kv
    (fn [errors field validate]
      (if-let [error (validate (get user field))]
        (conj errors [field error])
        errors))
    []
    {:name [#(when (clojure.string/blank? %) "Името е задължително")]
     :email [validate-email
             #(when (> (count %) 100) "Email е твърде дълъг")]
     :age [#(when (or (nil? %) (neg? %)) "Възрастта трябва да е положителна")]}))

(validate-user {:name "John" :email "john@example.com" :age 30})
;; => []
```

### 5.3 Contract тестване

```clojure
(defmacro defcontract [name input-spec output-spec & body]
  `(defn ~name [& args#]
     (let [input# (first args#)
           output# (apply ~(into `fn input-spec `@body) args#)]
       (when-not (~output-spec output#)
         (throw (ex-info "Нарушение на контракт"
                         {:function '~name
                          :input input#
                          :output output#})))
       output#)))

;; Употреба
(defcontract add-positive
  [a number? b number?]  ;; Input spec
  number?                 ;; Output spec
  [a b]
  (+ a b))
```

---

## 6. Модели за дизайн на API

### 6.1 Ring Handlers (Чисти функции)

```clojure
(defn wrap-logging [handler]
  (fn [request]
    (println "Request:" (:uri request))
    (let [response (handler request)]
      (println "Response:" (:status response))
      response)))

(defn wrap-cors [handler]
  (fn [request]
    (let [response (handler request)]
      (assoc response :headers
             (merge (:headers response {})
                    {"Access-Control-Allow-Origin" "*"})))))

;; Чист handler
(defn handle-get-user [request]
  {:status 200
   :headers {"Content-Type" "application/json"}
   :body (pr-str {:name "John" :email "john@example.com"})})
```

### 6.2 Middleware Stack

```clojure
(defn apply-middleware [handler middlewares]
  (reduce
    (fn [h middleware]
      (middleware h))
    handler
    middlewares))

(def app
  (-> handler-get-user
      (apply-middleware [wrap-cors
                         wrap-logging
                         wrap-auth])))
```

### 6.3 Дефиниции на routes

```clojure
(def routes
  [[:get "/users" list-users]
   [:get "/users/:id" get-user]
   [:post "/users" create-user]
   [:put "/users/:id" update-user]
   [:delete "/users/:id" delete-user]])

(defn match-route [method path]
  (some
    (fn [[m p handler]]
      (when (and (= method m)
                 (re-matches (route->regex p) path))
        {:handler handler
         :params (extract-params p path)}))
    routes))
```

### 6.4 Error Handling Middleware

```clojure
(defn wrap-exception [handler]
  (fn [request]
    (try
      (handler request)
      (catch Exception e
        {:status 500
         :headers {"Content-Type" "application/json"}
         :body (pr-str {:error (ex-message e)
                        :data (ex-data e)})}))))

(defn wrap-not-found [handler]
  (fn [request]
    (let [response (handler request)]
      (if (= (:status response) 404)
        {:status 404
         :body "Не е намерен"}
        response))))
```

---

## 7. Рецепти за тестване

### 7.1 Property-Based тестване

```clojure
(defcommutative +
  [a integer? b integer?]
  (= (+ a b) (+ b a)))

(defassociative +
  [a integer? b integer? c integer?]
  (= (+ (+ a b) c) (+ a (+ b c))))

;; Идемпотентни операции
(defidempotent conj
  [coll vector? item any?]
  (= (conj (conj coll item) item)
     (conj coll item)))
```

### 7.2 Test Fixtures с Random Data

```clojure
(defn with-sample-data [f]
  (let [samples (gen/sample (s/gen ::user) 10)]
    (doseq [sample samples]
      (f sample))))

(t/use-fixtures :each with-sample-data)

(t/deftest user-validation-test
  [sample]
  (t/is (nil? (validate-user sample))))
```

### 7.3 Mutation тестване

```clojure
;; Просто mutation тестване
(defn mutate-and-test [original-fn test-fn mutation]
  (let [mutated (mutation original-fn)]
    (try
      (test-fn mutated)
      false  ;; Тестът премина при мутация = лошо
      (catch AssertionError _
        true))))  ;; Тестът хвана мутацията = добро

;; Генератор на случайни мутации
(defn random-mutation [f]
  (let [mutations [(fn [x] (inc x))
                   (fn [x] (dec x))
                   (fn [x] (* x 2))]]
    (some #(% f) mutations)))
```

---

## 8. Рецепти за производителност

### 8.1 Batch обработка

```clojure
(defn batch-process [items batch-size f]
  (into []
        (mapcat f)
        (partition-all batch-size items)))

;; Употреба
(batch-process (range 10000) 100
  (fn [batch]
    (mapv expensive-operation batch)))
```

### 8.2 Caching с TTL

```clojure
(defn make-ttl-cache [ttl-ms]
  (let [cache (atom {})
        cleanup (fn []
                 (let [now (System/currentTimeMillis)]
                   (swap! cache
                          (fn [m]
                            (into {}
                                  (filter #(< (- now (val %)) ttl-ms))
                                  m)))))]
    (fn [f]
      (fn [k]
        (cleanup)
        (if-let [entry (get @cache k)]
          (val entry)
          (let [result (f k)]
            (swap! cache assoc k [(System/currentTimeMillis) result])
            result))))))

(def cached-heavy-operation (make-ttl-cache 60000) heavy-operation)
```

### 8.3 Lazy File Processing

```clojure
(defn lazy-file-lines [filepath]
  (line-seq (clojure.java.io/reader filepath)))

(defn lazy-csv-rows [filepath]
  (map #(clojure.string/split % #",")
       (lazy-file-lines filepath)))

;; Обработка на огромни файлове ред по ред
(into []
      (comp
        (drop 1)  ;; Пропускане на хедър
        (map #(update % 2 parse-long))  ;; Трансформиране на колона
        (filter #(= "active" (% 3))))
      (take 1000 (lazy-csv-rows "large-file.csv")))
```

### 8.4 Паралелна обработка на колекции

```clojure
(defn parallel-map [f coll n]
  (let [parts (partition-all (/ (count coll) n) coll)
        results (pmap #(doall (map f %)) parts)]
    (apply concat results)))

;; С reducers за по-добра производителност
(require '[clojure.core.reducers :as r])

(defn parallel-reduce [f init coll]
  (r/fold (/ (count coll) 4) f coll))
```

---

*Чист Clojure: Практически рецепти*
