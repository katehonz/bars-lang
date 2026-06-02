; AI-Native Tooling Demo
; File and Git operations from Bara Lang

(println "=== File Operations ===")

; Write a file
(file/write "/tmp/ai_demo.txt" "Hello from Bara Lang AI!")

; Read it back
(println (file/read "/tmp/ai_demo.txt"))

; Append to it
(file/append "/tmp/ai_demo.txt" " Appended text.")
(println (file/read "/tmp/ai_demo.txt"))

; Check existence
(println "Exists?" (file/exists? "/tmp/ai_demo.txt"))
(println "Missing?" (file/exists? "/tmp/nowhere.txt"))

; List directory
(println "Files in /tmp:" (file/ls "/tmp"))

(println "")
(println "=== Git Operations ===")

; Show current git status
(println (git/status))

; Show recent commits
(println "Recent commits:" (git/log))

; Show diff
(println "Diff:" (git/diff))
