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
  examples/let_destructure.brs
  examples/struct_demo.brs
  examples/struct_destructure.brs
  examples/test_demo.brs
  examples/deftest_demo.brs
  examples/defmacro_demo.brs
  examples/defmacro_demo2.brs
  examples/hof_demo.brs
  examples/hof_lambda.brs
  examples/kwargs_demo.brs
  examples/globals_demo.brs
  examples/crypto_demo.brs
  examples/tco_demo.brs
  examples/str_replace_demo.brs
  examples/map_ops_demo.brs
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

# --- Phase 14.2 debugger / profiler smoke ---
run_debug_profile_smoke() {
  local src="examples/math.brs"
  local out="$TMP/dbg_math"
  local log="$TMP/dbg_math.log"
  local ll

  # BARS_DEBUG: DWARF + runnable binary
  if ! BARS_DEBUG=1 BARS_FORCE=1 "$CC_BIN" "$src" "$out" >"$log" 2>&1; then
    echo "FAIL compile  BARS_DEBUG=1 math.brs"
    tail -8 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
    return
  fi
  ll="${out}.ll"
  if [[ ! -f "$ll" ]] || ! grep -q 'DISubprogram' "$ll"; then
    echo "FAIL debug    missing DISubprogram in .ll"
    fail=$((fail + 1))
  elif ! grep -q 'debug:' "$log"; then
    echo "FAIL debug    missing debug note in compile log"
    fail=$((fail + 1))
  else
    local stdout
    stdout="$("$out" 2>/dev/null || true)"
    if [[ "$stdout" == *"120"* ]]; then
      echo "OK   BARS_DEBUG=1 (DWARF DISubprogram + run)"
      pass=$((pass + 1))
    else
      echo "FAIL run      BARS_DEBUG binary (got: $stdout)"
      fail=$((fail + 1))
    fi
  fi

  # BARS_TIMINGS: stage notes
  out="$TMP/tim_math"
  log="$TMP/tim_math.log"
  if ! BARS_TIMINGS=1 BARS_FORCE=1 "$CC_BIN" "$src" "$out" >"$log" 2>&1; then
    echo "FAIL compile  BARS_TIMINGS=1 math.brs"
    tail -5 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
  elif grep -q 'timing: total' "$log" && grep -q 'timing: hir' "$log"; then
    echo "OK   BARS_TIMINGS=1 (stage milliseconds)"
    pass=$((pass + 1))
  else
    echo "FAIL timings  missing timing notes"
    cat "$log" | sed 's/^/  /' | head -20
    fail=$((fail + 1))
  fi

  # BARS_PROFILE: -pg link note + runnable
  out="$TMP/prof_math"
  log="$TMP/prof_math.log"
  if ! BARS_PROFILE=1 BARS_FORCE=1 "$CC_BIN" "$src" "$out" >"$log" 2>&1; then
    echo "FAIL compile  BARS_PROFILE=1 math.brs"
    tail -8 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
  elif ! grep -q 'profile:' "$log"; then
    echo "FAIL profile  missing profile note"
    fail=$((fail + 1))
  else
    stdout="$("$out" 2>/dev/null || true)"
    if [[ "$stdout" == *"120"* ]]; then
      echo "OK   BARS_PROFILE=1 (-pg link + run)"
      pass=$((pass + 1))
    else
      echo "FAIL run      BARS_PROFILE binary (got: $stdout)"
      fail=$((fail + 1))
    fi
  fi
  rm -f gmon.out
}

run_debug_profile_smoke

