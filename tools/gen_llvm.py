#!/usr/bin/env python3
"""Generate Bars LLVM backend code with guaranteed paren balance.

Usage: python3 gen_llvm.py > compiler/codegen/llvm.brs
"""

class BarsWriter:
    def __init__(self):
        self.lines = []
    def emit(self, text):
        self.lines.append(text)
    def write(self):
        return "\n".join(self.lines) + "\n"

w = BarsWriter()

def emit_defn(name, params, body):
    w.emit(f"(defn {name} {params}")
    for line in body:
        w.emit(f"  {line}")
    net = sum(line.count('(') - line.count(')') for line in body)
    if net > 0:
        w.emit("  " + ")" * net)
    w.emit(")")
    w.emit("")

# ===========================================================================
# Header
# ===========================================================================
w.emit(";; Bars LLVM Backend — Stage 7 of self-hosting")
w.emit(";; HIR → LLVM IR (human-readable .ll format)")
w.emit("")

# ===========================================================================
# String helpers
# ===========================================================================
emit_defn("str-starts-with?", "[s prefix]",
    ["(if (< (count s) (count prefix)) false"
    ,"  (loop [i 0]"
    ,"    (if (>= i (count prefix)) true"
    ,"      (if (= (str-get s i) (str-get prefix i))"
    ,"        (recur (+ i 1))"
    ,"        false))))"])

emit_defn("str-contains?", "[s sub]",
    ["(if (= (str-index-of s sub) -1) false true)"])

# ===========================================================================
# LLVM IR Generator
# ===========================================================================

emit_defn("llvm-header", "[]",
    ["(let [lines (vector)]"
    ,"  (do (push lines \"target triple = \\\"x86_64-unknown-linux-gnu\\\"\")"
    ,"      (push lines \"\")"
    ,"      (push lines \"declare i64 @bars_print_any_i64(i64)\")"
    ,"      (push lines \"declare i64 @bars_print_newline()\")"
    ,"      (push lines \"declare i64 @bars_vec_new()\")"
    ,"      (push lines \"declare i64 @bars_vec_push(i64, i64)\")"
    ,"      (push lines \"declare i64 @bars_vec_get(i64, i64)\")"
    ,"      (push lines \"declare i64 @bars_vec_count(i64)\")"
    ,"      (push lines \"declare i64 @bars_str_new(i64)\")"
    ,"      (push lines \"declare i64 @bars_str_concat(i64, i64)\")"
    ,"      (push lines \"declare i64 @bars_str_get(i64, i64)\")"
    ,"      (push lines \"declare i64 @bars_str_count(i64)\")"
    ,"      (push lines \"declare i64 @bars_str_slice(i64, i64, i64)\")"
    ,"      (push lines \"declare i64 @bars_str_index_of(i64, i64)\")"
    ,"      (push lines \"declare i64 @bars_str_starts_with(i64, i64)\")"
    ,"      (push lines \"declare i64 @bars_str_ends_with(i64, i64)\")"
    ,"      (push lines \"declare i64 @bars_system(i64)\")"
    ,"      (push lines \"declare i64 @bars_slurp(i64)\")"
    ,"      (push lines \"declare i64 @bars_spit(i64, i64)\")"
    ,"      (push lines \"declare i64 @bars_args_count()\")"
    ,"      (push lines \"declare i64 @bars_args_get(i64)\")"
    ,"      (push lines \"declare i64 @bars_exit(i64)\")"
    ,"      (push lines \"declare i64 @floor(i64)\")"
    ,"      (push lines \"\")"
    ,"      lines))"])

# ===========================================================================
# Parse HIR line into op and args
# ===========================================================================
emit_defn("parse-hir-line", "[line]",
    ["(cond"
    ,"  (str-contains? line \"Assign\")"
    ,"    (let [dest-start (+ (str-index-of line \"dest:\") 6)"
    ,"          dest-end (str-index-of line \",\")"
    ,"          dest (str-slice line dest-start (- dest-end 2))]"
    ,"      (let [val-start (+ (str-index-of line \"value:\") 7)"
    ,"            val (str-slice line val-start (count line))]"
    ,"        (let [v (vector)] (do (push v \"assign\") (do (push v dest) (do (push v val) v))))))"
    ,"  (str-contains? line \"Call\")"
    ,"    (let [dest-start (+ (str-index-of line \"dest:\") 6)"
    ,"          dest-end (str-index-of line \",\")"
    ,"          dest (str-slice line dest-start (- dest-end 2))"
    ,"          func-start (+ (str-index-of line \"func:\") 6)"
    ,"          func-end (str-index-of line \",\" (+ func-start 1))"
    ,"          func (str-slice line func-start (- func-end 2))]"
    ,"      (let [v (vector)] (do (push v \"call\") (do (push v dest) (do (push v func) v)))))"
    ,"  (str-contains? line \"Return\")"
    ,"    (let [val-start (+ (str-index-of line \"Return(\") 7)"
    ,"          val (str-slice line val-start (- (count line) 1))]"
    ,"      (let [v (vector)] (do (push v \"return\") (do (push v val) v))))"
    ,"  (str-contains? line \"Branch\")"
    ,"    (let [cond-start (+ (str-index-of line \"branch\") 7)"
    ,"          v (vector)]"
    ,"      (do (push v \"branch\") (do (push v line) v)))"
    ,"  :else"
    ,"    (let [v (vector)] (do (push v \"unknown\") v)))"])

