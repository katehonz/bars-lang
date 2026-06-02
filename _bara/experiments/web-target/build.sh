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

echo "=== Step 2: Patch runtime for JS ==="
sed -i 's/import cljnim_runtime/import cljnim_runtime_js/' "${SCRIPT_DIR}/build/math.nim"

echo "=== Step 3: Nim → JavaScript ==="
cd "$SCRIPT_DIR" && nim js -d:release \
  --path:"$LIB_PATH" \
  --path:"build" \
  -o:"build/math.js" \
  "js_wrappers.nim"

echo "=== Step 3: Generated files ==="
ls -la "${SCRIPT_DIR}/build/"
echo ""
echo "JS: ${SCRIPT_DIR}/build/math.js"
echo ""
echo "Open ${SCRIPT_DIR}/www/index.html in a browser to test"
