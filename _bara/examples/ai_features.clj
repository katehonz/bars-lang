; AI Features Demo — requires API key (DEEPSEEK_API_KEY, OPENAI_API_KEY, or MIMO_API_KEY)
; Run: ./cljnim repl  — then try the commands below
;
; Or compile/run: this file demonstrates the forms

(println "=== Error Handling with try/catch/finally ===")

(defn safe-divide [a b]
  (try
    (println "Dividing" a "by" b)
    (/ a b)
    (catch Exception e
      (do
        (println "Caught error:" (get e :message))
        nil))
    (finally
      (println "Cleanup done"))))

(println "Result:" (safe-divide 10 2))
(println "Result:" (safe-divide 10 0))

(println "")
(println "=== AI Code Generation ===")
(println "Use (ai/generate \"description\") in REPL")
(println "Or CLI: ./cljnim ai 'function to reverse a list'")

(println "")
(println "=== AI Optimization ===")
(println "Use (ai/optimize \"code\") in REPL")
(println "Or REPL command: :optimize (defn sum [nums] (reduce + nums))")

(println "")
(println "=== AI Debugging ===")
(println "Use (ai/debug expr) in REPL")
(println "Or REPL command: :debug (+ 1 2 3)")
