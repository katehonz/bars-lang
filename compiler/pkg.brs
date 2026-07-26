;; Bars.toml package integration — Stage 12.21+
;; TOML subset:
;;   [dependencies]
;;   foo = { path = "../foo" }
;;   bar = { git = "https://…" }   ; cloned to <project>/target/bars-deps/bar
;;
;; Used by the self-hosted build to resolve package deps for require.
;; slurp / bars_system are provided by the build pipeline (builtins / host).

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

(defn section-name [line]
  (let [s (str-trim line)
        n (count s)]
    (if (< n 3) ""
      (if (if (= (str-get s 0) 91) (= (str-get s (- n 1)) 93) false)
        (str-slice s 1 (- n 1))
        ""))))

;; Single-quote for shell (reject values containing ').
(defn shell-quote [s]
  (if (>= (str-index-of s "'") 0)
    ""
    (str-concat "'" (str-concat s "'"))))

;; "name = { path = \"..\" }" or "{ git = \"url\" }"
;; → [name "path"|"git" value] or 0
(defn parse-dep-line [line]
  (let [s (str-trim line)]
    (if (if (= (count s) 0) true (= (str-get s 0) 35))
      0
      (let [eq (str-index-of s "=")]
        (if (< eq 1) 0
          (let [name (str-trim (str-slice s 0 eq))
                rest (str-slice s (+ eq 1) (count s))
                git-key (str-index-of rest "git")
                path-key (str-index-of rest "path")]
            ;; Prefer git if both present (host: git first)
            (if (>= git-key 0)
              (let [q (first-quoted (str-slice rest git-key (count rest)))]
                (if (= (count q) 0) 0
                  (let [pair (vector)]
                    (do (push pair name) (push pair "git") (push pair q) pair))))
              (if (>= path-key 0)
                (let [q (first-quoted (str-slice rest path-key (count rest)))]
                  (if (= (count q) 0) 0
                    (let [pair (vector)]
                      (do (push pair name) (push pair "path") (push pair q) pair))))
                0))))))))

;; Parse Bars.toml → vector of [name kind value]
(defn parse-deps [text]
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

;; Back-compat alias
(defn parse-path-deps [text]
  (let [raw (parse-deps text)
        n (count raw)
        out (vector)]
    (do (loop [i 0]
          (if (>= i n) 0
            (let [d (get raw i)]
              (if (str-eq? (get d 1) "path")
                (let [pair (vector)]
                  (do (push pair (get d 0))
                      (push pair (get d 2))
                      (push out pair)
                      (recur (+ i 1))))
                (recur (+ i 1))))))
        out)))

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

(defn file-readable? [path]
  (!= (slurp path) 0))

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

;; Clone git dep into project/target/bars-deps/<name>. Returns root or "".
(defn ensure-git-dep [project-dir name url]
  (let [dest (join-path project-dir (join-path "target/bars-deps" name))
        marker (join-path dest "src/lib.brs")
        head (join-path dest ".git/HEAD")]
    (if (if (file-readable? marker) true (file-readable? head))
      dest
      (let [uq (shell-quote url)
            dq (shell-quote dest)
            parent (join-path project-dir "target/bars-deps")]
        (if (if (= (count uq) 0) true (= (count dq) 0))
          (do (println (str-concat "error: pkg: unsafe git url/path for `" (str-concat name "`")))
              "")
          (do (println (str-concat "  📦 git clone " (str-concat name " …")))
              (bars_system (str-concat "mkdir -p " (shell-quote parent)))
              (let [cmd (str-concat "git clone --depth 1 " (str-concat uq (str-concat " " dq)))
                    st (bars_system cmd)]
                (if (!= st 0)
                  (do (println (str-concat "error: pkg: git clone failed for `" (str-concat name "`")))
                      (println (str-concat "  note: " cmd))
                      "")
                  dest))))))))

;; Load all deps for project-dir → [[name root-dir] ...]
;; path deps: join project-dir + relative path
;; git deps: clone (if needed) to target/bars-deps/<name>
(defn load-path-deps [project-dir]
  (let [toml-path (join-path project-dir "Bars.toml")
        text (slurp toml-path)]
    (if (= text 0) (vector)
      (let [raw (parse-deps text)
            n (count raw)
            out (vector)]
        (do (loop [i 0]
              (if (>= i n) 0
                (let [dep (get raw i)
                      name (get dep 0)
                      kind (get dep 1)
                      val (get dep 2)]
                  (if (str-eq? kind "path")
                    (let [root (join-path project-dir val)
                          pair (vector)]
                      (do (push pair name)
                          (push pair root)
                          (push out pair)
                          (recur (+ i 1))))
                    (if (str-eq? kind "git")
                      (let [root (ensure-git-dep project-dir name val)]
                        (if (= (count root) 0)
                          (recur (+ i 1))
                          (let [pair (vector)]
                            (do (push pair name)
                                (push pair root)
                                (push out pair)
                                (recur (+ i 1))))))
                      (recur (+ i 1)))))))
            out)))))

(defn dep-root-by-name [deps name]
  (let [n (count deps)]
    (loop [i 0]
      (if (>= i n) ""
        (let [d (get deps i)]
          (if (str-eq? (get d 0) name) (get d 1)
            (recur (+ i 1))))))))

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
