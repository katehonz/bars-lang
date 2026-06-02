; Word Frequency Counter — data processing example
; Tests: reduce, assoc, get, keys, sort, str, println

(defn add-word [acc word]
  (let [w (clojure.string/lower-case word)]
    (assoc acc w (inc (get acc w 0)))))

(defn word-freq [text]
  (let [words (clojure.string/split text #"\s+")]
    (reduce add-word {} words)))

(def sample "the quick brown fox jumps over the lazy dog the fox")

(println "=== Word Frequency ===")
(let [freq (word-freq sample)]
  (doseq [word (sort (keys freq))]
    (println (str word ": " (get freq word)))))
