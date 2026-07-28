;; Self-hosted build pipeline — Stage 10d / Phase 13.2–13.4 / 14.2
;; reader → modules → macros → types → ownership → HIR → LLVM|C → link
;;
;; Exit codes: 0 ok, 1 usage/input/parse, 2 link (clang), 3 typecheck, 4 ownership
;; Skip: BARS_SKIP_TYPECHECK / BARS_SKIP_OWNERSHIP (non-empty env)
;; Incremental: skip link if output newer than all loaded sources (BARS_FORCE=1 to rebuild)
;; Watch: bars-self watch <in.brs> <out>
;; Debug/profile: BARS_DEBUG=1 (DWARF), BARS_PROFILE=1 (-pg), BARS_TIMINGS=1 (stage ms)

(require "compiler/reader.brs" :as reader)
(require "compiler/modules.brs" :as mods)
(require "compiler/macros.brs" :as macros)
(require "compiler/types.brs" :as types)
(require "compiler/ownership.brs" :as own)
(require "compiler/hir.brs" :as hir)
(require "compiler/codegen/llvm.brs" :as llvm)
(require "compiler/codegen/c.brs" :as cgen)
(require "compiler/codegen/wasm.brs" :as wasm)
(require "compiler/pkg.brs" :as pkg)
(require "compiler/fmt.brs" :as fmt)
(require "compiler/lint.brs" :as lint)
(require "compiler/doc.brs" :as doc)
(require "compiler/target.brs" :as tgt)

(extern "slurp" [path i64] -> i64)
(extern "spit" [path i64 content i64] -> i64)
(extern "bars_system" [cmd i64] -> i64)
(extern "bars_env_is_set" [name i64] -> i64)
(extern "bars_file_mtime" [path i64] -> i64)
(extern "bars_sleep_ms" [ms i64] -> i64)
(extern "bars_getenv" [name i64] -> i64)
(extern "bars_time_ms" [] -> i64)

;; ---- diagnostics (Phase 13.2) ----

(defn die [msg code]
  (do (println msg) code))

(defn err [kind msg]
  (println (str-concat "error: " (str-concat kind (str-concat ": " msg)))))

(defn note [msg]
  (println (str-concat "  note: " msg)))

(defn usage []
  (do (println "Usage: bars-self <input.brs> <output_bin>")
      (println "       bars-self --target <triple> <input.brs> <output_bin>")
      (println "       bars-self check <input.brs>")
      (println "       bars-self watch <input.brs> <output_bin>")
      (println "       bars-self fmt  <input.brs> [--write]")
      (println "       bars-self lint <input.brs>")
      (println "       bars-self doc  <input.brs> [output.md]")
      (println "       bars-self new  <name> [--bin]")
      (println "       bars-self publish [package-dir]")
      (println "       bars-self install <name> [version]")
      (println "       bars-self search [query]")
      (println "  Stages: parse → modules → macros → types → ownership → HIR → backend → link")
      (println "  Exit:   0 ok | 1 input/parse | 2 link | 3 types | 4 ownership | 5 lint")
      (println "  Env:    BARS_SKIP_TYPECHECK=1  BARS_SKIP_OWNERSHIP=1  BARS_STRICT_TYPES=1")
      (println "          BARS_BACKEND=llvm|c|wasm  (default llvm)")
      (println "          BARS_BACKEND_C=1 / BARS_BACKEND_WASM=1")
      (println "          BARS_TARGET=triple    cross target (or --target)")
      (println "            host from uname -m; aarch64 / wasm32 also supported")
      (println "          BARS_FORCE=1          rebuild even if up to date")
      (println "          BARS_NO_INCREMENTAL=1 always recompile")
      (println "          BARS_REGISTRY=path    local package registry (default ~/.bars/registry)")
      (println "          BARS_DEBUG=1          DWARF (-g -O0); gdb/lldb ready")
      (println "          BARS_PROFILE=1        gprof (-pg -g); use gprof/perf")
      (println "          BARS_TIMINGS=1        print compile-stage milliseconds")
      (println "          BARS_RELEASE=1        optimize link (-O2)")
      1))

