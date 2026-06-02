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

echo "=== Step 2: Nim → WASM (via Emscripten) ==="
cd "$SCRIPT_DIR"

if ! command -v emcc &> /dev/null; then
    echo "ERROR: Emscripten not found."
    echo "Install: git clone https://github.com/emscripten-core/emsdk.git"
    echo "         ./emsdk install latest && ./emsdk activate latest"
    exit 1
fi

emcc nim c --cc:clang \
  --path:"$LIB_PATH" \
  -d:emscripten -d:release \
  --noMain \
  -o:"build/math.js" \
  "wasm_wrappers.nim"

echo "=== Step 3: Generated files ==="
ls -la "${SCRIPT_DIR}/build/"
echo ""
echo "Open ${SCRIPT_DIR}/www/index.html in a browser to test"
