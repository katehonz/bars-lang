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
  git -C "$gitlib" init -q -b master
  git -C "$gitlib" add -A
  git -C "$gitlib" -c user.email=t@t -c user.name=t commit -q -m init
  git -C "$gitlib" tag v0.1
  # pinned branch with different value
  git -C "$gitlib" checkout -q -b pinbr
  cat >"$gitlib/src/lib.brs" <<'EOF'
(defn magic [] 77)
EOF
  git -C "$gitlib" add -A
  git -C "$gitlib" -c user.email=t@t -c user.name=t commit -q -m pin
  git -C "$gitlib" checkout -q master
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

  # branch pin → pinbr → 77; re-clone because pin changed
  cat >"$gitapp/Bars.toml" <<EOF
[package]
name = "gitapp"
version = "0.1.0"

[dependencies]
gitlib = { git = "$url", branch = "pinbr" }
EOF
  out="$TMP/gitapp_pin"
  if ! "$CC_BIN" "$gitapp/src/main.brs" "$out" >"$TMP/gitapp_pin.compile.log" 2>&1; then
    echo "FAIL compile  git-dep branch pin"
    tail -8 "$TMP/gitapp_pin.compile.log" | sed 's/^/  /'
    fail=$((fail + 1))
    return
  fi
  stdout="$("$out" 2>/dev/null || true)"
  if [[ "$stdout" == *"77"* ]]; then
    echo "OK   git-dep branch pin (branch=pinbr)"
    echo "     | $stdout"
    pass=$((pass + 1))
  else
    echo "FAIL run      git-dep branch pin (got: $stdout)"
    fail=$((fail + 1))
  fi

  # cache hit: same branch, no re-clone line required — just succeed with 77
  out="$TMP/gitapp_pin2"
  if ! "$CC_BIN" "$gitapp/src/main.brs" "$out" >"$TMP/gitapp_pin2.compile.log" 2>&1; then
    echo "FAIL compile  git-dep pin cache"
    fail=$((fail + 1))
    return
  fi
  if grep -q 'git clone' "$TMP/gitapp_pin2.compile.log"; then
    echo "FAIL cache     git-dep re-cloned with same pin"
    fail=$((fail + 1))
  else
    echo "OK   git-dep pin cache hit"
    pass=$((pass + 1))
  fi
}

if command -v git >/dev/null 2>&1; then
  run_git_dep_smoke
else
  echo "SKIP git-dep smoke (git not found)"
fi

# --- incremental mtime skip (Phase 13.3) ---
run_incremental_smoke() {
  local src="examples/math.brs"
  local out="$TMP/inc_math"
  local log1="$TMP/inc1.log"
  local log2="$TMP/inc2.log"
  local log3="$TMP/inc3.log"
  if ! "$CC_BIN" "$src" "$out" >"$log1" 2>&1; then
    echo "FAIL compile  incremental first build"
    tail -5 "$log1" | sed 's/^/  /'
    fail=$((fail + 1))
    return
  fi
  if ! "$CC_BIN" "$src" "$out" >"$log2" 2>&1; then
    echo "FAIL compile  incremental second build"
    fail=$((fail + 1))
    return
  fi
  if ! grep -q 'up to date' "$log2"; then
    echo "FAIL incremental: expected 'up to date' on second build"
    cat "$log2" | sed 's/^/  /'
    fail=$((fail + 1))
    return
  fi
  if ! BARS_FORCE=1 "$CC_BIN" "$src" "$out" >"$log3" 2>&1; then
    echo "FAIL compile  incremental force rebuild"
    fail=$((fail + 1))
    return
  fi
  if grep -q 'up to date' "$log3"; then
    echo "FAIL incremental: BARS_FORCE=1 should not skip"
    fail=$((fail + 1))
    return
  fi
  local stdout
  stdout="$("$out" 2>/dev/null || true)"
  if [[ "$stdout" == *"120"* ]]; then
    echo "OK   incremental skip + BARS_FORCE rebuild"
    pass=$((pass + 1))
  else
    echo "FAIL run      incremental binary (got: $stdout)"
    fail=$((fail + 1))
  fi
}

run_incremental_smoke

