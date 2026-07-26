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
;; Returns AST only (for requires). Main compile uses read-file-pack.
(defn read-file [path]
  (let [pack (read-file-pack path)]
    (if (= pack 0) 0 (get pack 0))))

;; Returns [ast src] or 0. src is kept for ownership line:col mapping.
(defn read-file-pack [path]
  (let [src (slurp path)]
    (if (= src 0)
      (do (err "io" (str-concat "cannot open file `" (str-concat path "`")))
          0)
      (let [ast (reader/bars-read-at src path)]
        (if (= ast 0)
          (do (err "parse" (str-concat "failed in `" (str-concat path "`")))
              0)
          (let [out (vector)]
            (do (push out ast) (push out src) out)))))))

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

(defn str-eq? [a b]
  (if (!= (count a) (count b)) false
    (= (str-starts-with? a b) 1)))

;; Parent directory of a path ("a/b/c.brs" → "a/b", "c.brs" → ".").
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

;; Try opening path; return AST or 0 (silent — caller reports).
(defn try-read [path]
  (let [src (slurp path)]
    (if (= src 0) 0
      (let [ast (reader/bars-read-at src path)]
        (if (= ast 0) 0 ast)))))

;; Search order (host-like): exact, relative to base, lib/<path>.
(defn find-module [base path-raw]
  (let [path (ensure-brs-path path-raw)
        a (try-read path)]
    (if (!= a 0)
      (let [out (vector)] (do (push out a) (push out path) out))
      (let [rel (join-path base path)
            b (try-read rel)]
        (if (!= b 0)
          (let [out (vector)] (do (push out b) (push out rel) out))
          (let [libp (join-path "lib" path)
                c (try-read libp)]
            (if (!= c 0)
              (let [out (vector)] (do (push out c) (push out libp) out))
              0)))))))

(defn path-in? [visited path]
  (let [n (count visited)]
    (loop [i 0]
      (if (>= i n) false
        (if (str-eq? (get visited i) path) true
          (recur (+ i 1)))))))

;; Resolve all requires in an AST (recursive).
;; base = directory of the current file (for relative requires).
;; visited = paths currently/already loading (cycle + single-load).
;; Returns [flat-ast alias-pairs] or 0 on error.
(defn resolve-requires-at [ast base visited]
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
              (let [path-raw (get req 0)
                    alias (get req 1)
                    prefix (mods/module-prefix alias)
                    found (find-module base path-raw)]
                (if (= found 0)
                  (do (err "module" (str-concat "cannot find `" (str-concat path-raw "`")))
                      (note (str-concat "searched from base `" (str-concat base "` and lib/")))
                      0)
                  (let [mod-raw (get found 0)
                        mod-path (get found 1)]
                    (if (path-in? visited mod-path)
                      (do (err "module" (str-concat "circular or duplicate require of `" (str-concat mod-path "`")))
                          (note "each module file is loaded once (host-compatible)")
                          0)
                      (do (push visited mod-path)
                          (let [mod-base (dirname mod-path)
                                mod-resolved (resolve-requires-at mod-raw mod-base visited)]
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
                                    (recur (+ i 1)))))))))))
              (do (push result expr)
                  (recur (+ i 1))))))))))

(defn resolve-requires [ast]
  (resolve-requires-at ast "." (vector)))

;; Resolve from a main file: seed visited with the main path and use its dir as base.
(defn resolve-requires-main [ast main-path]
  (let [visited (vector)
        base (dirname main-path)]
    (do (push visited main-path)
        (resolve-requires-at ast base visited))))

(defn run-typecheck [ast path]
  (if (skip-typecheck?)
    0
    (let [tc (types/type_check_at ast path)]
      (if (= tc 0) 0
        (if (strict-types?)
          (do (err "type" (str-concat "check failed in `" (str-concat path "`")))
              (note "set BARS_SKIP_TYPECHECK=1 to compile anyway")
              tc)
          (do (println (str-concat "warning: type: issues in `" (str-concat path "` (soft; BARS_STRICT_TYPES=1 to fail)")))
              0))))))

(defn run-ownership [ast path text]
  (if (skip-ownership?)
    0
    (let [oc (own/check_ownership_at ast path text)]
      (if (= oc 0) 0
        (do (err "ownership" (str-concat "check failed in `" (str-concat path "`")))
            (note "use-after-move on Owned values; BARS_SKIP_OWNERSHIP=1 to disable")
            oc)))))

(defn compile-file [input-path output-path]
  (let [pack (read-file-pack input-path)]
    (if (= pack 0)
      1
      (let [raw (get pack 0)
            src (get pack 1)]
        (if (= (count raw) 0)
          (do (err "parse" (str-concat "empty program `" (str-concat input-path "`")))
              1)
          (let [resolved (resolve-requires-main raw input-path)]
            (if (= resolved 0)
              1
              (let [flat (get resolved 0)
                    pairs (get resolved 1)
                    with-quals (mods/subst-qualified flat pairs)
                    expanded (macros/expand-program with-quals)
                    tc (run-typecheck expanded input-path)]
                (if (!= tc 0)
                  3
                  (let [oc (run-ownership expanded input-path src)]
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
                          0)))))))))))))

(defn main []
  (let [n (args-count)]
    (if (< n 3)
      (usage)
      (compile-file (args-get 1) (args-get 2)))))
