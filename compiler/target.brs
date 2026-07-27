;; Cross-compilation targets (Phase cross / PLAN_CROSS)
;;
;; BARS_TARGET=<triple> or bars-self --target <triple> …
;; Host default from `uname -m` (x86_64 / aarch64 → *-unknown-linux-gnu).
;;
;; Supported:
;;   x86_64-unknown-linux-gnu   (host on amd64)
;;   aarch64-unknown-linux-gnu  (host on arm64, or cross)
;;   wasm32-unknown-unknown     → WASM backend (WAT)

(extern "bars_getenv" [name i64] -> i64)
(extern "bars_file_exists" [path i64] -> i64)
(extern "bars_system" [cmd i64] -> i64)

(defn str-eq? [a b]
  (if (!= (count a) (count b)) false
    (= (str-starts-with? a b) 1)))

(defn starts-with? [s prefix]
  (if (> (count prefix) (count s)) false
    (str-eq? (str-slice s 0 (count prefix)) prefix)))

;; "aarch64-unknown-linux-gnu" → "aarch64_unknown_linux_gnu"
(defn dash-to-underscore [s]
  (let [n (count s)]
    (loop [i 0 acc ""]
      (if (>= i n) acc
        (if (= (str-get s i) 45)
          (recur (+ i 1) (str-concat acc "_"))
          (recur (+ i 1) (str-concat acc (str-slice s i (+ i 1)))))))))

;; "aarch64-unknown-linux-gnu" → "aarch64-linux-gnu" (strip vendor -unknown)
(defn strip-unknown [s]
  (let [idx (str-index-of s "-unknown")]
    (if (< idx 0) s
      (str-concat (str-slice s 0 idx)
        (str-slice s (+ idx 8) (count s))))))

;; uname -m → linux gnu triple
(defn arch-to-triple [arch]
  (if (str-eq? arch "x86_64") "x86_64-unknown-linux-gnu"
    (if (str-eq? arch "amd64") "x86_64-unknown-linux-gnu"
      (if (str-eq? arch "aarch64") "aarch64-unknown-linux-gnu"
        (if (str-eq? arch "arm64") "aarch64-unknown-linux-gnu"
          (if (> (count arch) 0)
            (str-concat arch "-unknown-linux-gnu")
            "x86_64-unknown-linux-gnu"))))))

;; Detect host via uname -m exit status (no stdout capture in runtime yet).
(defn detect-host-arch []
  (if (= (bars_system "uname -m 2>/dev/null | grep -Eq '^(aarch64|arm64)$'") 0)
    "aarch64"
    "x86_64"))

(defn default-host-target []
  (arch-to-triple (detect-host-arch)))

;; Active compile target: BARS_TARGET env, else host default.
(defn current-target []
  (let [t (bars_getenv "BARS_TARGET")]
    (if (= (count t) 0) (default-host-target) t)))

(defn is-host-target? [triple]
  (str-eq? triple (default-host-target)))

(defn is-wasm-target? [triple]
  (if (starts-with? triple "wasm32") true
    (starts-with? triple "wasm64")))

(defn is-aarch64-target? [triple]
  (starts-with? triple "aarch64"))

;; Validate known triples; unknown → still try (linker may fail later).
(defn known-target? [triple]
  (if (is-host-target? triple) true
    (if (is-aarch64-target? triple) true
      (is-wasm-target? triple))))

;; Expected path for a target's runtime .o (may not exist yet).
(defn runtime-obj-expected [triple]
  (if (is-wasm-target? triple) ""
    (if (is-host-target? triple)
      "runtime/bars_runtime.o"
      (str-concat "runtime/bars_runtime_"
        (str-concat (dash-to-underscore triple) ".o")))))

;; Path to bars_runtime*.o for this target (empty string if missing).
(defn runtime-obj-path [triple]
  (if (is-wasm-target? triple)
    ""
    (if (is-host-target? triple)
      (if (= (bars_file_exists "runtime/bars_runtime.o") 1)
        "runtime/bars_runtime.o"
        "")
      (let [full (str-concat "runtime/bars_runtime_"
                    (str-concat (dash-to-underscore triple) ".o"))
            dash (str-index-of triple "-")
            arch (if (< dash 0) triple (str-slice triple 0 dash))
            short (str-concat "runtime/bars_runtime_" (str-concat arch ".o"))]
        (if (= (bars_file_exists full) 1) full
          (if (= (bars_file_exists short) 1) short
            ""))))))

;; Cross C compiler name: aarch64-linux-gnu-gcc, or clang fallback.
(defn cross-cc [triple]
  (if (is-host-target? triple) "clang"
    (if (is-wasm-target? triple) ""
      (let [short (str-concat (strip-unknown triple) "-gcc")
            full (str-concat triple "-gcc")]
        (if (= (bars_system (str-concat "command -v " (str-concat short " >/dev/null 2>&1"))) 0)
          short
          (if (= (bars_system (str-concat "command -v " (str-concat full " >/dev/null 2>&1"))) 0)
            full
            "clang"))))))

;; clang --target= flag value (short linux triple works better with multiarch).
(defn clang-target-flag [triple]
  (if (is-host-target? triple) ""
    (strip-unknown triple)))

;; How to build object from .ll for cross: two-step (clang -c + cross-gcc link).
(defn needs-two-step-link? [triple]
  (if (is-host-target? triple) false
    (if (is-wasm-target? triple) false
      true)))

;; Hint when runtime .o is missing.
(defn runtime-missing-hint [triple]
  (let [us (dash-to-underscore triple)
        cc (cross-cc triple)
        ccn (if (= (count cc) 0) "cc" cc)]
    (str-concat "build runtime: "
      (str-concat ccn
        (str-concat " -O2 -c runtime/bars_runtime.c -o runtime/bars_runtime_"
          (str-concat us ".o"))))))

;; Auto-build runtime .o when missing (host cc or cross-gcc / clang --target).
;; Returns path or "" on failure.
(defn try-build-runtime [triple]
  (if (is-wasm-target? triple) ""
    (if (= (bars_file_exists "runtime/bars_runtime.c") 1)
      (if (is-host-target? triple)
        (let [cmd "cc -O2 -c runtime/bars_runtime.c -o runtime/bars_runtime.o"
              _ (do (println (str-concat "  note: building host runtime…")) 0)
              st (bars_system cmd)]
          (if (= st 0) "runtime/bars_runtime.o" ""))
        (let [out (runtime-obj-expected triple)
              cc (cross-cc triple)
              cmd (if (str-eq? cc "clang")
                    (str-concat "clang --target="
                      (str-concat (clang-target-flag triple)
                        (str-concat " -O2 -c runtime/bars_runtime.c -o " out)))
                    (str-concat cc
                      (str-concat " -O2 -c runtime/bars_runtime.c -o " out)))
              _ (do (println (str-concat "  note: building runtime for "
                              (str-concat triple "…"))) 0)
              st (bars_system cmd)]
          (if (= st 0) out "")))
      "")))

;; Resolve runtime path, building it if needed.
(defn ensure-runtime [triple]
  (let [rt (runtime-obj-path triple)]
    (if (> (count rt) 0) rt
      (try-build-runtime triple))))