# ===========================================================================
# Convert Operand to LLVM format
# ===========================================================================
emit_defn("op-to-llvm", "[op]",
    ["(if (str-contains? op \"Const(\")"
    ,"  (let [start (+ (str-index-of op \"Const(\") 6)"
    ,"        end (str-index-of op \")\")]"
    ,"    (str-slice op start end))"
    ,"  (if (str-contains? op \"Var(\")"
    ,"    (let [start (+ (str-index-of op \"Var(\") 5)"
    ,"          end (str-index-of op \")\")]"
    ,"      (str-concat \"%\" (str-slice op start (- end 1))))"
    ,"    op))"])

# ===========================================================================
# Process HIR lines → LLVM IR
# ===========================================================================
emit_defn("hir-to-llvm", "[hir-lines]",
    ["(let [output (llvm-header)"
    ,"      n (count hir-lines)]"
    ,"  (do (loop [i 0]"
    ,"        (if (>= i n) 0"
    ,"          (let [line (get hir-lines i)]"
    ,"            (if (str-starts-with? line \"func\")"
    ,"              (let [name-start (+ (str-index-of line \"func \") 5)"
    ,"                    name-end (str-index-of line \":\")"
    ,"                    func-name (str-slice line name-start name-end)]"
    ,"                (do (push output (str-concat \"define i64 @\" (str-concat func-name \"() {\")))"
    ,"                    (push output \"entry:\")"
    ,"                    (recur (+ i 1)))))"
    ,"              (if (str-starts-with? line \"    Assign\")"
    ,"                (let [parsed (parse-hir-line line)"
    ,"                      dest (get parsed 1)"
    ,"                      val (get parsed 2)"
    ,"                      llvm-val (op-to-llvm val)]"
    ,"                  (do (push output (str-concat \"  %\" (str-concat dest (str-concat \" = \" (str-concat llvm-val \" i64\")))))"
    ,"                      (recur (+ i 1)))))"
    ,"                (if (str-starts-with? line \"    Call\")"
    ,"                  (let [parsed (parse-hir-line line)"
    ,"                        dest (get parsed 1)"
    ,"                        func (get parsed 2)]"
    ,"                    (do (push output (str-concat \"  %\" (str-concat dest (str-concat \" = call i64 @\" (str-concat func \"()\")))))"
    ,"                        (recur (+ i 1)))))"
    ,"                  (if (str-starts-with? line \"    Return\")"
    ,"                    (let [parsed (parse-hir-line line)"
    ,"                          val (get parsed 1)"
    ,"                          llvm-val (op-to-llvm val)]"
    ,"                      (do (push output (str-concat \"  ret i64 \" llvm-val))"
    ,"                          (push output \"}\")"
    ,"                          (push output \"\")"
    ,"                          (recur (+ i 1)))))"
    ,"                    (if (str-starts-with? line \"    branch\")"
    ,"                      (let [cond-start (+ (str-index-of line \"branch \") 7)"
    ,"                            parts (str-slice line cond-start (count line))]"
    ,"                        (do (push output (str-concat \"  br i1 \" parts))"
    ,"                            (recur (+ i 1)))))"
    ,"                      (recur (+ i 1)))))))))"
    ,"      output))"])

# ===========================================================================
# Build pipeline: HIR -> LLVM IR -> llc -> cc -> binary
# ===========================================================================
emit_defn("compile-to-llvm", "[hir-lines output-path]",
    ["(let [ll-lines (hir-to-llvm hir-lines)"
    ,"      n (count ll-lines)]"
    ,"  (loop [i 0 ll-text \"\"]"
    ,"    (if (>= i n)"
    ,"      (let [ll-path (str-concat output-path \".ll\")]"
    ,"        (do (spit ll-path ll-text)"
    ,"            (println \"LLVM IR written to\" ll-path)"
    ,"            0))"
    ,"      (let [line (get ll-lines i)]"
    ,"        (recur (+ i 1) (str-concat (str-concat ll-text line) \"\\n\"))))))"])

print(w.write())