;; Types ON by default (soft warnings). Ownership ON by default (light NLL).
;;   BARS_SKIP_TYPECHECK=1 / BARS_SKIP_OWNERSHIP=1  force off
;;   BARS_STRICT_TYPES=1                            hard-fail type issues
;; Ownership: let-alias of Owned → move; loop rebinds are not moves;
;; Copy ops/lits don't move; real scope pop (vector pop runtime).
(defn skip-typecheck? []
  (= (bars_env_is_set "BARS_SKIP_TYPECHECK") 1))

(defn skip-ownership? []
  (= (bars_env_is_set "BARS_SKIP_OWNERSHIP") 1))

(defn strict-types? []
  (= (bars_env_is_set "BARS_STRICT_TYPES") 1))

(defn force-rebuild? []
  (if (= (bars_env_is_set "BARS_FORCE") 1) true
    (= (bars_env_is_set "BARS_NO_INCREMENTAL") 1)))

;; Phase 14.2 tooling: debugger / profiler / compile timings / release
(defn debug-mode? []
  (= (bars_env_is_set "BARS_DEBUG") 1))

(defn profile-mode? []
  (= (bars_env_is_set "BARS_PROFILE") 1))

(defn timings-mode? []
  (= (bars_env_is_set "BARS_TIMINGS") 1))

(defn release-mode? []
  (= (bars_env_is_set "BARS_RELEASE") 1))

;; clang/cc flags: profile > debug > release > default
(defn link-opt-flags []
  (if (profile-mode?) "-pg -g -O0 "
    (if (debug-mode?) "-g -O0 "
      (if (release-mode?) "-O2 "
        ""))))

(defn timing-note [label start-ms]
  (if (timings-mode?)
    (let [ms (- (bars_time_ms) start-ms)]
      (note (str-concat "timing: " (str-concat label
              (str-concat " " (str-concat (int-str? ms) "ms"))))))
    0))

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

;; dirname / join-path live in pkg.brs (pkg/dirname, pkg/join-path).

;; Try opening path; return AST or 0 (silent — caller reports).
(defn try-read [path]
  (let [src (slurp path)]
    (if (= src 0) 0
      (let [ast (reader/bars-read-at src path)]
        (if (= ast 0) 0 ast)))))

;; Pack found module as [ast path] or 0.
(defn found [ast path]
  (let [out (vector)]
    (do (push out ast) (push out path) out)))

;; Search package path-deps: name → src/lib.brs, or dep/src/<path>.
(defn find-in-deps [deps path-raw]
  (let [bare (pkg/strip-brs path-raw)
        root (pkg/dep-root-by-name deps bare)]
    (if (> (count root) 0)
      (let [lib1 (pkg/join-path root "src/lib.brs")
            a (try-read lib1)]
        (if (!= a 0) (found a lib1)
          (let [lib2 (pkg/join-path root "src/main.brs")
                b (try-read lib2)]
            (if (!= b 0) (found b lib2) 0))))
      ;; Search each dep's src/ for the path
      (let [n (count deps)
            path (ensure-brs-path path-raw)]
        (loop [i 0]
          (if (>= i n) 0
            (let [droot (get (get deps i) 1)
                  cand (pkg/join-path (pkg/join-path droot "src") path)
                  c (try-read cand)]
              (if (!= c 0) (found c cand)
                (recur (+ i 1))))))))))

