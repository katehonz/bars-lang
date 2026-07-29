# Standard Library

Bars ships with a standard library written in Bars itself under `lib/`.

## Loading

```clojure
(load "lib/core.brs")
(load "lib/math.brs")
(load "lib/vector.brs")
```

## Built-in Collection Functions

These are implemented in the C runtime and available without `load`:

### Vectors

| Function | Signature | Description |
|----------|-----------|-------------|
| `vector` | `(vector x y z ...)` | Create a vector with elements |
| `push` | `(push vec val)` | Append value to vector (**mutates**) |
| `get` | `(get vec idx)` | Element at index (0-based) |
| `count` | `(count vec)` | Number of elements |
| `vector-clone` | `(vector-clone v)` | Shallow copy |
| `conj` | `(conj v x)` | Copy + append `x` (original untouched) |
| `v-assoc` | `(v-assoc v i x)` | Copy with index `i` set to `x` |
| `v-pop` | `(v-pop v)` | Copy without last element |

Persistent ops are COW (clone then mutate the copy), not full structural sharing.

Vectors can be nested:

```clojure
(def v [1 [2 3] 4])
(println (get (get v 1) 0))  ;; → 2
```

### Maps

| Function | Signature | Description |
|----------|-----------|-------------|
| `map` | `(map)` | Create empty map |
| `map-set` | `(map-set m key val)` | Set key-value pair (**mutates**) |
| `map-get` | `(map-get m key)` | Get value by key |
| `map-count` | `(map-count m)` | Number of entries |
| `map-contains?` | `(map-contains? m key)` | `1` if key exists (even mapped to `0`), else `0` |
| `map-keys` | `(map-keys m)` | Vector of keys |
| `map-values` | `(map-values m)` | Vector of values |
| `map-clone` | `(map-clone m)` | Shallow copy |
| `map-assoc` | `(map-assoc m k v)` | Copy with `k → v` (original untouched) |

Maps can hold vectors and other collections:

```clojure
(def m (map))
(map-set m 1 [10 20])
(map-set m 2 [30 40])
(println (get (map-get m 1) 0))  ;; → 10
```

### Sets

| Function | Signature | Description |
|----------|-----------|-------------|
| `set` | `(set)` or `(set a b c)` | Create set (optionally with initial elements) |
| `set-add` | `(set-add s val)` | Add element to set |
| `set-contains?` | `(set-contains? s val)` | Check membership (1 or 0) |
| `set-count` | `(set-count s)` | Number of unique elements |

```clojure
(def s (set))
(set-add s 1)
(set-add s 2)
(set-add s 3)
(println (set-count s))          ;; → 3
(println (set-contains? s 2))    ;; → 1
(println (set-contains? s 99))   ;; → 0
```

## `lib/core.brs`

### Numeric Helpers

| Function | Signature | Description |
|----------|-----------|-------------|
| `inc` | `(inc n)` | `n + 1` |
| `dec` | `(dec n)` | `n - 1` |
| `zero?` | `(zero? n)` | `true` if `n == 0` |
| `pos?` | `(pos? n)` | `true` if `n > 0` |
| `neg?` | `(neg? n)` | `true` if `n < 0` |
| `even?` | `(even? n)` | `true` if `n` is even |
| `odd?` | `(odd? n)` | `true` if `n` is odd |
| `abs` | `(abs n)` | Absolute value |
| `max` | `(max a b)` | Maximum of two numbers |
| `min` | `(min a b)` | Minimum of two numbers |
| `sqrt` | `(sqrt n)` | Integer square root (0 for n ≤ 0) |
| `pow` | `(pow base exp)` | `base^exp` via libm |

### Vector Helpers

| Function | Signature | Description |
|----------|-----------|-------------|
| `empty?` | `(empty? vec)` | `true` if vector has 0 elements |
| `nth` | `(nth vec idx)` | Element at index |
| `first` | `(first vec)` | First element |

### Range

