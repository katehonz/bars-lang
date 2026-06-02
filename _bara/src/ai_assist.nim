# AI Assistance for Bara Lang Compiler
# Supports DeepSeek API and OpenAI-compatible APIs (Xiaomi MiMo, etc.)
# API keys are read from environment variables — never hardcoded.

import std/[httpclient, json, os, strutils, uri, tables, times]

type
  AiProvider* = enum
    aiDeepSeek
    aiOpenAiCompatible

  AiConfig* = object
    provider*: AiProvider
    apiKey*: string
    baseUrl*: string
    model*: string
    timeoutMs*: int

  AiResponse* = object
    ok*: bool
    suggestion*: string
    rawJson*: string

proc detectConfig*(): AiConfig =
  ## Auto-detect AI configuration from environment variables
  result.timeoutMs = 15000

  # DeepSeek
  let deepseekKey = getEnv("DEEPSEEK_API_KEY", "")
  if deepseekKey.len > 0:
    return AiConfig(
      provider: aiDeepSeek,
      apiKey: deepseekKey,
      baseUrl: "https://api.deepseek.com",
      model: getEnv("DEEPSEEK_MODEL", "deepseek-chat"),
      timeoutMs: parseInt(getEnv("AI_TIMEOUT_MS", "15000"))
    )

  # OpenAI-compatible (Xiaomi MiMo, OpenRouter, etc.)
  let openaiKey = getEnv("OPENAI_API_KEY", "")
  if openaiKey.len > 0:
    return AiConfig(
      provider: aiOpenAiCompatible,
      apiKey: openaiKey,
      baseUrl: getEnv("OPENAI_BASE_URL", "https://api.openai.com"),
      model: getEnv("OPENAI_MODEL", "gpt-4o-mini"),
      timeoutMs: parseInt(getEnv("AI_TIMEOUT_MS", "15000"))
    )

  # Xiaomi MiMo (OpenAI-compatible)
  let mimoKey = getEnv("MIMO_API_KEY", "")
  if mimoKey.len > 0:
    return AiConfig(
      provider: aiOpenAiCompatible,
      apiKey: mimoKey,
      baseUrl: getEnv("MIMO_BASE_URL", "https://api.mi-mo.ai"),
      model: getEnv("MIMO_MODEL", "mimo-chat"),
      timeoutMs: parseInt(getEnv("AI_TIMEOUT_MS", "15000"))
    )

  # No API key found
  return AiConfig(provider: aiDeepSeek, apiKey: "", baseUrl: "", model: "", timeoutMs: 0)

proc hasAiConfig*(): bool =
  detectConfig().apiKey.len > 0

type
  ErrorCacheEntry = object
    suggestion: string
    timestamp: float64

var errorCache = initTable[string, ErrorCacheEntry]()
var errorCacheMaxSize = 50

proc errorCacheKey(errorMsg, fileName: string): string =
  result = fileName & "::" & errorMsg
  if result.len > 200:
    result = result[0..199]

proc cacheError*(errorMsg, fileName: string, suggestion: string) =
  if errorCache.len >= errorCacheMaxSize:
    errorCache.clear()
  errorCache[errorCacheKey(errorMsg, fileName)] = ErrorCacheEntry(
    suggestion: suggestion,
    timestamp: epochTime()
  )

proc getCachedError*(errorMsg, fileName: string): string =
  let key = errorCacheKey(errorMsg, fileName)
  if key in errorCache:
    let entry = errorCache[key]
    if epochTime() - entry.timestamp < 3600.0:
      return entry.suggestion
  return ""

proc buildErrorPrompt*(errorMsg, sourceCode, fileName: string): string =
  ## Build a prompt for the AI to analyze a compiler error
  result = """You are an expert Bara Lang compiler assistant. The user got a compilation error.

**File:** """ & fileName & """

**Source code:**
```clojure
""" & sourceCode & """
```

**Compiler error:**
```
""" & errorMsg & """
```

Please explain the error in simple terms and suggest a fix. Keep your response under 200 words.
If the error is in Bara Lang code, show the corrected Bara Lang snippet.
Respond in the same language as the user's source code comments (Bulgarian or English).
"""