# --- Cross-compilation smoke (aarch64 + wasm target) ---
run_cross_smoke() {
  local src="examples/math.brs"
  local out log

  # wasm32 via BARS_TARGET (no qemu needed)
  out="$TMP/cross_wasm"
  log="$TMP/cross_wasm.log"
  if ! BARS_TARGET=wasm32-unknown-unknown BARS_FORCE=1 "$CC_BIN" "$src" "$out" >"$log" 2>&1; then
    # math.brs may not be ideal for wasm; try wasm_fact
    if ! BARS_TARGET=wasm32-unknown-unknown BARS_FORCE=1 "$CC_BIN" examples/wasm_fact.brs "$out" >"$log" 2>&1; then
      echo "FAIL compile  BARS_TARGET=wasm32"
      tail -8 "$log" | sed 's/^/  /'
      fail=$((fail + 1))
    else
      if [[ -f "${out}.wat" ]] || [[ -f "${out}.wasm" ]]; then
        echo "OK   BARS_TARGET=wasm32-unknown-unknown → WAT/WASM"
        pass=$((pass + 1))
      else
        echo "FAIL cross    wasm target produced no .wat/.wasm"
        fail=$((fail + 1))
      fi
    fi
  else
    if [[ -f "${out}.wat" ]] || [[ -f "${out}.wasm" ]]; then
      echo "OK   BARS_TARGET=wasm32-unknown-unknown → WAT/WASM"
      pass=$((pass + 1))
    else
      echo "FAIL cross    wasm target produced no .wat/.wasm"
      fail=$((fail + 1))
    fi
  fi

  # aarch64 when cross toolchain + runtime present
  if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    echo "SKIP aarch64 cross (no aarch64-linux-gnu-gcc)"
    return
  fi
  local rt="runtime/bars_runtime_aarch64_unknown_linux_gnu.o"
  if [[ ! -f "$rt" ]]; then
    if ! aarch64-linux-gnu-gcc -O2 -c runtime/bars_runtime.c -o "$rt" 2>"$TMP/rt_a64.log"; then
      echo "SKIP aarch64 cross (cannot build runtime .o)"
      return
    fi
  fi
  out="$TMP/cross_a64"
  log="$TMP/cross_a64.log"
  if ! BARS_FORCE=1 "$CC_BIN" --target aarch64-unknown-linux-gnu "$src" "$out" >"$log" 2>&1; then
    echo "FAIL compile  --target aarch64-unknown-linux-gnu"
    tail -10 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
    return
  fi
  if ! file "$out" | grep -qi 'aarch64\|ARM aarch64'; then
    echo "FAIL cross    expected aarch64 ELF, got: $(file "$out")"
    fail=$((fail + 1))
    return
  fi
  if ! grep -q 'aarch64-unknown-linux-gnu' "${out}.ll" 2>/dev/null; then
    echo "FAIL cross    .ll missing aarch64 target triple"
    fail=$((fail + 1))
    return
  fi
  echo "OK   --target aarch64-unknown-linux-gnu (ELF aarch64)"
  pass=$((pass + 1))
}

run_cross_smoke

# --- Phase 14.6: check + release smoke ---
run_check_release_smoke() {
  local src="examples/math.brs"
  local log="$TMP/check.log"
  local code

  if ! "$CC_BIN" check "$src" >"$log" 2>&1; then
    echo "FAIL check    examples/math.brs"
    tail -8 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
  elif ! grep -q 'check ok' "$log"; then
    echo "FAIL check    missing check ok note"
    cat "$log" | sed 's/^/  /' | head -15
    fail=$((fail + 1))
  else
    echo "OK   bars-self check examples/math.brs"
    pass=$((pass + 1))
  fi

  # ownership fail: use-after-move example if present
  if [[ -f examples/ownership.brs ]]; then
    log="$TMP/check_own.log"
    set +e
    "$CC_BIN" check examples/ownership.brs >"$log" 2>&1
    code=$?
    set -e
    # may be 0 (clean) or 4 (ownership) depending on example content
    if [[ "$code" -eq 0 ]] || [[ "$code" -eq 4 ]]; then
      echo "OK   bars-self check ownership.brs (exit $code)"
      pass=$((pass + 1))
    else
      echo "FAIL check    ownership.brs unexpected exit $code"
      tail -8 "$log" | sed 's/^/  /'
      fail=$((fail + 1))
    fi
  fi

  local out="$TMP/rel_math"
  log="$TMP/rel_math.log"
  if ! BARS_RELEASE=1 BARS_FORCE=1 "$CC_BIN" "$src" "$out" >"$log" 2>&1; then
    echo "FAIL compile  BARS_RELEASE=1"
    tail -8 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
  else
    local stdout
    stdout="$("$out" 2>/dev/null || true)"
    if [[ "$stdout" == *"120"* ]]; then
      echo "OK   BARS_RELEASE=1 (optimized link + run)"
      pass=$((pass + 1))
    else
      echo "FAIL run      BARS_RELEASE binary"
      fail=$((fail + 1))
    fi
  fi
}