;; Search order: exact, relative to base, lib/, Bars.toml path-deps, bars-deps.
(defn find-module [base path-raw deps]
  (let [path (ensure-brs-path path-raw)
        a (try-read path)]
    (if (!= a 0) (found a path)
      (let [rel (pkg/join-path base path)
            b (try-read rel)]
        (if (!= b 0) (found b rel)
          (let [libp (pkg/join-path "lib" path)
                c (try-read libp)]
            (if (!= c 0) (found c libp)
              (let [d (find-in-deps deps path-raw)]
                (if (!= d 0) d
                  ;; target/bars-deps/<name>/src/lib.brs (host clone layout)
                  (let [bare (pkg/strip-brs path-raw)
                        dep-lib (pkg/join-path (pkg/join-path (pkg/join-path "target/bars-deps" bare) "src") "lib.brs")
                        e (try-read dep-lib)]
                    (if (!= e 0) (found e dep-lib) 0)))))))))))

(defn path-in? [visited path]
  (let [n (count visited)]
    (loop [i 0]
      (if (>= i n) false
        (if (str-eq? (get visited i) path) true
          (recur (+ i 1)))))))

;; Resolve all requires in an AST (recursive).
;; base = directory of the current file (for relative requires).
;; visited = paths currently/already loading (cycle + single-load).
;; deps = Bars.toml path-deps [[name root] ...]
;; Returns [flat-ast alias-pairs] or 0 on error.
(defn resolve-requires-at [ast base visited deps]
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
                    found (find-module base path-raw deps)]
                (if (= found 0)
                  (do (err "module" (str-concat "cannot find `" (str-concat path-raw "`")))
                      (note (str-concat "searched base `" (str-concat base "`, lib/, Bars.toml path-deps")))
                      0)
                  (let [mod-raw (get found 0)
                        mod-path (get found 1)]
                    (if (path-in? visited mod-path)
                      (do (err "module" (str-concat "circular or duplicate require of `" (str-concat mod-path "`")))
                          (note "each module file is loaded once (host-compatible)")
                          0)
                      (do (push visited mod-path)
                          (let [mod-base (pkg/dirname mod-path)
                                mod-resolved (resolve-requires-at mod-raw mod-base visited deps)]
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
  (resolve-requires-at ast "." (vector) (vector)))

;; Resolve from a main file: seed visited, load Bars.toml path-deps, use dirname base.
;; Returns [flat-ast alias-pairs source-paths] or 0.
;; source-paths = main + all required modules (for incremental mtime checks).
(defn resolve-requires-main [ast main-path]
  (let [visited (vector)
        base (pkg/dirname main-path)
        proj (pkg/find-manifest-dir base)
        deps (if (= (count proj) 0) (vector) (pkg/load-path-deps proj))]
    (do (push visited main-path)
        (if (> (count proj) 0)
          (push visited (pkg/join-path proj "Bars.toml"))
          0)
        (if (> (count deps) 0)
          (println (str-concat "  note: Bars.toml path-deps from `" (str-concat proj "`")))
          0)
        (let [resolved (resolve-requires-at ast base visited deps)]
          (if (= resolved 0) 0
            (let [out (vector)]
              (do (push out (get resolved 0))
                  (push out (get resolved 1))
                  (push out visited)
                  out)))))))

;; ---- incremental (Phase 13.3) ----

(defn max-mtime [paths]
  (let [n (count paths)]
    (loop [i 0 m 0]
      (if (>= i n) m
        (let [t (bars_file_mtime (get paths i))]
          (recur (+ i 1) (if (> t m) t m)))))))

;; True when output exists and is at least as new as every loaded source.
(defn up-to-date? [sources output-path]
  (let [out-m (bars_file_mtime output-path)]
    (if (= out-m 0) false
      (>= out-m (max-mtime sources)))))

(defn run-typecheck [ast path text]
  (if (skip-typecheck?)
    0
    (let [tc (types/type_check_at ast path text)]
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

;; Backend: llvm (default), c, or experimental wasm/wat.
(defn use-c-backend? []
  (= (bars_env_is_set "BARS_BACKEND_C") 1))

(defn use-wasm-backend? [triple]
  (if (= (bars_env_is_set "BARS_BACKEND_WASM") 1) true
    (tgt/is-wasm-target? triple)))

(defn link-notes [output-path]
  (do (if (debug-mode?)
        (note (str-concat "debug: `" (str-concat output-path "` (gdb/lldb; break _bars_main)")))
        0)
      (if (profile-mode?)
        (note (str-concat "profile: run binary then `gprof " (str-concat output-path " gmon.out`")))
        0)
      0))

;; Host: single clang link of .ll + runtime.
(defn link-llvm-host [output-path ll-path rt opts]
  (let [cmd (str-concat "clang -Wno-override-module "
              (str-concat opts
                (str-concat ll-path
                  (str-concat " " (str-concat rt
                    (str-concat " -lgc -lm -o " output-path))))))
        status (bars_system cmd)]
    (if (!= status 0)
      (do (err "link" "clang failed (LLVM backend)")
          (note (str-concat "command: " cmd))
          2)
      (do (link-notes output-path) 0))))

;; Cross: clang --target -c .ll → .o, then cross-gcc link with runtime.
(defn link-llvm-cross [output-path ll-path rt triple opts]
  (let [obj (str-concat output-path ".o")
        ct (tgt/clang-target-flag triple)
        cc (tgt/cross-cc triple)
        c1 (str-concat "clang --target="
              (str-concat ct
                (str-concat " -Wno-override-module -c "
                  (str-concat ll-path (str-concat " -o " obj)))))
        c2 (str-concat cc
              (str-concat " "
                (str-concat opts
                  (str-concat obj
                    (str-concat " " (str-concat rt
                      (str-concat " -lgc -lm -o " output-path)))))))
        s1 (bars_system c1)]
    (if (!= s1 0)
      (do (err "link" "clang -c failed (cross LLVM)")
          (note (str-concat "command: " c1))
          2)
      (let [s2 (bars_system c2)]
        (if (!= s2 0)
          (do (err "link" (str-concat "cross link failed (`" (str-concat cc "`)")))
              (note (str-concat "command: " c2))
              (note (str-concat "target: " triple))
              2)
          (do (note (str-concat "target: " (str-concat triple
                        (str-concat " via " cc))))
              (link-notes output-path)
              0))))))

(defn link-llvm [output-path triple]
  (let [ll-path (str-concat output-path ".ll")
        opts (link-opt-flags)
        rt (tgt/ensure-runtime triple)]
    (if (= (count rt) 0)
      (do (err "link" (str-concat "runtime object missing for `" (str-concat triple "`")))
          (note (tgt/runtime-missing-hint triple))
          (note "or: make runtime / make runtime-aarch64")
          2)
      (if (tgt/needs-two-step-link? triple)
        (link-llvm-cross output-path ll-path rt triple opts)
        (link-llvm-host output-path ll-path rt opts)))))

(defn link-c [output-path triple]
  (let [c-path (str-concat output-path ".c")
        opts (if (if (profile-mode?) true (debug-mode?))
               (link-opt-flags)
               "-O2 ")
        rt (tgt/ensure-runtime triple)
        cc (if (tgt/is-host-target? triple) "cc" (tgt/cross-cc triple))]
    (if (= (count rt) 0)
      (do (err "link" (str-concat "runtime object missing for `" (str-concat triple "`")))
          (note (tgt/runtime-missing-hint triple))
          2)
      (let [cmd (str-concat cc
                  (str-concat " -I. "
                    (str-concat opts
                      (str-concat c-path
                        (str-concat " " (str-concat rt
                          (str-concat " -lgc -lm -o " output-path)))))))
            status (bars_system cmd)]
        (if (!= status 0)
          (do (err "link" (str-concat cc " failed (C backend)"))
              (note (str-concat "command: " cmd))
              (note "check the C compiler diagnostics above")
              2)
          (do (if (tgt/is-host-target? triple) 0
                (note (str-concat "target: " (str-concat triple (str-concat " via " cc)))))
              0))))))

;; WASM: emit .wat only (no link). Optional wat2wasm if present.
(defn link-wasm [output-path]
  (let [wat (str-concat output-path ".wat")
        wasm-out (str-concat output-path ".wasm")
        has-w2w (= (bars_system "command -v wat2wasm >/dev/null 2>&1") 0)
        has-tools (= (bars_system "command -v wasm-tools >/dev/null 2>&1") 0)]
    (if has-w2w
      (let [st (bars_system (str-concat "wat2wasm " (str-concat wat (str-concat " -o " wasm-out))))]
        (if (!= st 0)
          (do (err "link" "wat2wasm failed")
              (note (str-concat "wat: " wat))
              2)
          (do (note (str-concat "wrote `" (str-concat wasm-out "`")))
              0)))
      (if has-tools
        (let [st (bars_system (str-concat "wasm-tools parse " (str-concat wat (str-concat " -o " wasm-out))))]
          (if (!= st 0)
            (do (err "link" "wasm-tools parse failed") 2)
            (do (note (str-concat "wrote `" (str-concat wasm-out "`")))
                0)))
        (do (note (str-concat "wrote `" (str-concat wat "` (install wasm-tools/wat2wasm for .wasm)")))
            ;; Launcher stub: prefer wasmtime on .wat when no .wasm
            (spit output-path
              (str-concat "#!/bin/sh\n"
                (str-concat "exec wasmtime --invoke main \""
                  (str-concat wat "\" \"$@\"\n"))))
            (bars_system (str-concat "chmod +x " output-path))
            0)))))

(defn emit-and-link [hir-lines output-path source-path triple]
  (let [t0 (bars_time_ms)]
    (if (use-wasm-backend? triple)
      (do (note "backend: wasm (WAT)")
          (note (str-concat "target: " triple))
          (wasm/compile-wasm hir-lines output-path)
          (let [code (link-wasm output-path)]
            (do (timing-note "codegen+link" t0) code)))
      (if (use-c-backend?)
        (do (note "backend: c")
            (cgen/compile-c hir-lines output-path)
            (let [code (link-c output-path triple)]
              (do (timing-note "codegen+link" t0) code)))
        (do (llvm/compile-llvm-target hir-lines output-path source-path triple)
            (let [code (link-llvm output-path triple)]
              (do (timing-note "codegen+link" t0) code)))))))

(defn compile-file [input-path output-path]
  (compile-file-at input-path output-path (tgt/current-target)))

(defn compile-file-at [input-path output-path triple]
  (let [t-all (bars_time_ms)
        pack (read-file-pack input-path)]
    (if (= pack 0)
      1
      (let [raw (get pack 0)
            src (get pack 1)]
        (if (= (count raw) 0)
          (do (err "parse" (str-concat "empty program `" (str-concat input-path "`")))
              1)
          (let [t0 (bars_time_ms)
                resolved (resolve-requires-main raw input-path)]
            (do (timing-note "parse+modules" t0)
                (if (= resolved 0)
                  1
                  (let [flat (get resolved 0)
                        pairs (get resolved 1)
                        sources (get resolved 2)]
                    (if (if (force-rebuild?) false (up-to-date? sources output-path))
                      (do (note (str-concat "up to date: `" (str-concat output-path "`")))
                          0)
                      (let [t1 (bars_time_ms)
                            with-quals (mods/subst-qualified flat pairs)
                            expanded (macros/expand-program with-quals)
                            _m (timing-note "macros" t1)
                            t2 (bars_time_ms)
                            tc (run-typecheck expanded input-path src)
                            _t (timing-note "types" t2)]
                        (if (!= tc 0)
                          3
                          (let [t3 (bars_time_ms)
                                oc (run-ownership expanded input-path src)
                                _o (timing-note "ownership" t3)]
                            (if (!= oc 0)
                              4
                              (let [t4 (bars_time_ms)
                                    hir-lines (hir/lower-program expanded)
                                    _h (timing-note "hir" t4)
                                    code (emit-and-link hir-lines output-path input-path triple)]
                                (do (timing-note "total" t-all) code))))))))))))))))

;; ---- watch (Phase 13.4) ----
;; Poll source mtimes; recompile when any source is newer than the binary.
;; Interval fixed at 500ms (no getenv value API yet).

;; int to string for watch status / diagnostics
(defn int-str? [n] (str-from-i64 n))

;; Poll source mtimes; recompile when any loaded source is newer than last attempt.
;; On failure, wait for the next source change (no spam every tick).
(defn watch-mode [input-path output-path]
  (do (println (str-concat "watch: `" (str-concat input-path
                (str-concat "` → `" (str-concat output-path "` (Ctrl+C to stop)")))))
      (loop [last-src 0]
        (let [pack (read-file-pack input-path)]
          (if (= pack 0)
            (do (note "waiting for input file…")
                (bars_sleep_ms 500)
                (recur last-src))
            (let [raw (get pack 0)
                  resolved (resolve-requires-main raw input-path)]
              (if (= resolved 0)
                (do (bars_sleep_ms 500)
                    (recur last-src))
                (let [sources (get resolved 2)
                      src-m (max-mtime sources)
                      out-m (bars_file_mtime output-path)
                      changed (if (= last-src 0) true (> src-m last-src))
                      stale (if (= out-m 0) true (> src-m out-m))
                      need (if changed true stale)]
                  (if need
                    (do (println (str-concat "watch: compiling `" (str-concat input-path "`…")))
                        (let [code (compile-file input-path output-path)]
                          (if (= code 0)
                            (println "watch: ok")
                            (println (str-concat "watch: failed (exit "
                                      (str-concat (int-str? code) ")"))))
                          (bars_sleep_ms 500)
                          (recur src-m)))
                    (do (bars_sleep_ms 500)
                        (recur last-src)))))))))))

;; ---- tooling (Phase 14.2) ----

(defn tool-read [path]
  (let [src (slurp path)]
    (if (= src 0)
      (do (err "io" (str-concat "cannot open `" (str-concat path "`")))
          0)
      (let [ast (reader/bars-read-at src path)]
        (if (= ast 0)
          (do (err "parse" (str-concat "failed in `" (str-concat path "`")))
              0)
          (let [out (vector)]
            (do (push out src) (push out ast) out)))))))

(defn cmd-fmt [path write?]
  (let [pack (tool-read path)]
    (if (= pack 0) 1
      (let [src (get pack 0)
            ast (get pack 1)
            out (fmt/format-ast ast)]
        (if write?
          (do (spit path out)
              (note (str-concat "formatted `" (str-concat path "`")))
              0)
          (do (println out) 0))))))

(defn cmd-lint [path]
  (let [pack (tool-read path)]
    (if (= pack 0) 1
      (let [src (get pack 0)
            ast (get pack 1)
            n (lint/lint-all path src ast)]
        (if (= n 0)
          (do (note (str-concat "lint clean: `" (str-concat path "`")))
              0)
          (do (err "lint" (str-concat (int-str? n) " issue(s)"))
              5))))))

(defn cmd-doc [path out-path]
  (let [pack (tool-read path)]
    (if (= pack 0) 1
      (let [src (get pack 0)
            ast (get pack 1)
            md (doc/generate path src ast)]
        (if (= (count out-path) 0)
          (do (println md) 0)
          (do (spit out-path md)
              (note (str-concat "wrote `" (str-concat out-path "`")))
              0))))))

(defn has-flag-arg? [flag]
  (let [n (args-count)]
    (loop [i 2]
      (if (>= i n) false
        (if (str-eq? (args-get i) flag) true
          (recur (+ i 1)))))))

;; ---- ecosystem (Phase 14.3) ----

(defn cmd-new [name]
  (let [kind (if (has-flag-arg? "--bin") "bin" "lib")]
    (pkg/new-package name kind)))

(defn cmd-publish [dir]
  (let [d (if (= (count dir) 0) "." dir)
        reg (pkg/default-registry)
        dest (pkg/publish-package d reg)]
    (if (= (count dest) 0) 1 0)))

(defn cmd-install [name version]
  (let [reg (pkg/default-registry)
        dest (pkg/install-from-registry "." reg name version)]
    (if (= (count dest) 0) 1 0)))

(defn cmd-search [query]
  (let [reg (pkg/default-registry)
        entries (pkg/index-list reg)
        n (count entries)]
    (do (println (str-concat "registry: " reg))
        (if (= n 0)
          (do (note "empty registry (publish a package first)") 0)
          (loop [i 0 shown 0]
            (if (>= i n)
              (if (= shown 0)
                (do (note "no matches") 0)
                0)
              (let [e (get entries i)
                    nm (get e 0)
                    ver (get e 1)
                    ok (if (= (count query) 0) true
                         (>= (str-index-of nm query) 0))]
                (if ok
                  (do (println (str-concat nm (str-concat " " ver)))
                      (recur (+ i 1) (+ shown 1)))
                  (recur (+ i 1) shown)))))))))

;; Phase 14.6: check = parse → modules → macros → types → ownership (no codegen).
(defn cmd-check [path]
  (let [pack (read-file-pack path)]
    (if (= pack 0)
      1
      (let [raw (get pack 0)
            src (get pack 1)]
        (if (= (count raw) 0)
          (do (err "parse" (str-concat "empty program `" (str-concat path "`")))
              1)
          (let [resolved (resolve-requires-main raw path)]
            (if (= resolved 0)
              1
              (let [flat (get resolved 0)
                    pairs (get resolved 1)
                    with-quals (mods/subst-qualified flat pairs)
                    expanded (macros/expand-program with-quals)
                    tc (run-typecheck expanded path src)]
                (if (!= tc 0)
                  3
                  (let [oc (run-ownership expanded path src)]
                    (if (!= oc 0)
                      4
                      (do (note (str-concat "check ok: `" (str-concat path "`")))
                          0))))))))))))

(defn main []
  (let [n (args-count)]
    (if (< n 2)
      (usage)
      (let [a1 (args-get 1)]
        (if (str-eq? a1 "watch")
          (if (< n 4) (usage) (watch-mode (args-get 2) (args-get 3)))
          (if (str-eq? a1 "fmt")
            (if (< n 3) (usage)
              (cmd-fmt (args-get 2) (has-flag-arg? "--write")))
            (if (str-eq? a1 "lint")
              (if (< n 3) (usage) (cmd-lint (args-get 2)))
              (if (str-eq? a1 "doc")
                (if (< n 3) (usage)
                  (cmd-doc (args-get 2)
                    (if (>= n 4) (args-get 3) "")))
                (if (str-eq? a1 "check")
                  (if (< n 3) (usage) (cmd-check (args-get 2)))
                  (if (str-eq? a1 "new")
                    (if (< n 3) (usage) (cmd-new (args-get 2)))
                    (if (str-eq? a1 "publish")
                      (cmd-publish (if (>= n 3) (args-get 2) ""))
                      (if (str-eq? a1 "install")
                        (if (< n 3) (usage)
                          (cmd-install (args-get 2)
                            (if (>= n 4) (args-get 3) "")))
                        (if (str-eq? a1 "search")
                          (cmd-search (if (>= n 3) (args-get 2) ""))
                          (if (str-eq? a1 "--target")
                            (if (< n 5) (usage)
                              (compile-file-at (args-get 3) (args-get 4) (args-get 2)))
                            (if (< n 3)
                              (usage)
                              (compile-file a1 (args-get 2)))))))))))))))))