proc buildGenerationPrompt*(description: string): string =
  ## Build a prompt for AI code generation
  result = """You are an expert Bara Lang programmer. Generate a Bara Lang function based on this description:

""" & description & """

Requirements:
- Use idiomatic Bara Lang
- Include docstring
- Use loop/recur instead of recursion if possible
- Return ONLY the Bara Lang code, no explanations
"""

proc buildOptimizationPrompt*(code: string): string =
  ## Build a prompt for AI optimization suggestions
  result = """You are an expert Clojure performance engineer. Analyze this Clojure code and suggest optimizations:

```clojure
""" & code & """
```

Consider:
- SIMD/vectorization opportunities
- loop/recur vs recursion
- Persistent data structure usage
- Transients for batch operations
- Parallelization opportunities (pmap, reducers)

Keep response under 200 words. Return ONLY Bara Lang code suggestions, no explanations.
"""

proc buildDebugPrompt*(code: string, evalResult: string): string =
  ## Build a prompt for AI debugging analysis
  result = """You are an expert Clojure debugger. Analyze this Clojure expression and its result:

**Expression:**
```clojure
""" & code & """
```

**Result:**
```
""" & evalResult & """
```

Explain what happened step by step. If there's a bug or unexpected behavior, explain why.
Keep response under 200 words.
Respond in the same language as the user's source code comments (Bulgarian or English).
"""

proc callAiApi*(config: AiConfig, prompt: string): AiResponse =
  ## Call the AI API and return the response
  if config.apiKey.len == 0:
    return AiResponse(ok: false, suggestion: "No AI API key configured. Set DEEPSEEK_API_KEY, OPENAI_API_KEY, or MIMO_API_KEY environment variable.")

  let client = newHttpClient(timeout = config.timeoutMs)
  defer: client.close()

  let url = config.baseUrl & "/v1/chat/completions"
  let body = %*{
    "model": config.model,
    "messages": [
      {"role": "user", "content": prompt}
    ],
    "temperature": 0.3,
    "max_tokens": 800
  }

  client.headers["Authorization"] = "Bearer " & config.apiKey
  client.headers["Content-Type"] = "application/json"

  try:
    let resp = client.post(url, body = $body)
    let respBody = resp.body
    result.rawJson = respBody

    if resp.code.int != 200:
      return AiResponse(ok: false, suggestion: "AI API error (HTTP " & $resp.code.int & "): " & respBody)

    let jsonResp = parseJson(respBody)
    if jsonResp.hasKey("choices") and jsonResp["choices"].len > 0:
      let content = jsonResp["choices"][0]["message"]["content"].getStr("")
      return AiResponse(ok: true, suggestion: content, rawJson: respBody)
    else:
      return AiResponse(ok: false, suggestion: "Unexpected AI API response format", rawJson: respBody)

  except CatchableError as e:
    return AiResponse(ok: false, suggestion: "AI request failed: " & e.msg)

proc explainError*(errorMsg, sourceCode, fileName: string): AiResponse =
  ## High-level helper: explain a compiler error using AI
  let cached = getCachedError(errorMsg, fileName)
  if cached.len > 0:
    return AiResponse(ok: true, suggestion: cached)
  let config = detectConfig()
  let prompt = buildErrorPrompt(errorMsg, sourceCode, fileName)
  let res = callAiApi(config, prompt)
  if res.ok:
    cacheError(errorMsg, fileName, res.suggestion)
  return res

proc generateCode*(description: string): AiResponse =
  ## High-level helper: generate Bara Lang code from description
  let config = detectConfig()
  let prompt = buildGenerationPrompt(description)
  return callAiApi(config, prompt)

proc optimizeCode*(code: string): AiResponse =
  ## High-level helper: suggest optimizations for Bara Lang code
  let config = detectConfig()
  let prompt = buildOptimizationPrompt(code)
  return callAiApi(config, prompt)

proc debugCode*(code: string, evalResult: string): AiResponse =
  ## High-level helper: debug a Bara Lang expression and its result
  let config = detectConfig()
  let prompt = buildDebugPrompt(code, evalResult)
  return callAiApi(config, prompt)

proc formatSuggestion*(response: AiResponse): string =
  ## Format AI response for terminal display
  if not response.ok:
    return "💡 AI: " & response.suggestion

  var res = "💡 AI Suggestion:\n"
  for line in response.suggestion.splitLines():
    res.add("   " & line & "\n")
  return res
