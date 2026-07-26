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
| `push` | `(push vec val)` | Append value to vector |
| `get` | `(get vec idx)` | Element at index (0-based) |
| `count` | `(count vec)` | Number of elements |

Vectors can be nested:

```clojure
(def v [1 [2 3] 4])
(println (get (get v 1) 0))  ;; → 2
```

### Maps

| Function | Signature | Description |
|----------|-----------|-------------|
| `map` | `(map)` | Create empty map |
| `map-set` | `(map-set m key val)` | Set key-value pair |
| `map-get` | `(map-get m key)` | Get value by key |
| `map-count` | `(map-count m)` | Number of entries |

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
| `set` | `(set)` | Create empty set |
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

## `lib/map.brs`

| Function | Signature | Description |
|----------|-----------|-------------|
| `map-empty?` | `(map-empty? m)` | `true` if map has 0 entries |
| `map-has?` | `(map-has? m key)` | `true` if key exists in map |

## Higher-Order Functions (REPL/Cranelift Only)

The AOT backend does not yet support function pointers, so `map-vec`, `filter-vec`, and `reduce-vec` are commented out in `lib/core.brs`. They work in the Cranelift JIT REPL.