| Function | Signature | Description |
|----------|-----------|-------------|
| `range` | `(range start end)` | Vector `[start, ..., end-1]` |
| `range-step` | `(range-step start end step)` | Range with custom step |

```clojure
(range 1 5)        ;; [1 2 3 4]
(range-step 0 10 2) ;; [0 2 4 6 8]
```

### Sequence Ops

Self-host HIR desugars (also in the C backend):

| Function | Signature | Description |
|----------|-----------|-------------|
| `take` / `drop` | `(take n coll)` | First n / all but first n elements |
| `take-while` / `drop-while` | `(take-while pred coll)` | Prefix/suffix by predicate |
| `reverse` | `(reverse coll)` | New vector, back-to-front |
| `concat` | `(concat a b …)` | Fresh vector with all elements, variadic |
| `distinct` | `(distinct coll)` | First occurrence of each element, order kept |
| `interpose` | `(interpose sep coll)` | `sep` between elements |
| `partition` | `(partition n coll)` | Vector of n-sized chunks (tail dropped) |
| `frequencies` | `(frequencies coll)` | Map element → occurrence count |
| `sort` | `(sort coll)` / `(sort cmp coll)` | Fresh vector; default `<` or custom comes-before fn |
| `str-upper` / `str-lower` | `(str-upper s)` | ASCII case map |
| `str-includes?` | `(str-includes? s sub)` | `1` if substring present, else `0` |
| `group-by` | `(group-by f coll)` | Map `(f x)` → vector of matching elems |
| `zipmap` | `(zipmap ks vs)` | Map from keys to values (stops at shorter) |
| `select-keys` | `(select-keys m ks)` | Sub-map with only the present keys |
| `mapcat` | `(mapcat f coll)` | `(f x)` vectors, concatenated |
| `keep` | `(keep f coll)` | Non-0 `(f x)` results only |
| `flatten` | `(flatten coll)` | Deep flatten (runtime, order kept) |
| `get-in` | `(get-in coll ks)` | Walk a key/index path (maps + vectors) |
| `update` | `(update m k f)` | `map-set m k (f (map-get m k))` |
| `sort-by` | `(sort-by f coll)` | Sort ascending by `(f elem)` |
| `merge` | `(merge a b …)` | Clone of first + others' keys (later wins) |
| `dissoc` | `(dissoc m k …)` | Clone without the keys |
| `assoc-in` | `(assoc-in m ks v)` | Nested assoc (intermediate maps cloned) |
| `update-in` | `(update-in m ks f)` | `assoc-in` with `(f (get-in m ks))` |
| `reduce-kv` | `(reduce-kv f init m)` | Fold `(f acc k v)` over entries |
| `keys` / `vals` | `(keys m)` | Aliases of `map-keys` / `map-values` |
| `map-delete` | `(map-delete m k)` | Remove key in place; returns the map |
| `vector-set` | `(vector-set vec i v)` | Set index in place; returns the vector |

### Boolean Helpers

| Function | Signature | Description |
|----------|-----------|-------------|
| `or` | `(or a b)` | Logical OR |
| `and` | `(and a b)` | Logical AND |

## `lib/math.brs`

| Function | Signature | Description |
|----------|-----------|-------------|
| `square` | `(square n)` | `n * n` |
| `cube` | `(cube n)` | `n * n * n` |
| `gcd` | `(gcd a b)` | Greatest common divisor |
| `lcm` | `(lcm a b)` | Least common multiple |
| `factorial` | `(factorial n)` | `n!` |
| `fib` | `(fib n)` | `n`-th Fibonacci number |
| `sum` | `(sum vec)` | Sum of vector elements |
| `product` | `(product vec)` | Product of vector elements |

## `lib/vector.brs`

| Function | Signature | Description |
|----------|-----------|-------------|
| `last` | `(last vec)` | Last element (or `0` if empty) |
| `rest` | `(rest vec)` | All elements except first |
| `take` | `(take vec n)` | First `n` elements |
| `drop` | `(drop vec n)` | Elements from index `n` to end |
| `reverse` | `(reverse vec)` | Reversed vector |
| `contains?` | `(contains? vec val)` | `true` if vector contains value |
| `index-of` | `(index-of vec val)` | First index of value, or `-1` |

