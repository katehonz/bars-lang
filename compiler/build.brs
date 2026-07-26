;; Self-hosted build pipeline — Stage 10d / Phase 13
;; reader → modules → macros → types → ownership → HIR → LLVM → clang
;;
;; Exit codes: 0 ok, 1 usage/input, 2 clang, 3 typecheck, 4 ownership
;; Skip: BARS_SKIP_TYPECHECK / BARS_SKIP_OWNERSHIP (non-empty env)

(require "compiler/reader.brs" :as reader)
(require "compiler/modules.brs" :as mods)
(require "compiler/macros.brs" :as macros)
(require "compiler/types.brs" :as types)
(require "compiler/ownership.brs" :as own)
(require "compiler/hir.brs" :as hir)
(require "compiler/codegen/llvm.brs" :as llvm)

(extern "slurp" [path i64] -> i64)
(extern "spit" [path i64 content i64] -> i64)
(extern "bars_system" [cmd i64] -> i64)
(extern "bars_env_set" [name i64] -> i64)

(defn die [msg code]
  (do (println msg) code))

;; Types ON by default (soft warnings). Ownership ON by default (light NLL).
;;   BARS_SKIP_TYPECHECK=1 / BARS_SKIP_OWNERSHIP=1  force off
;;   BARS_STRICT_TYPES=1                            hard-fail type issues
(defn skip-typecheck? []
  (= (bars_env_set "BARS_SKIP_TYPECHECK") 1))

(defn skip-ownership? []
  (= (bars_env_set "BARS_SKIP_OWNERSHIP") 1))

;; Load a .brs file to AST. slurp returns 0 if file missing.
(defn read-file [path]
  (let [src (slurp path)]
    (if (= src 0)
      (do (println (str-concat "error: cannot open file: " path))
          0)
      (reader/bars-read src))))

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
;; Returns [flat-ast alias-pairs] or 0 on read error.
(defn resolve-requires [ast]
  (if (= ast 0) 0
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
                    mod-raw (read-file path)]
                (if (= mod-raw 0)
                  0
                  (let [mod-resolved (resolve-requires mod-raw)]
                    (if (= mod-resolved 0) 0
                      (let [mod-ast (get mod-resolved 0)
                            mod-pairs (get mod-resolved 1)
                            renamed (mods/rename-module mod-ast prefix)
                            pair (vector)]
                        (do (mods/append-all result renamed)
                            (mods/append-all pairs mod-pairs)
                            (push pair alias)
                            (push pair prefix)
                            (push pairs pair)
                            (recur (+ i 1))))))))
              (do (push result expr)
                  (recur (+ i 1))))))))))

(defn strict-types? []
  (= (bars_env_set "BARS_STRICT_TYPES") 1))

(defn run-typecheck [ast]
  (if (skip-typecheck?)
    0
    (let [tc (types/type_check ast)]
      (if (if (strict-types?) (!= tc 0) false)
        tc
        0))))

(defn run-ownership [ast]
  (if (skip-ownership?)
    0
    (own/check_ownership ast)))

(defn compile-file [input-path output-path]
  (let [raw (read-file input-path)]
    (if (= raw 0)
      1
      (let [resolved (resolve-requires raw)]
        (if (= resolved 0)
          1
          (let [flat (get resolved 0)
                pairs (get resolved 1)
                with-quals (mods/subst-qualified flat pairs)
                expanded (macros/expand-program with-quals)
                tc (run-typecheck expanded)]
            (if (!= tc 0)
              (die "error: type check failed" 3)
              (let [oc (run-ownership expanded)]
                (if (!= oc 0)
                  (die "error: ownership check failed" 4)
                  (let [hir-lines (hir/lower-program expanded)
                        _ (llvm/compile-llvm hir-lines output-path)
                        ll-path (str-concat output-path ".ll")
                        cmd (str-concat "clang -Wno-override-module "
                              (str-concat ll-path
                                (str-concat " runtime/bars_runtime.o -lgc -lm -o " output-path)))
                        status (bars_system cmd)]
                    (if (!= status 0)
                      (do (println (str-concat "error: clang failed: " cmd))
                          (println status)
                          2)
                      0)))))))))))

(defn main []
  (let [n (args-count)]
    (if (< n 3)
      (die "Usage: bars-self <input.brs> <output_bin>" 1)
      (compile-file (args-get 1) (args-get 2)))))
