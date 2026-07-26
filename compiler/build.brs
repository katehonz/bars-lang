;; Self-hosted build pipeline — Stage 10d / Phase 13.2
;; reader → modules → macros → types → ownership → HIR → LLVM → clang
;;
;; Exit codes: 0 ok, 1 usage/input/parse, 2 link (clang), 3 typecheck, 4 ownership
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

;; ---- diagnostics (Phase 13.2) ----

(defn die [msg code]
  (do (println msg) code))

(defn err [kind msg]
  (println (str-concat "error: " (str-concat kind (str-concat ": " msg)))))

(defn note [msg]
  (println (str-concat "  note: " msg)))

(defn usage []
  (do (println "Usage: bars-self <input.brs> <output_bin>")
      (println "  Stages: parse → modules → macros → types → ownership → HIR → LLVM → clang")
      (println "  Exit:   0 ok | 1 input/parse | 2 link | 3 types | 4 ownership")
      (println "  Env:    BARS_SKIP_TYPECHECK=1  BARS_SKIP_OWNERSHIP=1  BARS_STRICT_TYPES=1")
      1))

;; Types ON by default (soft warnings). Ownership ON by default (light NLL).
;;   BARS_SKIP_TYPECHECK=1 / BARS_SKIP_OWNERSHIP=1  force off
;;   BARS_STRICT_TYPES=1                            hard-fail type issues
;; Ownership: let-alias of Owned → move; loop rebinds are not moves;
;; Copy ops/lits don't move; real scope pop (vector pop runtime).
(defn skip-typecheck? []
  (= (bars_env_set "BARS_SKIP_TYPECHECK") 1))

(defn skip-ownership? []
  (= (bars_env_set "BARS_SKIP_OWNERSHIP") 1))

(defn strict-types? []
  (= (bars_env_set "BARS_STRICT_TYPES") 1))

;; Load a .brs file to AST. slurp returns 0 if file missing.
;; bars-read returns 0 on parse error.
(defn read-file [path]
  (let [src (slurp path)]
    (if (= src 0)
      (do (err "io" (str-concat "cannot open file `" (str-concat path "`")))
          0)
      (let [ast (reader/bars-read src)]
        (if (= ast 0)
          (do (err "parse" (str-concat "failed in `" (str-concat path "`")))
              0)
          ast)))))

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
                  (do (err "module" (str-concat "failed to load require `" (str-concat path "`")))
                      0)
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

(defn run-typecheck [ast path]
  (if (skip-typecheck?)
    0
    (let [tc (types/type_check ast)]
      (if (= tc 0) 0
        (if (strict-types?)
          (do (err "type" (str-concat "check failed in `" (str-concat path "`")))
              (note "set BARS_SKIP_TYPECHECK=1 to compile anyway")
              tc)
          (do (println (str-concat "warning: type: issues in `" (str-concat path "` (soft; BARS_STRICT_TYPES=1 to fail)")))
              0))))))

(defn run-ownership [ast path]
  (if (skip-ownership?)
    0
    (let [oc (own/check_ownership ast)]
      (if (= oc 0) 0
        (do (err "ownership" (str-concat "check failed in `" (str-concat path "`")))
            (note "use-after-move on Owned values; BARS_SKIP_OWNERSHIP=1 to disable")
            oc)))))

(defn compile-file [input-path output-path]
  (let [raw (read-file input-path)]
    (if (= raw 0)
      1
      (if (= (count raw) 0)
        (do (err "parse" (str-concat "empty program `" (str-concat input-path "`")))
            1)
        (let [resolved (resolve-requires raw)]
          (if (= resolved 0)
            1
            (let [flat (get resolved 0)
                  pairs (get resolved 1)
                  with-quals (mods/subst-qualified flat pairs)
                  expanded (macros/expand-program with-quals)
                  tc (run-typecheck expanded input-path)]
              (if (!= tc 0)
                3
                (let [oc (run-ownership expanded input-path)]
                  (if (!= oc 0)
                    4
                    (let [hir-lines (hir/lower-program expanded)
                          _ (llvm/compile-llvm hir-lines output-path)
                          ll-path (str-concat output-path ".ll")
                          cmd (str-concat "clang -Wno-override-module "
                                (str-concat ll-path
                                  (str-concat " runtime/bars_runtime.o -lgc -lm -o " output-path)))
                          status (bars_system cmd)]
                      (if (!= status 0)
                        (do (err "link" "clang failed while producing binary")
                            (note (str-concat "command: " cmd))
                            (note "check the clang diagnostics above")
                            2)
                        0))))))))))))

(defn main []
  (let [n (args-count)]
    (if (< n 3)
      (usage)
      (compile-file (args-get 1) (args-get 2)))))