## `lib/string.brs`

| Function | Signature | Description |
|----------|-----------|-------------|
| `str-empty?` | `(str-empty? s)` | `true` if string is empty |
| `str-count` | `(str-count s)` | Length of string |
| `str-replace` | `(str-replace s from to)` | New string with all occurrences of `from` replaced by `to` |

## Phase 14.1 modules

Load with `(require "lib/io" :as io)` (etc.). Backed by C runtime primitives where needed.

### `lib/io.brs` — File I/O

| Function | Description |
|----------|-------------|
| `exists?` | Path exists |
| `mtime` | Unix mtime seconds (0 if missing) |
| `delete` | Unlink path |
| `read-file` | Slurp whole file (0 if missing) |
| `write-file` | Overwrite file; returns bytes written |
| `append-file` | Append; returns bytes written |

### `lib/time.brs` — Time

| Function | Description |
|----------|-------------|
| `now` | Unix seconds |
| `now-ms` | Unix milliseconds |
| `sleep-ms` | Sleep |
| `elapsed-ms` | `now-ms - start` |

### `lib/random.brs` — Random

| Function | Description |
|----------|-------------|
| `seed!` | Seed libc `rand` |
| `raw` | Raw `rand()` |
| `rand-int` | Integer in `[0, n)` |
| `rand-range` | Inclusive `[lo, hi]` |

### `lib/regex.brs` — POSIX ERE

| Function | Description |
|----------|-------------|
| `matches?` | Full-string match |
| `find` | Start index of first match, or `-1` |
| `contains?` | Pattern occurs anywhere |

### `lib/json.brs` — JSON (integers)

Tagged values: `[0]` null, `[1 b]` bool, `[2 n]` number, `[3 s]` string,
`[4 elems]` array, `[5 pairs]` object (`pairs` = vector of `[key val]`).

| Function | Description |
|----------|-------------|
| `j-null` / `j-bool` / `j-num` / `j-str` / `j-arr` / `j-obj` | Constructors |
| `parse` | String → tagged value (or `0` on error) |
| `stringify` | Tagged value → JSON string |

### `lib/args.brs` — CLI helpers

| Function | Description |
|----------|-------------|
| `count-args` / `get-arg` | `argv` length / element |
| `has-flag?` | Exact flag present |
| `flag-value` | Token after flag |
| `positionals` | Non-flag args |

### `lib/net.brs` — TCP sockets (Phase 14.7)

Sync TCP over the C runtime. File descriptors are `i64` (`-1` = error).

| Function | Description |
|----------|-------------|
| `connect` | `(net/connect host port)` → fd or `-1` |
| `listen` | `(net/listen port)` → listen fd or `-1` |
| `accept` | `(net/accept listen-fd)` → client fd or `-1` |
| `send` | `(net/send fd data)` → bytes sent or `-1` |
| `recv` | `(net/recv fd max-len)` → string, `0` on error, `""` on EOF |
| `close` | `(net/close fd)` → `0` ok |
| `ok?` | `(net/ok? fd)` → true if `fd >= 0` |

```bash
./bars-self examples/net_echo_server.brs /tmp/srv
./bars-self examples/net_client.brs /tmp/cli
/tmp/srv &   # listens on 18765
/tmp/cli     # → ping
```

### `lib/kw.brs` — Keyword-arg helpers (Phase 17.3c)

Use with the compiler built-in `(kwargs :k v …)` → flat vector of string keys.

| Function | Description |
|----------|-------------|
| `lookup` | Value for key, or `0` if missing |
| `lookup-or` | Value or default |
| `has?` | Key present? |
| `count-pairs` | Number of pairs |

### `lib/crypto.brs` — SHA-256 (Phase 17.3)

SHA-256 in the C runtime; lowercase hex digest as a string.

