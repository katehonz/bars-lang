[← Back to Index](index.md)

# AI-First Design Philosophy

## Why AI-First?

Modern software development is increasingly done by **AI agents** operating in terminal environments. These agents do not use GUIs, IDEs, or syntax highlighting. They need:

1. **Structured I/O** — JSON/EDN, not plain text
2. **Programmatic Control** — Every operation must be scriptable
3. **Self-Describing Systems** — AI can discover capabilities at runtime
4. **Git Integration** — Version control as part of the workflow

## Principles

### 1. Structured I/O

All REPL communication uses JSON:

```json
// Input
{"op": "eval", "form": "(+ 1 2)", "request-id": "uuid"}

// Output
{
  "status": "ok",
  "request-id": "uuid",
  "result": {"type": "int", "value": 3, "printed": "3"},
  "meta": {"ms": 0.5, "ns": "user"}
}
```

### 2. Batch Operations

AI agents evaluate multiple forms at once:

```json
{"op": "eval-batch",
 "forms": [
   "(defn add [a b] (+ a b))",
   "(add 10 20)"
 ]}
```

### 3. Session Persistence

Definitions persist within a REPL session, allowing incremental development:

```json
{"op": "eval", "form": "(defn square [x] (* x x))"}
{"op": "eval", "form": "(square 5)"}
{"op": "get-defs"}
```

### 4. Error Recovery

All errors are structured with type, message, and context:

```json
{
  "status": "error",
  "error": {
    "type": "compiler/unknown-symbol",
    "symbol": "unknwon-fn",
    "message": "Unknown symbol: unknwon-fn",
    "form": "(unknwon-fn 1 2)"
  }
}
```

## AI Workflow

```bash
# 1. Clone repo
git clone git@gitlab.com:balvatar/lisp-nim.git
cd lisp-nim

# 2. Start AI REPL
cljnim repl --json

# 3. AI evaluates forms, gets structured responses
# 4. AI writes files via (file/write ...) [future]
# 5. AI commits via (git/commit ...) [future]
# 6. AI pushes via (git/push) [future]
```

## Comparison

| Aspect | Human IDE | AI Terminal |
|---|---|---|
| Interface | GUI + mouse | Text + commands |
| Navigation | Clicking | `(apropos ...)`, `(doc ...)` |
| Refactoring | Manual | Batch eval + git diff |
| Testing | Run button | `(run-tests)` structured response |
| Commit | GUI dialog | `(git/commit "msg")` |

## Future: Tool-Call Format

Direct integration with AI frameworks:

```json
{
  "tool": "cljnim/eval",
  "arguments": {
    "code": "(defn fib [n] ...)",
    "mode": "compile"
  }
}
```
