# Bars build system
# ─────────────────
# host (Rust bootstrap)  →  cargo build --release  →  target/release/bars
# self  (Bars compiler)  →  make bars-self          →  ./bars-self
#
# Day-to-day language work happens in compiler/*.brs (Bars-first).
# bootstrap/ is frozen like Nim csources — only rebuild for bring-up.

.PHONY: all build host runtime bars-self self gen2 gen3 identity \
        self-test test clean install examples help

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
	@echo "  make runtime     - compile C runtime object"
	@echo "  make bars-self   - Gen1: host compiles $(BUILD_BRS) → ./bars-self"
	@echo "  make gen2        - Gen2: bars-self recompiles itself → ./bars-self2"
	@echo "  make gen3        - Gen3: bars-self2 recompiles → ./bars-self3"
	@echo "  make identity    - Gen3.ll == Gen4.ll fixed-point check"
	@echo "  make self-test   - run example suite with ./bars-self (types ON)"
	@echo "  make test        - cargo test (bootstrap)"
	@echo "  make clean       - remove build artifacts"
	@echo ""
	@echo "Env: types + ownership ON by default for user programs"
	@echo "     BARS_SKIP_TYPECHECK=1 / BARS_SKIP_OWNERSHIP=1  force off"
	@echo "     BARS_STRICT_TYPES=1                            hard-fail types"

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

# ── Self-hosted compiler ───────────────────────────────────────────────────

# Gen1: host → bars-self
bars-self self: $(HOST) $(RUNTIME)
	BARS_SKIP_TYPECHECK=1 $(HOST) build --backend cranelift $(BUILD_BRS) -o $(SELF)
	@echo "→ $(SELF) ready (Gen1)"

# Skip types/ownership when recompiling the full compiler (large AST; own
# flags intentional moves in HIR/temp counters that are false positives today)
SELF_SKIP := BARS_SKIP_TYPECHECK=1 BARS_SKIP_OWNERSHIP=1

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
