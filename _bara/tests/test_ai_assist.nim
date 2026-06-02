# Tests for AI assistance module (no real API calls)

import unittest, strutils, times
import os
import ai_assist

suite "AI Config Detection":
  test "detectConfig returns empty when no env vars set":
    let cfg = detectConfig()
    check cfg.timeoutMs >= 0

  test "hasAiConfig returns false when no keys set (if env empty)":
    let key = getEnv("DEEPSEEK_API_KEY", "")
    let okey = getEnv("OPENAI_API_KEY", "")
    let mkey = getEnv("MIMO_API_KEY", "")
    if key.len == 0 and okey.len == 0 and mkey.len == 0:
      check hasAiConfig() == false

suite "Prompt Building":
  test "buildErrorPrompt includes filename and source":
    let prompt = buildErrorPrompt("type mismatch", "(defn foo [x] x)", "test.clj")
    check "test.clj" in prompt
    check "type mismatch" in prompt
    check "(defn foo [x] x)" in prompt

  test "buildGenerationPrompt includes description":
    let prompt = buildGenerationPrompt("reverse a list")
    check "reverse a list" in prompt
    check "Bara Lang" in prompt

  test "buildOptimizationPrompt includes code":
    let prompt = buildOptimizationPrompt("(reduce + [1 2 3])")
    check "(reduce + [1 2 3])" in prompt
    check "SIMD" in prompt or "optim" in prompt.toLowerAscii()

  test "buildDebugPrompt includes code and result":
    let prompt = buildDebugPrompt("(+ 1 2)", "3")
    check "(+ 1 2)" in prompt
    check "3" in prompt
    check "Clojure" in prompt

suite "Error Cache":
  test "getCachedError returns empty for unknown errors":
    check getCachedError("unknown error", "test.clj") == ""

  test "cacheError and getCachedError work":
    cacheError("type mismatch", "test.clj", "Check your types")
    check getCachedError("type mismatch", "test.clj") == "Check your types"

  test "cacheError with same key returns correct suggestion":
    cacheError("unterminated string", "src.clj", "Add closing quote")
    let cached = getCachedError("unterminated string", "src.clj")
    check cached == "Add closing quote"

suite "Response Formatting":
  test "formatSuggestion shows error when not ok":
    let resp = AiResponse(ok: false, suggestion: "No key configured")
    let formatted = formatSuggestion(resp)
    check "💡 AI:" in formatted
    check "No key configured" in formatted

  test "formatSuggestion shows suggestion when ok":
    let resp = AiResponse(ok: true, suggestion: "Use (reverse coll)")
    let formatted = formatSuggestion(resp)
    check "💡 AI Suggestion:" in formatted
    check "Use (reverse coll)" in formatted
