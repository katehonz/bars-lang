# Bars build system
# ─────────────────
# host (Rust bootstrap)  →  cargo build --release  →  target/release/bars
# self  (Bars compiler)  →  make bars-self          →  ./bars-self
#
# Day-to-day language work happens in compiler/*.brs (Bars-first).
# bootstrap/ is frozen like Nim csources — only rebuild for bring-up.

.PHONY: all build host runtime runtime-aarch64 bars-self self gen2 gen3 identity \
        self-test self-test-c test clean install examples help

HOST     := ./target/release/bars
SELF     := ./bars-self
SELF2    := ./bars-self2
SELF3    := ./bars-self3
RUNTIME  := runtime/bars_runtime.o
BUILD_BRS := compiler/build.brs

all: bars-self

help:
	@echo "Bars targets:"
	@echo "  make host        - build Rust bootstrap (target/release/bars)"
	@echo "  make runtime     - compile C runtime object (host)"
	@echo "  make runtime-aarch64 - cross runtime for aarch64-unknown-linux-gnu"
	@echo "  make bars-self   - Gen1: host compiles $(BUILD_BRS) → ./bars-self"
	@echo "  make gen2        - Gen2: bars-self recompiles itself → ./bars-self2"
	@echo "  make gen3        - Gen3: bars-self2 recompiles → ./bars-self3"
	@echo "  make identity    - Gen3.ll == Gen4.ll fixed-point check"
	@echo "  make self-test   - example suite (LLVM + git smoke + C backend)"
	@echo "  make self-test-c - C-backend examples only (BARS_BACKEND_C=1)"
	@echo "  make test        - cargo test (bootstrap)"
	@echo "  make clean       - remove build artifacts"
	@echo ""
	@echo "Env: types + ownership ON by default"
	@echo "     BARS_SKIP_TYPECHECK=1 / BARS_SKIP_OWNERSHIP=1  force off"
	@echo "     BARS_STRICT_TYPES=1                            hard-fail types"
	@echo "     BARS_BACKEND_C=1     use C backend (.c + cc) instead of LLVM"
	@echo "     BARS_SKIP_C_TEST=1   skip C suite inside self-test"
	@echo "     BARS_FORCE=1         force rebuild (disable mtime skip)"
	@echo "     BARS_NO_INCREMENTAL=1  always recompile"
	@echo "     BARS_DEBUG=1         DWARF (-g -O0); gdb/lldb ready"
	@echo "     BARS_PROFILE=1       gprof (-pg -g); then gprof/perf"
	@echo "     BARS_TIMINGS=1       print compile-stage milliseconds"
	@echo "     BARS_TARGET=triple   cross-compile (or --target <triple>)"
	@echo "       host from uname -m; aarch64-unknown-linux-gnu | wasm32-unknown-unknown"
	@echo "     BARS_RELEASE=1       optimize link (-O2)"
	@echo "     (self-host skips types only; ownership is light NLL)"
	@echo ""
	@echo "bars-self: ./bars-self <in.brs> <out>"
	@echo "           ./bars-self --target <triple> <in.brs> <out>"
	@echo "           ./bars-self check|watch|fmt|lint|doc …"

# ── Host (Rust bootstrap, frozen) ──────────────────────────────────────────

build host:
	cargo build --release

test:
	cargo test

install:
	cargo install --path bootstrap

# ── C runtime ──────────────────────────────────────────────────────────────

runtime $(RUNTIME): runtime/bars_runtime.c runtime/bars_runtime.h
	$(CC) -O2 -c runtime/bars_runtime.c -o runtime/bars_runtime.o
	ar rcs runtime/libbars_runtime.a runtime/bars_runtime.o

# Cross-compiled runtime for aarch64 (requires aarch64-linux-gnu-gcc)
RUNTIME_AARCH64 := runtime/bars_runtime_aarch64_unknown_linux_gnu.o
AARCH64_CC ?= aarch64-linux-gnu-gcc

runtime-aarch64 $(RUNTIME_AARCH64): runtime/bars_runtime.c runtime/bars_runtime.h
	$(AARCH64_CC) -O2 -c runtime/bars_runtime.c -o $(RUNTIME_AARCH64)
	@echo "→ $(RUNTIME_AARCH64) ready"

# ── Self-hosted compiler ───────────────────────────────────────────────────

# Gen1: host → bars-self
bars-self self: $(HOST) $(RUNTIME)
	BARS_SKIP_TYPECHECK=1 $(HOST) build --backend cranelift $(BUILD_BRS) -o $(SELF)
	@echo "→ $(SELF) ready (Gen1)"

# Skip types when recompiling the full compiler (large AST soft-noise).
# Ownership is light NLL and clean on compiler sources (loop rebinds ≠ moves).
SELF_SKIP := BARS_SKIP_TYPECHECK=1

# Gen2: bars-self → bars-self2
gen2: bars-self
	$(SELF_SKIP) $(SELF) $(BUILD_BRS) $(SELF2)
	@echo "→ $(SELF2) ready (Gen2)"

# Gen3: bars-self2 → bars-self3
gen3: gen2
	$(SELF_SKIP) $(SELF2) $(BUILD_BRS) $(SELF3)
	@echo "→ $(SELF3) ready (Gen3)"

# Identity: Gen3 and Gen4 produce identical LLVM IR
identity: gen3
	@tmp=$$(mktemp -d) && \
	  $(SELF_SKIP) $(SELF3) $(BUILD_BRS) $$tmp/gen4 && \
	  if cmp -s $(SELF3).ll $$tmp/gen4.ll; then \
	    echo "OK identity: Gen3.ll == Gen4.ll (fixed point)"; \
	  else \
	    echo "FAIL identity: LLVM IR differs"; \
	    diff -u $(SELF3).ll $$tmp/gen4.ll | head -40; \
	    rm -rf $$tmp; exit 1; \
	  fi && rm -rf $$tmp

# Example suites (types ON by default for user programs)
self-test: bars-self
	@bash scripts/selfhost-test.sh $(SELF)

# C backend only (same examples, BARS_BACKEND_C=1)
self-test-c: bars-self
	@BARS_BACKEND_C=1 bash -c 'pass=0; fail=0; \
	  for s in examples/math.brs examples/loop_demo.brs examples/match_demo.brs \
	    examples/vector.brs examples/string.brs examples/cond_demo.brs \
	    examples/module_demo.brs examples/map.brs examples/nested_demo.brs; do \
	    out=/tmp/bars-c-$$$$-$$(basename $$s .brs); \
	    if BARS_BACKEND_C=1 $(SELF) $$s $$out >/tmp/bars-c-$$$$.log 2>&1 && $$out >/dev/null 2>&1; then \
	      echo "OK   $$s (c)"; pass=$$((pass+1)); \
	    else echo "FAIL $$s (c)"; fail=$$((fail+1)); fi; \
	  done; echo "=== $$pass passed, $$fail failed (c) ==="; test $$fail -eq 0'

self-test-gen2: gen2
	@bash scripts/selfhost-test.sh $(SELF2)

examples: bars-self
	@bash scripts/selfhost-test.sh $(SELF)

# ── Cleanup ────────────────────────────────────────────────────────────────

clean:
	cargo clean
	rm -f bars-self bars-self2 bars-self3 bars-self4
	rm -f bars-self.ll bars-self2.ll bars-self3.ll bars-self4.ll
	rm -f runtime/bars_runtime.o runtime/libbars_runtime.a
	find . -name "*.ssa" -delete 2>/dev/null || true
	find . -name "*.qbe" -delete 2>/dev/null || true
