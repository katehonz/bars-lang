;; Stage 4: Self-hosted build pipeline

(require "lib/reader.brs" :as reader)
(require "lib/hir.brs" :as hir)
(require "lib/qbe.brs" :as qbe)

(extern "bars_system" [cmd i64] -> i64)
(extern "slurp" [path i64] -> i64)
(extern "spit" [path i64 content i64] -> i64)

(defn join-lines [lines]
  (loop [i 0 acc ""]
    (if (>= i (count lines))
      acc
      (let [line (get lines i)
            sep (if (= i 0) "" "\n")]
        (recur (+ i 1) (str-concat (str-concat acc sep) line))))))

(defn replace-all [s old new]
  (loop [acc s]
    (let [idx (str-index-of acc old)]
      (if (= idx -1)
        acc
        (let [before (str-slice acc 0 idx)
              after (str-slice acc (+ idx (count old)) (count acc))]
          (recur (str-concat (str-concat before new) after)))))))

(defn fix-runtime-calls [ssa]
  (let [s1 (replace-all ssa "call $println()" "call $bars_print_newline()")]
    (replace-all s1 "call $println(" "call $bars_print_any_i64(")))

(defn compile-file [input-path output-path]
  (let [source (slurp input-path)]
    (let [ast (bars-read source)]
      (let [hir-lines (hir/lower-program ast)]
        (let [ssa-vec (qbe/hir-to-qbe hir-lines)]
          (let [ssa-raw (join-lines ssa-vec)]
            (let [ssa (fix-runtime-calls ssa-raw)]
              (let [ssa-path (str-concat output-path ".ssa")]
                (spit ssa-path ssa)
                (let [asm-path (str-concat output-path ".s")]
                  (let [qbe-cmd (str-concat (str-concat (str-concat "qbe " ssa-path) " -o ") asm-path)]
                    (let [qbe-res (bars_system qbe-cmd)]
                      (if (= qbe-res 0)
                        (let [cc-part1 (str-concat "cc " asm-path)]
                          (let [cc-part2 (str-concat cc-part1 " runtime/bars_runtime.o -lgc -lm -no-pie -o ")]
                            (let [cc-cmd (str-concat cc-part2 output-path)]
                              (let [cc-res (bars_system cc-cmd)]
                                (if (= cc-res 0)
                                  0
                                  (do (println "Link failed") 1))))))
                        (do (println "QBE compilation failed") 1)))))))))))))

(defn main []
  (let [args-count (args-count)]
    (if (< args-count 3)
      (do (println "Usage: build <input.brs> <output_bin>") 1)
      (let [input-path (args-get 1)]
        (let [output-path (args-get 2)]
          (compile-file input-path output-path))))))
