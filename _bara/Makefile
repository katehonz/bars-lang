.PHONY: build test check clean run-example bench bench-aot

NIMCACHE = nimcache

build:
	nim c -d:ssl -o:cljnim src/cljnim.nim

test:
	nim c -r tests/test_reader.nim
	nim c -r tests/test_emitter.nim
	nim c -r tests/test_pvec.nim
	nim c -r tests/test_pmap.nim
	nim c -r tests/test_deps.nim
	nim c -r tests/test_macros.nim
	nim c -d:ssl -r tests/test_eval.nim
	nim c -d:ssl --path:src -r tests/test_ai_assist.nim

test-reader:
	nim c -r tests/test_reader.nim

test-emitter:
	nim c -r tests/test_emitter.nim

check: build test
	./cljnim run examples/hello.clj
	./cljnim run examples/math.clj
	./cljnim run examples/core.clj
	./cljnim run examples/interop.clj
	./cljnim run examples/macros.clj
	./cljnim run examples/jsonista.clj

run-example: build
	./cljnim run examples/hello.clj

bench:
	bash benchmarks/run_benchmarks.sh

bench-aot:
	bash benchmarks/run_aot_benchmarks.sh

clean:
	rm -f cljnim
	rm -rf $(NIMCACHE)
	find . -name "*_generated.nim" -delete
	find . -name "*_generated" -delete
	find . -name "test_reader" -delete
	find . -name "test_emitter" -delete
	find . -name "test_deps" -delete
	find . -name "test_pvec" -delete
	find . -name "test_pmap" -delete
	find . -name "test_eval" -delete
	find . -name "test_macros" -delete
	find . -name "test_ai_assist" -delete