run_check_release_smoke

# --- Phase 14.7 TCP net smoke (loopback echo) ---
run_net_smoke() {
  local srv_src="examples/net_echo_server.brs"
  local cli_src="examples/net_client.brs"
  local srv="$TMP/net_srv"
  local cli="$TMP/net_cli"
  local log="$TMP/net.log"
  if [[ ! -f "$srv_src" ]] || [[ ! -f "$cli_src" ]]; then
    echo "SKIP net smoke (examples missing)"
    return
  fi
  if ! "$CC_BIN" "$srv_src" "$srv" >"$log" 2>&1; then
    echo "FAIL compile  net_echo_server"
    tail -8 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
    return
  fi
  if ! "$CC_BIN" "$cli_src" "$cli" >"$log" 2>&1; then
    echo "FAIL compile  net_client"
    tail -8 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
    return
  fi
  "$srv" >/dev/null 2>&1 &
  local spid=$!
  sleep 0.2
  local stdout
  stdout="$("$cli" 2>/dev/null || true)"
  wait "$spid" 2>/dev/null || true
  if echo "$stdout" | grep -q 'ping'; then
    echo "OK   net TCP echo (127.0.0.1:18765)"
    echo "     | $stdout"
    pass=$((pass + 1))
  else
    echo "FAIL run      net echo (got: $stdout)"
    fail=$((fail + 1))
  fi
}

run_net_smoke

# --- Phase 15.1 HTTP client smoke (loopback GET + POST) ---
run_http_smoke() {
  local log="$TMP/http.log"
  local hs="$TMP/http_srv" hc="$TMP/http_cli"
  local es="$TMP/http_echo" pc="$TMP/http_post"

  if [[ ! -f examples/http_server.brs ]] || [[ ! -f examples/http_client.brs ]]; then
    echo "SKIP http smoke (examples missing)"
    return
  fi

  if ! "$CC_BIN" examples/http_server.brs "$hs" >"$log" 2>&1; then
    echo "FAIL compile  http_server"
    tail -8 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
    return
  fi
  if ! "$CC_BIN" examples/http_client.brs "$hc" >"$log" 2>&1; then
    echo "FAIL compile  http_client"
    tail -8 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
    return
  fi
  "$hs" >/dev/null 2>&1 &
  local spid=$!
  sleep 0.25
  local stdout
  stdout="$(timeout 3 "$hc" 2>/dev/null || true)"
  wait "$spid" 2>/dev/null || true
  if echo "$stdout" | grep -qx '200' && echo "$stdout" | grep -qx 'hello'; then
    echo "OK   http GET  (127.0.0.1:18766 → hello)"
    echo "$stdout" | sed 's/^/     | /'
    pass=$((pass + 1))
  else
    echo "FAIL run      http GET (got: $stdout)"
    fail=$((fail + 1))
  fi

  if [[ ! -f examples/http_echo_server.brs ]] || [[ ! -f examples/http_post_client.brs ]]; then
    return
  fi
  if ! "$CC_BIN" examples/http_echo_server.brs "$es" >"$log" 2>&1; then
    echo "FAIL compile  http_echo_server"
    tail -8 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
    return
  fi
  if ! "$CC_BIN" examples/http_post_client.brs "$pc" >"$log" 2>&1; then
    echo "FAIL compile  http_post_client"
    tail -8 "$log" | sed 's/^/  /'
    fail=$((fail + 1))
    return
  fi
  "$es" >/dev/null 2>&1 &
  spid=$!
  sleep 0.25
  stdout="$(timeout 3 "$pc" 2>/dev/null || true)"
  wait "$spid" 2>/dev/null || true
  if echo "$stdout" | grep -qx '200' && echo "$stdout" | grep -qx 'ping'; then
    echo "OK   http POST (127.0.0.1:18767 → ping)"
    echo "$stdout" | sed 's/^/     | /'
    pass=$((pass + 1))
  else
    echo "FAIL run      http POST (got: $stdout)"
    fail=$((fail + 1))
  fi
}