# --- Phase 14.1 stdlib smoke (io / json / random+time+regex) ---
run_stdlib_smoke() {
  local out log stdout

  # io
  out="$TMP/io_demo"
  log="$TMP/io_demo.log"
  if ! "$CC_BIN" examples/io_demo.brs "$out" >"$log" 2>&1; then
    echo "FAIL compile  examples/io_demo.brs"
    tail -5 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
  else
    stdout="$("$out" 2>/dev/null || true)"
    if [[ "$stdout" == *"hello world"* ]] && [[ "$stdout" == *$'\n'0 ]] || [[ "$stdout" == *$'0' ]]; then
      # last line should be 0 (deleted)
      if echo "$stdout" | tail -1 | grep -qx '0'; then
        echo "OK   examples/io_demo.brs"
        pass=$((pass + 1))
      else
        echo "FAIL run      io_demo (expected last line 0)"
        echo "$stdout" | sed 's/^/     | /'
        fail=$((fail + 1))
      fi
    else
      echo "FAIL run      io_demo"
      echo "$stdout" | sed 's/^/     | /'
      fail=$((fail + 1))
    fi
  fi

  # json
  out="$TMP/json_demo"
  log="$TMP/json_demo.log"
  if ! "$CC_BIN" examples/json_demo.brs "$out" >"$log" 2>&1; then
    echo "FAIL compile  examples/json_demo.brs"
    tail -8 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
  else
    stdout="$("$out" 2>/dev/null || true)"
    if echo "$stdout" | grep -q '{"k":7}' && echo "$stdout" | head -1 | grep -qx '42'; then
      echo "OK   examples/json_demo.brs"
      pass=$((pass + 1))
    else
      echo "FAIL run      json_demo"
      echo "$stdout" | sed 's/^/     | /' | head -20
      fail=$((fail + 1))
    fi
  fi

  # random + time + regex
  out="$TMP/rtr_demo"
  log="$TMP/rtr_demo.log"
  if ! "$CC_BIN" examples/random_time_demo.brs "$out" >"$log" 2>&1; then
    echo "FAIL compile  examples/random_time_demo.brs"
    tail -8 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
  else
    stdout="$("$out" 2>/dev/null || true)"
    # lines: timeok timeok a b rangeok match1 match0 find miss elapsedok
    # match1=1, match0=0, find=2, miss=-1
    if echo "$stdout" | sed -n '6p' | grep -qx '1' \
       && echo "$stdout" | sed -n '7p' | grep -qx '0' \
       && echo "$stdout" | sed -n '8p' | grep -qx '2' \
       && echo "$stdout" | sed -n '9p' | grep -qx -- '-1'; then
      echo "OK   examples/random_time_demo.brs"
      pass=$((pass + 1))
    else
      echo "FAIL run      random_time_demo"
      echo "$stdout" | sed 's/^/     | /'
      fail=$((fail + 1))
    fi
  fi
}

if [[ -f examples/io_demo.brs ]]; then
  echo "=== Phase 14.1 stdlib ==="
  run_stdlib_smoke
fi

# --- Phase 14.2 tooling (fmt / lint / doc) ---
run_tooling_smoke() {
  local out log

  # fmt: pretty-print contains defn
  out="$TMP/fmt_out.txt"
  if ! "$CC_BIN" fmt examples/math.brs >"$out" 2>"$TMP/fmt.err"; then
    echo "FAIL fmt      examples/math.brs"
    tail -5 "$TMP/fmt.err" | sed 's/^/  /'
    fail=$((fail + 1))
  elif ! grep -q '(defn add' "$out"; then
    echo "FAIL fmt      missing defn add"
    head -10 "$out" | sed 's/^/  /'
    fail=$((fail + 1))
  else
    echo "OK   bars-self fmt examples/math.brs"
    pass=$((pass + 1))
  fi

  # lint clean
  if ! "$CC_BIN" lint examples/math.brs >"$TMP/lint.out" 2>&1; then
    echo "FAIL lint     examples/math.brs"
    cat "$TMP/lint.out" | sed 's/^/  /'
    fail=$((fail + 1))
  elif ! grep -q 'lint clean' "$TMP/lint.out"; then
    echo "FAIL lint     expected clean"
    cat "$TMP/lint.out" | sed 's/^/  /'
    fail=$((fail + 1))
  else
    echo "OK   bars-self lint examples/math.brs"
    pass=$((pass + 1))
  fi

  # lint dirty → exit 5
  printf '(defn foo [x]\t(+ x 1))   \n' >"$TMP/dirty.brs"
  set +e
  "$CC_BIN" lint "$TMP/dirty.brs" >"$TMP/lint_dirty.out" 2>&1
  local rc=$?
  set -e
  if [[ $rc -ne 5 ]]; then
    echo "FAIL lint     dirty expected exit 5 got $rc"
    cat "$TMP/lint_dirty.out" | sed 's/^/  /'
    fail=$((fail + 1))
  elif ! grep -q 'tab character' "$TMP/lint_dirty.out"; then
    echo "FAIL lint     expected tab warning"
    fail=$((fail + 1))
  else
    echo "OK   bars-self lint (dirty → exit 5)"
    pass=$((pass + 1))
  fi

  # doc
  if ! "$CC_BIN" doc lib/io.brs "$TMP/io.md" >"$TMP/doc.out" 2>&1; then
    echo "FAIL doc      lib/io.brs"
    cat "$TMP/doc.out" | sed 's/^/  /'
    fail=$((fail + 1))
  elif ! grep -q 'read-file' "$TMP/io.md"; then
    echo "FAIL doc      missing read-file"
    fail=$((fail + 1))
  else
    echo "OK   bars-self doc lib/io.brs"
    pass=$((pass + 1))
  fi
}

