;; Bars Standard Library — File I/O (Phase 14.1)
;; Sync wrappers over C runtime. Async-ready signatures later.
;;
;;   (require "lib/io" :as io)
;;   (io/read-file "x.txt")
;;   (io/write-file "x.txt" "hi")
;;   (io/exists? "x.txt")

(defn exists? [path]
  (= (bars_file_exists path) 1))

(defn mtime [path]
  (bars_file_mtime path))

(defn delete [path]
  (= (bars_file_delete path) 1))

;; Read whole file as string; 0 if missing/unreadable.
(defn read-file [path]
  (slurp path))

;; Write whole file (overwrite). Returns bytes written (0 on failure).
(defn write-file [path content]
  (spit path content))

;; Append to file (create if missing). Returns bytes written.
(defn append-file [path content]
  (bars_file_append path content))

;; True if path is readable as a non-empty or empty file.
(defn readable? [path]
  (if (exists? path)
    (!= (slurp path) 0)
    false))
