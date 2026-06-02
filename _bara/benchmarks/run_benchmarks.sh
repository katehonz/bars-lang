#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "  Bara Lang vs JVM Clojure — Benchmarks"
echo "=============================================="
echo ""

run_bench() {
  local name="$1"
  local file="$2"
  local runs="$3"
  
  echo "--- $name ---"
  echo ""
  
  # Bara Lang
  echo "  [Bara Lang]"
  local nim_total=0
  local nim_times=()
  for ((i=1; i<=runs; i++)); do
    local start=$(date +%s%N)
    "$PROJECT_DIR/cljnim" run "$SCRIPT_DIR/$file" > /dev/null 2>&1
    local end=$(date +%s%N)
    local elapsed=$(( (end - start) / 1000000 ))
    nim_times+=($elapsed)
    nim_total=$((nim_total + elapsed))
  done
  local nim_avg=$((nim_total / runs))
  local nim_min=${nim_times[0]}
  for t in "${nim_times[@]}"; do
    if [ $t -lt $nim_min ]; then nim_min=$t; fi
  done
  echo "    Avg: ${nim_avg}ms | Min: ${nim_min}ms | Runs: $runs"
  
  # JVM Clojure
  if command -v clojure &> /dev/null; then
    echo "  [JVM Clojure]"
    local jvm_total=0
    local jvm_times=()
    for ((i=1; i<=runs; i++)); do
      local start=$(date +%s%N)
      clojure "$SCRIPT_DIR/$file" > /dev/null 2>&1
      local end=$(date +%s%N)
      local elapsed=$(( (end - start) / 1000000 ))
      jvm_times+=($elapsed)
      jvm_total=$((jvm_total + elapsed))
    done
    local jvm_avg=$((jvm_total / runs))
    local jvm_min=${jvm_times[0]}
    for t in "${jvm_times[@]}"; do
      if [ $t -lt $jvm_min ]; then jvm_min=$t; fi
    done
    echo "    Avg: ${jvm_avg}ms | Min: ${jvm_min}ms | Runs: $runs"
    
    if [ $jvm_avg -gt 0 ]; then
      local speedup=$((jvm_avg / nim_avg))
      echo "  => Bara Lang is ${speedup}x FASTER (avg)"
    fi
  else
    echo "  [JVM Clojure] — not installed, skipping"
  fi
  echo ""
}

echo "Building Bara Lang..."
nim c -o:"$PROJECT_DIR/cljnim" "$PROJECT_DIR/src/cljnim.nim" 2>/dev/null
echo ""

run_bench "Hello World (startup time)" "hello.clj" 5
run_bench "Fibonacci 30 (recursive)" "fibonacci.clj" 3
run_bench "Factorial 20 (recursive)" "factorial.clj" 3

echo "=============================================="
echo "  Binary size comparison"
echo "=============================================="
echo ""
BINSIZE=$(stat -f%z "$PROJECT_DIR/cljnim" 2>/dev/null || stat -c%s "$PROJECT_DIR/cljnim" 2>/dev/null)
echo "  cljnim binary: $(echo "scale=2; $BINSIZE / 1048576" | bc)MB"
if command -v clojure &> /dev/null; then
  CLOJURE_SIZE=$(du -sh $(dirname $(which clojure))/../ 2>/dev/null | cut -f1)
  echo "  JVM + Clojure: $CLOJURE_SIZE"
fi
echo ""
echo "Done."
