# Pure Clojure: Practical Recipes

## Table of Contents

1. [Common Patterns](#1-common-patterns)
2. [Data Transformation Recipes](#2-data-transformation-recipes)
3. [State Management Recipes](#3-state-management-recipes)
4. [Async Recipes](#4-async-recipes)
5. [Validation Recipes](#5-validation-recipes)
6. [API Design Patterns](#6-api-design-patterns)
7. [Testing Recipes](#7-testing-recipes)
8. [Performance Recipes](#8-performance-recipes)

---

## 1. Common Patterns

### 1.1 Maybe/Option Pattern

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

### 1.2 Either/Result Pattern

```clojure
(defn parse-int [s]
  (try
    {:success (Long/parseLong s)}
    (catch NumberFormatException _
      {:error "Invalid number"})))

(defn bind [result f]
  (if (:error result)
    result
    (f (:success result))))

(-> (parse-int "42")
    (bind #(* % 2))
    (bind #(+ % 1)))
;; => {:success 85}
```

### 1.3 State Machine Pattern

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

### 1.4 Builder Pattern

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

## 2. Data Transformation Recipes

### 2.1 Nested Data Access

```clojure
(defn get-in-safe [m keys default]
  (try
    (get-in m keys)
    (catch NullPointerException _
      default)))

;; With spec validation
(get-in-safe {:user {:address {:city "Sofia"}}}
             [:user :address :city]
             "Unknown")

;; Deep update
(defn update-in-safe [m keys f & args]
  (if (get-in m keys)
    (apply update-in m keys f args)
    m))
```

### 2.2 Grouping and Aggregating

```clojure
;; Group by multiple keys
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

;; Rolling aggregations
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

### 2.4 Tree Operations

```clojure
;; Sum all numeric leaves
(defn tree-sum [tree]
  (reduce + 0
          (tree-seq sequential? seq tree)))

;; Map over tree
(defn tree-map [f tree]
  (postwalk #(if (sequential? %) (mapv f %) %) tree))

;; Find in tree
(defn tree-find [pred tree]
  (first (filter pred (tree-seq sequential? seq tree))))
```

---

## 3. State Management Recipes

### 3.1 Service Pattern with Atoms

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
          (throw (ex-info "Service not running" {})))
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

### 3.3 Cooldown Mechanism

```clojure
(defn make-cooldown [timeout-ms]
  (let [last-call (atom 0)]
    (fn []
      (let [now (System/currentTimeMillis)]
        (when (> (- now @last-call) timeout-ms)
          (reset! last-call now)
          true)))))

(def rate-limiter (make-cooldown 1000))

;; Usage
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
              (swap! state assoc :status :open :last-failure (System/currentTimeMillis))
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

## 4. Async Recipes

### 4.1 Channel Pipeline

```clojure
(defn channel-pipeline [in-f out-f & channels]
  (doseq [ch channels]
    (async/go
      (loop []
        (when-let [value (<! ch)]
          (out-f value)
          (recur))))))

;; Usage
(let [input-chan (async/chan 100)
      process-chan (async/chan 100)
      output-chan (async/chan 100)]
  (async/pipeline 10 process-chan (map process-item) input-chan)
  (async/pipeline 10 output-chan (map format-output) process-chan))
```

### 4.2 Multiplexing Channels

```clojure
(defn multiplex [in-chan & out-chans]
  (async/go
    (loop [value (<! in-chan)]
      (when-not (nil? value)
        (doseq [ch out-chans]
          (>! ch value))
        (recur (<! in-chan))))))

;; Usage
(let [input (async/chan)
      out1 (async/chan)
      out2 (async/chan)]
  (multiplex input out1 out2)
  ;; Now input is broadcast to both outputs
  )
```

### 4.3 Timeout Patterns

```clojure
;; Timeout on operation
(async/go
  (let [result (async/alts!! [work-chan
                              (async/timeout 5000)])]
    (if (= result :timed-out)
      {:status :timeout}
      {:status :success :value (first result)})))

;; Retry with backoff
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

## 5. Validation Recipes

### 5.1 Multi-stage Validation

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
      [field "cannot be blank"])))

(defn max-length [field length]
  (fn [result]
    (when (> (count (get-in result [:data field])) length)
      [field (str "must be at most" length "characters")])))

(validate-stages
  {:name ""}
  (non-blank :name)
  (max-length :name 50))
;; => {:status :error :errors [:name "cannot be blank"]}
```

### 5.2 Schema Validation

```clojure
(def email-regex #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")

(defn validate-email [email]
  (when-not (re-find email-regex email)
    "Invalid email format"))

(defn validate-user [user]
  (reduce-kv
    (fn [errors field validate]
      (if-let [error (validate (get user field))]
        (conj errors [field error])
        errors))
    []
    {:name [#(when (clojure.string/blank? %) "Name required")]
     :email [validate-email
             #(when (> (count %) 100) "Email too long")]
     :age [#(when (or (nil? %) (neg? %)) "Age must be positive")]}))

(validate-user {:name "John" :email "john@example.com" :age 30})
;; => []
```

### 5.3 Contract Testing

```clojure
(defmacro defcontract [name input-spec output-spec & body]
  `(defn ~name [& args#]
     (let [input# (first args#)
           output# (apply ~(into `fn input-spec `@body) args#)]
       (when-not (~output-spec output#)
         (throw (ex-info "Contract violation"
                         {:function '~name
                          :input input#
                          :output output#})))
       output#)))

;; Usage
(defcontract add-positive
  [a number? b number?]  ;; Input spec
  number?                 ;; Output spec
  [a b]
  (+ a b))
```

---

## 6. API Design Patterns

### 6.1 Ring Handlers (Pure Functions)

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

;; Pure handler
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

### 6.3 Route Definitions

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
                 (re-matches (路由->regex p) path))
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
         :body "Not Found"}
        response))))
```

---

## 7. Testing Recipes

### 7.1 Property-Based Testing

```clojure
(defcommutative +
  [a integer? b integer?]
  (= (+ a b) (+ b a)))

(defassociative +
  [a integer? b integer? c integer?]
  (= (+ (+ a b) c) (+ a (+ b c))))

;; Idempotent operations
(defidempotent conj
  [coll vector? item any?]
  (= (conj (conj coll item) item)
     (conj coll item)))
```

### 7.2 Test Fixtures with Random Data

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

### 7.3 Mutation Testing

```clojure
;; Simple mutation testing
(defn mutate-and-test [original-fn test-fn mutation]
  (let [mutated (mutation original-fn)]
    (try
      (test-fn mutated)
      false  ;; Test passed on mutation = bad
      (catch AssertionError _
        true))))  ;; Test caught mutation = good

;; Random mutation generator
(defn random-mutation [f]
  (let [mutations [(fn [x] (inc x))
                   (fn [x] (dec x))
                   (fn [x] (* x 2))]]
    (some #(% f) mutations)))
```

---

## 8. Performance Recipes

### 8.1 Batched Processing

```clojure
(defn batch-process [items batch-size f]
  (into []
        (mapcat f)
        (partition-all batch-size items)))

;; Usage
(batch-process (range 10000) 100
  (fn [batch]
    (mapv expensive-operation batch)))
```

### 8.2 Caching with TTL

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

;; Process huge files line by line
(into []
      (comp
        (drop 1)  ;; Skip header
        (map #(update % 2 parse-long))  ;; Transform column
        (filter #(= "active" (% 3))))
      (take 1000 (lazy-csv-rows "large-file.csv")))
```

### 8.4 Parallel Collection Processing

```clojure
(defn parallel-map [f coll n]
  (let [parts (partition-all (/ (count coll) n) coll)
        results (pmap #(doall (map f %)) parts)]
    (apply concat results)))

;; With reducers for better performance
(require '[clojure.core.reducers :as r])

(defn parallel-reduce [f init coll]
  (r/fold (/ (count coll) 4) f coll))
```

---

*Pure Clojure: Practical Recipes*
