#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "  AOT Benchmark: Pre-compiled vs JVM Startup"
echo "=============================================="
echo ""

nim c -o:"$PROJECT_DIR/cljnim" "$PROJECT_DIR/src/cljnim.nim" 2>/dev/null

# Pre-compile all benchmarks to native binaries
echo "Pre-compiling benchmarks to native binaries..."
for f in "$SCRIPT_DIR"/*.clj; do
  name=$(basename "$f" .clj)
  "$PROJECT_DIR/cljnim" compile "$f" "/tmp/bench_${name}.nim" 2>/dev/null
  nim c -o:"/tmp/bench_${name}" "/tmp/bench_${name}.nim" 2>/dev/null
  echo "  ✓ $name"
done
echo ""

run_aot_bench() {
  local name="$1"
  local bin="/tmp/bench_$2"
  local clj_file="$SCRIPT_DIR/$2.clj"
  local runs="$3"
  
  echo "--- $name ---"
  echo ""
  
  # Pre-compiled native binary
  echo "  [Bara Lang AOT]"
  local nim_total=0
  local nim_times=()
  for ((i=1; i<=runs; i++)); do
    local start=$(date +%s%N)
    "$bin" > /dev/null 2>&1
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
      clojure "$clj_file" > /dev/null 2>&1
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
    
    if [ $nim_avg -gt 0 ]; then
      local speedup=$((jvm_avg / nim_avg))
      echo "  => Bara Lang AOT is ${speedup}x FASTER (avg)"
    fi
  else
    echo "  [JVM Clojure] — not installed"
  fi
  echo ""
}

run_aot_bench "Hello World (startup time)" "hello" 10
run_aot_bench "Fibonacci 30" "fibonacci" 5
run_aot_bench "Factorial 20" "factorial" 5

echo "=============================================="
echo "  Binary sizes"
echo "=============================================="
echo ""
for f in /tmp/bench_*; do
  if [ -f "$f" ] && [[ "$f" != *.nim ]]; then
    fsize=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null)
    echo "  $(basename $f): $(echo "scale=2; $fsize / 1024" | bc)KB"
  fi
done
echo ""
echo "Done."