echo "=== Phase 14.2 tooling ==="
run_tooling_smoke

# --- Phase 14.3 ecosystem (local registry) ---
run_registry_smoke() {
  local reg="$TMP/bars-reg"
  local libdir="$TMP/reglib"
  local appdir="$TMP/regapp"
  export BARS_REGISTRY="$reg"

  mkdir -p "$libdir/src" "$appdir/src"
  cat >"$libdir/Bars.toml" <<'EOF'
[package]
name = "reglib"
version = "0.1.0"

[dependencies]
EOF
  cat >"$libdir/src/lib.brs" <<'EOF'
(defn magic [] 55)
EOF
  if ! "$CC_BIN" publish "$libdir" >"$TMP/pub.log" 2>&1; then
    echo "FAIL publish  registry smoke"
    cat "$TMP/pub.log" | sed 's/^/  /'
    fail=$((fail + 1))
    unset BARS_REGISTRY
    return
  fi
  if ! grep -q 'reglib 0.1.0' "$reg/index.txt" 2>/dev/null; then
    echo "FAIL publish  index missing reglib"
    fail=$((fail + 1))
    unset BARS_REGISTRY
    return
  fi

  cat >"$appdir/Bars.toml" <<'EOF'
[package]
name = "regapp"
version = "0.1.0"

[dependencies]
reglib = { version = "0.1.0" }
EOF
  cat >"$appdir/src/main.brs" <<'EOF'
(require "reglib" :as r)
(defn main []
  (println (r/magic)))
EOF
  local out="$TMP/regapp_bin"
  if ! "$CC_BIN" "$appdir/src/main.brs" "$out" >"$TMP/regapp.compile.log" 2>&1; then
    echo "FAIL compile  registry dep app"
    tail -8 "$TMP/regapp.compile.log" | sed 's/^/  /'
    fail=$((fail + 1))
    unset BARS_REGISTRY
    return
  fi
  local stdout
  stdout="$("$out" 2>/dev/null || true)"
  if [[ "$stdout" == *"55"* ]]; then
    echo "OK   registry publish + version dep (55)"
    pass=$((pass + 1))
  else
    echo "FAIL run      registry dep (got: $stdout)"
    fail=$((fail + 1))
  fi

  # search
  if "$CC_BIN" search reglib >"$TMP/search.out" 2>&1 && grep -q reglib "$TMP/search.out"; then
    echo "OK   bars-self search"
    pass=$((pass + 1))
  else
    echo "FAIL search"
    fail=$((fail + 1))
  fi

  # new (absolute compiler path — we cd into a temp dir)
  local newdir="$TMP/newpkg_home"
  local abs_cc
  abs_cc="$(cd "$(dirname "$CC_BIN")" && pwd)/$(basename "$CC_BIN")"
  mkdir -p "$newdir"
  if (cd "$newdir" && "$abs_cc" new coolpkg >"$TMP/new.log" 2>&1) && [[ -f "$newdir/coolpkg/Bars.toml" ]]; then
    echo "OK   bars-self new coolpkg"
    pass=$((pass + 1))
  else
    echo "FAIL new"
    cat "$TMP/new.log" | sed 's/^/  /'
    fail=$((fail + 1))
  fi

  unset BARS_REGISTRY
}

echo "=== Phase 14.3 ecosystem ==="
run_registry_smoke

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
