;; Self-hosted build pipeline — Stage 4/10
;; reader → modules → macros → HIR → LLVM → clang → binary

(require "compiler/reader.brs" :as reader)
(require "compiler/modules.brs" :as mods)
(require "compiler/macros.brs" :as macros)
(require "compiler/hir.brs" :as hir)
(require "compiler/codegen/llvm.brs" :as llvm)

(extern "slurp" [path i64] -> i64)
(extern "spit" [path i64 content i64] -> i64)
(extern "bars_system" [cmd i64] -> i64)

;; Load a .brs file to AST (no require resolution yet)
(defn read-file [path]
  (reader/bars-read (slurp path)))

;; (require "lib/core") and (require "lib/core.brs") both work
(defn ensure-brs-path [path]
  (let [n (count path)]
    (if (< n 4) (str-concat path ".brs")
      (if (if (= (str-get path (- n 4)) 46)
            (if (= (str-get path (- n 3)) 98)
              (if (= (str-get path (- n 2)) 114)
                (= (str-get path (- n 1)) 115)
                false)
              false)
            false)
        path
        (str-concat path ".brs")))))

;; Resolve all requires in an AST (recursive).
;; Returns [flat-ast alias-pairs] where alias-pairs is [[alias prefix] ...]
(defn resolve-requires [ast]
  (let [n (count ast)
        result (vector)
        pairs (vector)]
    (loop [i 0]
      (if (>= i n)
        (let [out (vector)]
          (do (push out result)
              (push out pairs)
              out))
        (let [expr (get ast i)
              req (mods/parse-require expr)]
          (if (> (count req) 0)
            (let [path (ensure-brs-path (get req 0))
                  alias (get req 1)
                  prefix (mods/module-prefix alias)
                  mod-raw (read-file path)
                  mod-resolved (resolve-requires mod-raw)
                  mod-ast (get mod-resolved 0)
                  mod-pairs (get mod-resolved 1)
                  renamed (mods/rename-module mod-ast prefix)
                  pair (vector)]
              (do (mods/append-all result renamed)
                  (mods/append-all pairs mod-pairs)
                  (push pair alias)
                  (push pair prefix)
                  (push pairs pair)
                  (recur (+ i 1))))
            (do (push result expr)
                (recur (+ i 1)))))))))

(defn compile-file [input-path output-path]
  (let [raw (read-file input-path)
        resolved (resolve-requires raw)
        flat (get resolved 0)
        pairs (get resolved 1)
        with-quals (mods/subst-qualified flat pairs)
        expanded (macros/expand-program with-quals)
        hir-lines (hir/lower-program expanded)]
    (do (llvm/compile-llvm hir-lines output-path)
        (let [ll-path (str-concat output-path ".ll")
              cmd (str-concat "clang -Wno-override-module "
                    (str-concat ll-path
                      (str-concat " runtime/bars_runtime.o -lgc -lm -o " output-path)))]
          (bars_system cmd)))))

(defn main []
  (let [n (args-count)]
    (if (< n 3)
      (do (println "Usage: <input.brs> <output_bin>") 1)
      (compile-file (args-get 1) (args-get 2)))))
