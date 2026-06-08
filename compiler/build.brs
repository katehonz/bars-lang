;; Self-hosted build pipeline — Stage 4
;; Codegen via LLVM (Stage 7) + Macro expansion (Stage 8)

(require "compiler/reader.brs" :as reader)
(require "compiler/macros.brs" :as macros)
(require "compiler/hir.brs" :as hir)
(require "compiler/codegen/llvm.brs" :as llvm)

(extern "slurp" [path i64] -> i64)
(extern "spit" [path i64 content i64] -> i64)
(extern "bars_system" [cmd i64] -> i64)

(defn compile-file [input-path output-path]
  (let [source (slurp input-path)]
    (let [ast (reader/bars-read source)]
      (let [expanded (macros/expand-program ast)]
        (let [hir-lines (hir/lower-program expanded)]
          (llvm/compile-llvm hir-lines output-path))))))

(defn main []
  (let [args-count (args-count)]
    (if (< args-count 3)
      (do (println "Usage: <input.brs> <output_bin>") 1)
      (let [input-path (args-get 1)]
        (let [output-path (args-get 2)]
          (compile-file input-path output-path))))))
