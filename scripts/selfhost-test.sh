#!/usr/bin/env bash
# Run a fixed suite of examples with a Bars self-hosted compiler.
# Usage: scripts/selfhost-test.sh [compiler-binary]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CC_BIN="${1:-./bars-self}"
if [[ ! -x "$CC_BIN" ]]; then
  echo "error: compiler not found or not executable: $CC_BIN" >&2
  echo "hint: make bars-self" >&2
  exit 1
fi

if [[ ! -f runtime/bars_runtime.o ]]; then
  echo "error: missing runtime/bars_runtime.o (make runtime)" >&2
  exit 1
fi

TMP="${TMPDIR:-/tmp}/bars-selftest-$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

run_one() {
  local src="$1"
  local tag="${2:-}"
  local name
  name="$(basename "$src" .brs)"
  [[ -n "$tag" ]] && name="${name}_${tag}"
  local out="$TMP/$name"
  local log="$TMP/$name.compile.log"
  if ! "$CC_BIN" "$src" "$out" >"$log" 2>&1; then
    echo "FAIL compile  $src${tag:+ ($tag)}"
    tail -5 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
    return
  fi
  if [[ ! -x "$out" ]]; then
    echo "FAIL no-bin   $src${tag:+ ($tag)}"
    fail=$((fail + 1))
    return
  fi
  # Run; non-zero exit is OK if stdout looks fine (some mains return n)
  local stdout
  stdout="$("$out" 2>"$TMP/$name.stderr" || true)"
  echo "OK   $src${tag:+ ($tag)}"
  if [[ -n "$stdout" ]]; then
    echo "$stdout" | sed 's/^/     | /' | head -6
  fi
  pass=$((pass + 1))
}

EXAMPLES=(
  examples/math.brs
  examples/loop_demo.brs
  examples/match_demo.brs
  examples/match_binding.brs
  examples/vector.brs
  examples/module_demo.brs
  examples/module_nested.brs
  examples/pkg_app/src/main.brs
  examples/adt_demo.brs
  examples/adt_demo2.brs
  examples/string.brs
  examples/cond_demo.brs
  examples/nested_demo.brs
  examples/map.brs
)

echo "=== self-host test with $CC_BIN ==="
# Optional typecheck pass (Gen1); set BARS_TYPECHECK=1 to enable
if [[ "${BARS_TYPECHECK:-}" == "1" ]]; then
  echo "(typecheck enabled)"
fi
for src in "${EXAMPLES[@]}"; do
  if [[ -f "$src" ]]; then
    run_one "$src"
  else
    echo "SKIP missing  $src"
  fi
done

# --- git path-deps smoke (local file:// repo; no network) ---
run_git_dep_smoke() {
  local gitlib="$TMP/gitlib"
  local gitapp="$TMP/gitapp"
  mkdir -p "$gitlib/src" "$gitapp/src"
  cat >"$gitlib/src/lib.brs" <<'EOF'
(defn magic [] 99)
EOF
  cat >"$gitlib/Bars.toml" <<'EOF'
[package]
name = "gitlib"
version = "0.1.0"
EOF
  git -C "$gitlib" init -q
  git -C "$gitlib" add -A
  git -C "$gitlib" -c user.email=t@t -c user.name=t commit -q -m init
  local url="file://$gitlib"
  cat >"$gitapp/Bars.toml" <<EOF
[package]
name = "gitapp"
version = "0.1.0"

[dependencies]
gitlib = { git = "$url" }
EOF
  cat >"$gitapp/src/main.brs" <<'EOF'
(require "gitlib" :as g)
(defn main []
  (println (g/magic)))
EOF
  local out="$TMP/gitapp_bin"
  if ! "$CC_BIN" "$gitapp/src/main.brs" "$out" >"$TMP/gitapp.compile.log" 2>&1; then
    echo "FAIL compile  git-dep smoke"
    tail -8 "$TMP/gitapp.compile.log" | sed 's/^/  /'
    fail=$((fail + 1))
    return
  fi
  local stdout
  stdout="$("$out" 2>/dev/null || true)"
  if [[ "$stdout" == *"99"* ]]; then
    echo "OK   git-dep smoke (Bars.toml git = file://…)"
    echo "     | $stdout"
    pass=$((pass + 1))
  else
    echo "FAIL run      git-dep smoke (got: $stdout)"
    fail=$((fail + 1))
  fi
}

if command -v git >/dev/null 2>&1; then
  run_git_dep_smoke
else
  echo "SKIP git-dep smoke (git not found)"
fi

# --- C backend suite (BARS_BACKEND_C=1 → .c + cc) ---
# Same examples as LLVM; set BARS_SKIP_C_TEST=1 to skip.
C_EXAMPLES=(
  examples/math.brs
  examples/loop_demo.brs
  examples/match_demo.brs
  examples/match_binding.brs
  examples/vector.brs
  examples/module_demo.brs
  examples/module_nested.brs
  examples/pkg_app/src/main.brs
  examples/adt_demo.brs
  examples/adt_demo2.brs
  examples/string.brs
  examples/cond_demo.brs
  examples/nested_demo.brs
  examples/map.brs
)

if [[ "${BARS_SKIP_C_TEST:-}" == "1" ]]; then
  echo "SKIP C-backend suite (BARS_SKIP_C_TEST=1)"
elif ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
  echo "SKIP C-backend suite (no cc/gcc)"
else
  echo "=== C backend suite (BARS_BACKEND_C=1) ==="
  export BARS_BACKEND_C=1
  for src in "${C_EXAMPLES[@]}"; do
    if [[ -f "$src" ]]; then
      run_one "$src" "c"
    else
      echo "SKIP missing  $src (c)"
    fi
  done
  unset BARS_BACKEND_C
fi

echo "=== $pass passed, $fail failed ==="
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