```clojure
(require "lib/crypto" :as crypto)
(crypto/sha256 "abc")
;; → "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
```

### `lib/http_server.brs` — HTTP/1.1 server helpers (Phase 17.4)

Sync one-shot helpers over TCP. Re-exports `listen` / `ok?` / `close` / `send` /
`recv` so a single `(require "lib/http_server" :as hs)` is enough.

Request vector: `[method path body]`. Response: full HTTP message string.

| Function | Description |
|----------|-------------|
| `parse-request` | Raw bytes → request or `0` |
| `method` / `path` / `body` | Accessors |
| `method-eq?` / `path-eq?` | String equality helpers |
| `ok` / `not-found` / `bad-request` / … | Response builders |
| `accept-request` | From listen fd → `[client req]` |
| `reply` | Send response + close client |
| `serve-once` | Listen, one client, fixed response |

See `examples/http_server_route.brs`.

### `lib/http.brs` — HTTP/1.1 client (Phase 15.1)

Pure Bars client on top of `lib/net`. Sync only; **no TLS**.

Response is a vector `[status-code body-string]`, or `0` on connect/send failure.

| Function | Description |
|----------|-------------|
| `request` | `(http/request method host port path body)` |
| `get-req` | GET (named so it does not shadow vector `get`) |
| `post` | POST with body string |
| `status` / `body` | Accessors on a response vector |
| `ok?` | Status in `200..299` |

```bash
./bars-self examples/http_server.brs /tmp/hs
./bars-self examples/http_client.brs /tmp/hc
/tmp/hs &    # :18766
/tmp/hc      # → 200 / hello
```

## `lib/map.brs`

| Function | Signature | Description |
|----------|-----------|-------------|
| `map-empty?` | `(map-empty? m)` | `true` if map has 0 entries |
| `map-has?` | `(map-has? m key)` | `true` if key exists in map |

## `lib/test.brs` — Test framework (Phase 17.1)

Context-based suite (works with `bars-self`; no user `defmacro` needed).

```clojure
(require "lib/test" :as t)

(t/deftest test-math
  (do
    (t/is ctx (= (+ 1 2) 3) "add")
    (t/is-eq ctx 42 (* 6 7) "mul")))

(defn main []
  (let [ctx (t/suite "math")]
    (test-math ctx)
    (t/finish ctx)))   ;; exit 1 if any failure
```

| Function / macro | Description |
|------------------|-------------|
| `deftest` | Macro: `(deftest name body)` → `(defn name [ctx] body)` |
| `make` / `suite` | Fresh context; `suite` also prints `=== name` |
| `section` | Print `-- name` (no counters) |
| `is` | `(is ctx ok msg)` — pass/fail + counters |
| `is-eq` | Equality; prints expected/actual on fail |
| `is-not` / `is-truthy` / `is-zero` | Variants |
| `passed` / `failed` / `total` | Counters |
| `report` | Print summary; return failed count |
| `finish` | `report` + `exit 1` if failed |
| `assert` | Soft one-shot OK/FAIL (no suite) |
| `assert!` | Hard fail: print + `exit 1` |

See `examples/test_demo.brs`, `examples/deftest_demo.brs`.

## Higher-Order Functions (`map` / `filter` / `reduce`)

Built into the compiler (HIR desugar → `loop`/`recur`). Work on **host and
`bars-self`** (LLVM/C/WASM), with named functions or `(fn […] …)` lambdas.

| Form | Meaning |
|------|---------|
| `(map f vec)` | New vector of `(f x)` for each element |
| `(filter pred vec)` | Elements where `pred` is truthy |
| `(reduce f init vec)` | Fold left: `(f acc x)` |

```clojure
(map inc [1 2 3])                 ;; → vector length 3
(filter even? [1 2 3 4])          ;; → [2 4]
(reduce add 0 [1 2 3 4 5])        ;; → 15
(map (fn [x] (* x 2)) [1 2 3])    ;; lambda OK
```

**Note:** zero-arg `(map)` is still the **hash-map** constructor.
