;; Self-hosted build pipeline — Stage 4
;; QBE отпадна (PLAN v6.0). Code generation via LLVM (Stage 7, TODO).
;; Засега: read → ownership → types → HIR (валидация)

(require "compiler/reader.brs" :as reader)
(require "compiler/ownership.brs" :as own)
(require "compiler/types.brs" :as types)
(require "compiler/hir.brs" :as hir)

(extern "slurp" [path i64] -> i64)

(defn compile-file [input-path]
  (let [source (slurp input-path)]
    (let [ast (reader/bars-read source)]
      (do (own/check_ownership ast)
          (do (types/type_check ast)
              (do (hir/lower-program ast)
                  (println "OK: " input-path)
                  0))))))

(defn main []
  (let [args-count (args-count)]
    (if (< args-count 3)
      (do (println "Usage: build <input.brs> <output_bin>")
          (println "  LLVM backend coming in Stage 7")
          1)
      (let [input-path (args-get 1)]
        (compile-file input-path)))))
