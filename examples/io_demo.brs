(require "lib/io" :as io)

(defn main []
  (let [path "/tmp/bars_io_demo.txt"
        w (io/write-file path "hello")
        r (io/read-file path)
        a (io/append-file path " world")
        r2 (io/read-file path)
        ex (if (io/exists? path) 1 0)
        mt (io/mtime path)
        del (if (io/delete path) 1 0)
        gone (if (io/exists? path) 1 0)]
    (do (println w)
        (println r)
        (println a)
        (println r2)
        (println ex)
        (println (if (> mt 0) 1 0))
        (println del)
        (println gone)
        0)))
