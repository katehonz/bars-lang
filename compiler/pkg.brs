;; Bars.toml package integration — Stage 12.21
;; Minimal TOML subset: [dependencies] name = { path = "..." }
;; Used by the self-hosted build to resolve package path deps.

(defn str-eq? [a b]
  (if (!= (count a) (count b)) false
    (= (str-starts-with? a b) 1)))

(defn is-space? [c]
  (if (= c 32) true
    (if (= c 9) true false)))

(defn str-trim [s]
  (let [n (count s)]
    (loop [i 0]
      (if (>= i n) ""
        (if (is-space? (str-get s i))
          (recur (+ i 1))
          (loop [j (- n 1)]
            (if (< j i) ""
              (if (is-space? (str-get s j))
                (recur (- j 1))
                (str-slice s i (+ j 1))))))))))

(defn split-lines [text]
  (let [n (count text) out (vector)]
    (loop [i 0 start 0]
      (if (>= i n)
        (do (if (< start n) (push out (str-slice text start n)) 0)
            out)
        (if (= (str-get text i) 10)
          (do (push out (str-slice text start i))
              (recur (+ i 1) (+ i 1)))
          (recur (+ i 1) start))))))

;; First double-quoted substring, or "".
(defn first-quoted [s]
  (let [n (count s)]
    (loop [i 0]
      (if (>= i n) ""
        (if (= (str-get s i) 34)
          (loop [j (+ i 1)]
            (if (>= j n) ""
              (if (= (str-get s j) 34)
                (str-slice s (+ i 1) j)
                (recur (+ j 1)))))
          (recur (+ i 1)))))))

;; Line is [section] → section name, else "".
(defn section-name [line]
  (let [s (str-trim line)
        n (count s)]
    (if (< n 3) ""
      (if (if (= (str-get s 0) 91) (= (str-get s (- n 1)) 93) false)
        (str-slice s 1 (- n 1))
        ""))))

;; "name = { path = \"../foo\" }" → [name path] or 0
(defn parse-dep-line [line]
  (let [s (str-trim line)]
    (if (if (= (count s) 0) true (= (str-get s 0) 35))
      0
      (let [eq (str-index-of s "=")]
        (if (< eq 1) 0
          (let [name (str-trim (str-slice s 0 eq))
                rest (str-slice s (+ eq 1) (count s))
                path-key (str-index-of rest "path")]
            (if (< path-key 0) 0
              (let [after (str-slice rest path-key (count rest))
                    q (first-quoted after)]
                (if (= (count q) 0) 0
                  (let [pair (vector)]
                    (do (push pair name) (push pair q) pair)))))))))))

;; Parse Bars.toml text → vector of [dep-name relative-path]
(defn parse-path-deps [text]
  (let [lines (split-lines text)
        n (count lines)
        out (vector)]
    (loop [i 0 in-deps 0]
      (if (>= i n) out
        (let [line (get lines i)
              sec (section-name line)]
          (if (> (count sec) 0)
            (if (str-eq? sec "dependencies")
              (recur (+ i 1) 1)
              (recur (+ i 1) 0))
            (if (= in-deps 0)
              (recur (+ i 1) 0)
              (let [dep (parse-dep-line line)]
                (if (= dep 0)
                  (recur (+ i 1) 1)
                  (do (push out dep)
                      (recur (+ i 1) 1)))))))))))

(defn dirname [path]
  (let [n (count path)]
    (loop [i (- n 1)]
      (if (< i 0) "."
        (if (= (str-get path i) 47)
          (if (= i 0) "/" (str-slice path 0 i))
          (recur (- i 1)))))))

(defn join-path [base rel]
  (if (if (= (count base) 0) true (str-eq? base "."))
    rel
    (if (= (str-get base (- (count base) 1)) 47)
      (str-concat base rel)
      (str-concat base (str-concat "/" rel)))))

;; Walk up from start-dir looking for Bars.toml. Returns dir or "".
(defn find-manifest-dir [start-dir]
  (loop [dir start-dir depth 0]
    (if (> depth 24) ""
      (let [candidate (join-path dir "Bars.toml")
            src (slurp candidate)]
        (if (!= src 0) dir
          (if (if (str-eq? dir ".") true (str-eq? dir "/"))
            ""
            (let [parent (dirname dir)]
              (if (str-eq? parent dir) ""
                (recur parent (+ depth 1))))))))))

;; Load path deps for a project dir → [[name root-dir] ...]
(defn load-path-deps [project-dir]
  (let [toml-path (join-path project-dir "Bars.toml")
        text (slurp toml-path)]
    (if (= text 0) (vector)
      (let [raw (parse-path-deps text)
            n (count raw)
            out (vector)]
        (do (loop [i 0]
              (if (>= i n) 0
                (let [dep (get raw i)
                      name (get dep 0)
                      rel (get dep 1)
                      root (join-path project-dir rel)
                      pair (vector)]
                  (do (push pair name)
                      (push pair root)
                      (push out pair)
                      (recur (+ i 1))))))
            out)))))

;; Look up dep root by package name. Returns root or "".
(defn dep-root-by-name [deps name]
  (let [n (count deps)]
    (loop [i 0]
      (if (>= i n) ""
        (let [d (get deps i)]
          (if (str-eq? (get d 0) name) (get d 1)
            (recur (+ i 1))))))))

;; Strip trailing .brs if present.
(defn strip-brs [path]
  (let [n (count path)]
    (if (< n 4) path
      (if (if (= (str-get path (- n 4)) 46)
            (if (= (str-get path (- n 3)) 98)
              (if (= (str-get path (- n 2)) 114)
                (= (str-get path (- n 1)) 115)
                false)
              false)
            false)
        (str-slice path 0 (- n 4))
        path))))