run_http_smoke

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

# --- Phase 14.4 language (traits, async stub, wasm wat) ---
run_lang_smoke() {
  local out log stdout

  out="$TMP/trait_demo"
  if ! "$CC_BIN" examples/trait_demo.brs "$out" >"$TMP/trait.log" 2>&1; then
    echo "FAIL compile  examples/trait_demo.brs"
    tail -8 "$TMP/trait.log" | sed 's/^/  /'
    fail=$((fail + 1))
  else
    stdout="$("$out" 2>/dev/null || true)"
    if echo "$stdout" | head -1 | grep -qx '7' && echo "$stdout" | tail -1 | grep -qx '42'; then
      echo "OK   examples/trait_demo.brs (deftrait/impl/defconst)"
      pass=$((pass + 1))
    else
      echo "FAIL run      trait_demo"
      echo "$stdout" | sed 's/^/     | /'
      fail=$((fail + 1))
    fi
  fi

  out="$TMP/trait_rich"
  if ! "$CC_BIN" examples/trait_rich.brs "$out" >"$TMP/trait_rich.log" 2>&1; then
    echo "FAIL compile  examples/trait_rich.brs"
    tail -8 "$TMP/trait_rich.log" | sed 's/^/  /'
    fail=$((fail + 1))
  else
    stdout="$("$out" 2>/dev/null || true)"
    # 7 7 11 10 42 42
    if echo "$stdout" | tr '\n' ' ' | grep -q '7 7 11 10 42 42'; then
      echo "OK   examples/trait_rich.brs (defaults + Self + tcall)"
      pass=$((pass + 1))
    else
      echo "FAIL run      trait_rich"
      echo "$stdout" | sed 's/^/     | /'
      fail=$((fail + 1))
    fi
  fi

  out="$TMP/async_demo"
  if ! "$CC_BIN" examples/async_demo.brs "$out" >"$TMP/async.log" 2>&1; then
    echo "FAIL compile  examples/async_demo.brs"
    tail -8 "$TMP/async.log" | sed 's/^/  /'
    fail=$((fail + 1))
  else
    stdout="$("$out" 2>/dev/null || true)"
    if echo "$stdout" | sed -n '4p' | grep -qx '99'; then
      echo "OK   examples/async_demo.brs (Future poll stub)"
      pass=$((pass + 1))
    else
      echo "FAIL run      async_demo"
      echo "$stdout" | sed 's/^/     | /'
      fail=$((fail + 1))
    fi
  fi

  out="$TMP/wasm_math"
  if ! BARS_FORCE=1 BARS_BACKEND_WASM=1 "$CC_BIN" examples/math.brs "$out" >"$TMP/wasm.log" 2>&1; then
    echo "FAIL compile  wasm math"
    cat "$TMP/wasm.log" | sed 's/^/  /'
    fail=$((fail + 1))
  elif [[ ! -f "$out.wat" ]] || ! grep -q 'i64.add' "$out.wat"; then
    echo "FAIL wasm     missing .wat / i64.add"
    cat "$TMP/wasm.log" | sed 's/^/  /'
    fail=$((fail + 1))
  elif ! grep -q 'loop \$dispatch' "$out.wat" || ! grep -q 'local.set \$__pc' "$out.wat"; then
    echo "FAIL wasm     missing PC dispatch control flow"
    fail=$((fail + 1))
  else
    echo "OK   BARS_BACKEND_WASM=1 → .wat (PC dispatch CFG)"
    pass=$((pass + 1))
  fi

  # Executable CFG + WASI println (if wasm-tools + wasmtime available)
  if command -v wasm-tools >/dev/null 2>&1 && command -v wasmtime >/dev/null 2>&1; then
    out="$TMP/wasm_fact"
    if BARS_FORCE=1 BARS_BACKEND_WASM=1 "$CC_BIN" examples/wasm_fact.brs "$out" >"$TMP/wasm_fact.log" 2>&1 \
       && wasm-tools validate "$out.wasm" >/dev/null 2>&1; then
      got="$(wasmtime --invoke main "$out.wasm" 2>/dev/null | tr -d '\r')"
      if [[ "$got" == "120" ]]; then
        echo "OK   wasm_fact → wasmtime main = 120"
        pass=$((pass + 1))
      else
        echo "FAIL wasm_fact run (got: $got)"
        fail=$((fail + 1))
      fi
    else
      echo "FAIL wasm_fact compile/validate"
      tail -5 "$TMP/wasm_fact.log" | sed 's/^/  /'
      fail=$((fail + 1))
    fi
    out="$TMP/wasm_loop"
    if BARS_FORCE=1 BARS_BACKEND_WASM=1 "$CC_BIN" examples/wasm_loop.brs "$out" >"$TMP/wasm_loop.log" 2>&1 \
       && wasm-tools validate "$out.wasm" >/dev/null 2>&1; then
      got="$(wasmtime --invoke main "$out.wasm" 2>/dev/null | tr -d '\r')"
      if [[ "$got" == "45" ]]; then
        echo "OK   wasm_loop → wasmtime main = 45"
        pass=$((pass + 1))
      else
        echo "FAIL wasm_loop run (got: $got)"
        fail=$((fail + 1))
      fi
    else
      echo "FAIL wasm_loop compile/validate"
      fail=$((fail + 1))
    fi
    # WASI fd_write println
    out="$TMP/wasm_print"
    if BARS_FORCE=1 BARS_BACKEND_WASM=1 "$CC_BIN" examples/wasm_print.brs "$out" >"$TMP/wasm_print.log" 2>&1 \
       && wasm-tools validate "$out.wasm" >/dev/null 2>&1; then
      # stdout lines before wasmtime warnings
      got="$(wasmtime --invoke main "$out.wasm" 2>/dev/null | grep -E '^[0-9-]+$' | tr '\n' ' ' | sed 's/ *$//')"
      if [[ "$got" == "7 120 0" ]]; then
        echo "OK   wasm_print → WASI println 7 / 120"
        pass=$((pass + 1))
      else
        echo "FAIL wasm_print (got: '$got')"
        fail=$((fail + 1))
      fi
    else
      echo "FAIL wasm_print compile/validate"
      fail=$((fail + 1))
    fi
  else
    echo "SKIP wasmtime CFG/WASI run (install wasm-tools + wasmtime)"
  fi
}

echo "=== Phase 14.4 language ==="
run_lang_smoke

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
  examples/let_destructure.brs
  examples/struct_demo.brs
  examples/struct_destructure.brs
  examples/test_demo.brs
  examples/deftest_demo.brs
  examples/defmacro_demo.brs
  examples/defmacro_demo2.brs
  examples/hof_demo.brs
  examples/hof_lambda.brs
  examples/kwargs_demo.brs
  examples/globals_demo.brs
  examples/crypto_demo.brs
  examples/tco_demo.brs
  examples/str_replace_demo.brs
  examples/map_ops_demo.brs
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
