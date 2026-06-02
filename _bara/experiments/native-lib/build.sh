#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLJNIM="${SCRIPT_DIR}/../../cljnim"
LIB_PATH="${SCRIPT_DIR}/../../lib"

mkdir -p "${SCRIPT_DIR}/build"

echo "=== Step 1: Clojure → Nim ==="
"$CLJNIM" compile-lib \
  "${SCRIPT_DIR}/examples/math.clj" \
  "${SCRIPT_DIR}/build/math.nim"

echo "=== Step 2: Nim → Shared Library ==="
cd "$SCRIPT_DIR" && nim c --app:lib \
  --path:"$LIB_PATH" \
  -d:release \
  -o:"build/libmath.so" \
  "native_wrappers.nim"

echo "=== Step 3: Generated files ==="
ls -la "${SCRIPT_DIR}/build/"
echo ""
echo "Library: ${SCRIPT_DIR}/build/libmath.so"
echo ""
echo "To test: cd ${SCRIPT_DIR}/test_client && make && LD_LIBRARY_PATH=../build ./test_client"
