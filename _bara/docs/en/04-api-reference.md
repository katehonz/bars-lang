
[← Back to Index](index.md)

---

# REPL API Reference

## JSON REPL Protocol

Start the JSON REPL:
```bash
cljnim repl --json
```

The REPL reads one JSON object per line and responds with one JSON object per line.

## Operations

### `eval`
Evaluate a single Clojure form.

**Request:**
```json
{"op": "eval", "form": "(+ 1 2 3)"}
```

**Response (success):**
```json
{
  "status": "ok",
  "result": {
    "type": "unknown",
    "value": "6",
    "printed": "6"
  },
  "meta": {
    "ns": "user",
    "ms": 861.5,
    "form": "(+ 1 2 3)"
  }
}
```

**Response (error):**
```json
{
  "status": "error",
  "error": {
    "type": "reader/error",
    "message": "Unterminated list",
    "form": "( + 1 2"
  },
  "meta": {
    "ns": "user",
    "ms": 0.1
  }
}
```

**Optional fields:**
- `request-id` — Correlation ID, echoed in the response
- `ns` — Target namespace (default: `"user"`)

---

### `eval-batch`
Evaluate multiple forms in sequence.

**Request:**
```json
{"op": "eval-batch", "forms": ["(defn f [x] x)", "(f 42)"]}
```

**Response:**
```json
{
  "status": "ok",
  "results": [
    {"status": "ok", "result": {"type": "var", "name": "f", ...}},
    {"status": "ok", "result": {"printed": "42"}, ...}
  ]
}
```

---

### `get-defs`
List all vars defined in the current session.

**Request:**
```json
{"op": "get-defs"}
```

**Response:**
```json
{"status": "ok", "defs": ["add", "square"], "ns": "user"}
```

---

### `clear`
Clear all session definitions.

**Request:**
```json
{"op": "clear"}
```

**Response:**
```json
{"status": "ok", "cleared": true}
```

---

### `quit`
Exit the REPL.

**Request:**
```json
{"op": "quit"}
```

**Response:**
```json
{"status": "ok", "bye": true}
```

## Response Schema

All responses contain:
- `status` — `"ok"` or `"error"`

On success:
- `result` — Evaluation result object
  - `type` — `"var"`, `"unknown"`, etc.
  - `printed` — String representation of the result
- `meta` — Metadata
  - `ns` — Current namespace
  - `ms` — Execution time in milliseconds
  - `form` — Original form (if `eval`)

On error:
- `error` — Error object
  - `type` — Error category
  - `message` — Human-readable message
- `meta` — Same as success

## File Operations (from Clojure code)

| Function | Example | Returns |
|---|---|---|
| `file/read` | `(file/read "path")` | String content or error map |
| `file/write` | `(file/write "path" "content")` | `true` or error map |
| `file/append` | `(file/append "path" "more")` | `true` or error map |
| `file/ls` | `(file/ls "dir")` | Vector of filenames |
| `file/exists?` | `(file/exists? "path")` | `true` / `false` |

## Git Operations (from Clojure code)

| Function | Example | Returns |
|---|---|---|
| `git/status` | `(git/status)` | Map with `:branch`, `:modified`, `:untracked`, `:staged`, `:clean` |
| `git/commit` | `(git/commit "msg")` | Map with `:sha`, `:success` |
| `git/push` | `(git/push)` | Map with `:success`, `:output` |
| `git/diff` | `(git/diff)` | Diff string |
| `git/log` | `(git/log)` or `(git/log 10)` | Vector of commit strings |

## Human REPL Commands

In human mode (`cljnim repl`):

| Command | Description |
|---|---|
| `:quit`, `:q` | Exit REPL |
| `:help`, `:h` | Show help |
| `:defs` | List defined vars |
| `:clear` | Clear definitions |
| `:ns` | Show current namespace |
