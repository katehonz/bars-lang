.PHONY: all build test clean install examples

all: build

build:
	cargo build --release

test:
	cargo test

clean:
	cargo clean
	find . -name "*.ssa" -delete
	find . -name "*.qbe" -delete

examples:
	cargo run -- build examples/hello.brs
	cargo run -- build examples/math.brs
	cargo run -- build examples/ownership.brs

install:
	cargo install --path bootstrap
