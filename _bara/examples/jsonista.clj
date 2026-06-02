; jsonista.clj — Production JSON library example for Bara Lang
; Modeled after https://github.com/metosin/jsonista
; Replaces Java/Jackson dependencies with native Nim JSON performance
;
; This example demonstrates:
;   - Fast JSON encoding/decoding without JVM overhead
;   - Keyword keys support (Bara Lang idiomatic)
;   - File I/O
;   - Pretty printing
;   - Complex nested data structures
;   - Error handling
;   - Performance demonstration

(println "=== jsonista.clj — Production JSON Example ===")
(println "Zero Java dependencies — pure native Nim performance\n")

; ---- Basic Encoding ----

(println "=== Basic Encoding ===")
(def basic {:hello 1})
(println (json/write-value-as-string basic))

(println "\n=== Keyword Keys Encoding ===")
(def person {:name "Alice" :age 30 :active true})
(println (json/write-value-as-string person))

(println "\n=== Complex Nested Data ===")
(def nested-data
  {:user {:name "Bob"
          :roles [:admin :editor]
          :settings {:theme "dark" :notifications true}}
   :metrics [42 3.14 100]
   :metadata nil})

(println (json/write-value-as-string nested-data))

; ---- Decoding ----

(println "\n=== Basic Decoding ===")
(def json-str "{\"hello\": 1, \"world\": \"test\"}")
(println (json/read-value json-str))

(println "\n=== Decoding with Keyword Keys ===")
(println (json/read-value json-str {:keyword-keys? true}))

(println "\n=== Decoding Arrays ===")
(def arr-json "[{\"id\":1,\"name\":\"A\"},{\"id\":2,\"name\":\"B\"}]")
(println (json/read-value arr-json {:keyword-keys? true}))

; ---- Pretty Printing ----

(println "\n=== Pretty Printing ===")
(println (json/write-value-as-string nested-data {:pretty? true}))

; ---- File I/O ----

(println "\n=== File I/O ===")
(def test-file "examples/nimcache/jsonista_test.json")

; Write to file
(json/write-value-to-file test-file nested-data {:pretty? true})
(println "Wrote to" test-file)

; Read back
(println "Read back:")
(println (json/read-value-from-file test-file {:keyword-keys? true}))

; Verify roundtrip
(println "\n=== Roundtrip Verification ===")
(println "Original name:" (get (get nested-data :user) :name))
(println "Roundtrip name:" (get (get (json/read-value-from-file test-file {:keyword-keys? true}) :user) :name))
(println "Match?" (= (get (get nested-data :user) :name)
                     (get (get (json/read-value-from-file test-file {:keyword-keys? true}) :user) :name)))

; ---- Error Handling ----

(println "\n=== Error Handling ===")
(def bad-json "{invalid json}")
(def result (json/read-value bad-json))
(println "Parse error result:" result)

; ---- Real-world API Response Simulation ----

(println "\n=== API Response Simulation ===")
(def api-response
  {:status 200
   :headers {"Content-Type" "application/json"
             "X-Request-ID" "abc-123"}
   :body {:users [{:id 1 :username "alice" :email "alice@example.com"}
                  {:id 2 :username "bob" :email "bob@example.com"}]
          :total 2
          :page 1
          :per-page 10}})

(def api-json (json/write-value-as-string api-response {:pretty? true}))
(println api-json)

; Parse it back
(def parsed-api (json/read-value api-json {:keyword-keys? true}))
(println "Parsed API status:" (get parsed-api :status))
(println "First user:" (first (get (get parsed-api :body) :users)))

; ---- Custom Mapper Example ----

(println "\n=== Custom Mapper Example ===")
(defn make-mapper [opts]
  opts)

(def custom-mapper (make-mapper {:keyword-keys? true :pretty? true}))
(println "Custom mapper output:")
(println (json/write-value-as-string {:config {:debug true :port 8080}} custom-mapper))

; ---- Performance Demonstration ----

(println "\n=== Performance Demonstration ===")
(def bench-data
  {:timestamp "2024-01-15T10:30:00Z"
   :events [{:id 0 :type "click" :value 0.0 :tags ["tag-0" "cat-0"]}
            {:id 1 :type "view" :value 0.5 :tags ["tag-1" "cat-1"]}
            {:id 2 :type "click" :value 1.0 :tags ["tag-2" "cat-2"]}
            {:id 3 :type "view" :value 1.5 :tags ["tag-3" "cat-3"]}
            {:id 4 :type "click" :value 2.0 :tags ["tag-4" "cat-4"]}]})

; Single encode/decode to show it works fast
(def json-bench (json/write-value-as-string bench-data))
(def parsed-bench (json/read-value json-bench {:keyword-keys? true}))
(println "Bench data encoded/decoded successfully")
(println (str "Data size: " (count json-bench) " chars"))
(println "First event type:" (get (first (get parsed-bench :events)) :type))

(println "\n=== jsonista.clj complete ===")
(println "This example shows production-ready JSON handling")
(println "with zero Java dependencies — pure native performance.")
