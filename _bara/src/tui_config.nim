# TUI Configuration Manager
# Handles persistent config in ~/.config/cljnim/config.json

import std/[json, os, strutils]
import ai_assist

type
  TuiConfig* = object
    provider*: string      # "deepseek", "openai", "mimo", "custom"
    model*: string
    baseUrl*: string
    apiKey*: string
    timeoutMs*: int
    lastFile*: string      # last used .clj file

const
  DefaultProviders = {
    "deepseek": ("https://api.deepseek.com", "deepseek-chat"),
    "openai": ("https://api.openai.com", "gpt-4o-mini"),
    "mimo": ("https://api.mi-mo.ai", "mimo-chat"),
    "custom": ("", "")
  }

proc configDir(): string =
  getHomeDir() / ".config" / "cljnim"

proc configPath(): string =
  configDir() / "config.json"

proc defaultConfig*(): TuiConfig =
  result.provider = "deepseek"
  result.model = "deepseek-chat"
  result.baseUrl = "https://api.deepseek.com"
  result.apiKey = ""
  result.timeoutMs = 15000
  result.lastFile = ""

proc loadConfig*(): TuiConfig =
  let path = configPath()
  if not fileExists(path):
    return defaultConfig()
  try:
    let jsonStr = readFile(path)
    let j = parseJson(jsonStr)
    result.provider = j{"provider"}.getStr("deepseek")
    result.model = j{"model"}.getStr("deepseek-chat")
    result.baseUrl = j{"baseUrl"}.getStr("https://api.deepseek.com")
    result.apiKey = j{"apiKey"}.getStr("")
    result.timeoutMs = j{"timeoutMs"}.getInt(15000)
    result.lastFile = j{"lastFile"}.getStr("")
  except:
    result = defaultConfig()

proc saveConfig*(cfg: TuiConfig) =
  let dir = configDir()
  if not dirExists(dir):
    createDir(dir)
  let j = %*{
    "provider": cfg.provider,
    "model": cfg.model,
    "baseUrl": cfg.baseUrl,
    "apiKey": cfg.apiKey,
    "timeoutMs": cfg.timeoutMs,
    "lastFile": cfg.lastFile
  }
  writeFile(configPath(), pretty(j))

proc toAiConfig*(cfg: TuiConfig): AiConfig =
  ## Convert TUI config to AiConfig for ai_assist module
  result.apiKey = cfg.apiKey
  result.baseUrl = cfg.baseUrl
  result.model = cfg.model
  result.timeoutMs = cfg.timeoutMs
  if cfg.provider == "deepseek":
    result.provider = aiDeepSeek
  else:
    result.provider = aiOpenAiCompatible

proc fromAiConfig*(cfg: AiConfig): TuiConfig =
  ## Convert AiConfig to TUI config
  result.apiKey = cfg.apiKey
  result.baseUrl = cfg.baseUrl
  result.model = cfg.model
  result.timeoutMs = cfg.timeoutMs
  if cfg.provider == aiDeepSeek:
    result.provider = "deepseek"
  else:
    result.provider = "openai"

proc isValid*(cfg: TuiConfig): bool =
  cfg.apiKey.len > 0 and cfg.baseUrl.len > 0 and cfg.model.len > 0

proc providerDefaults*(provider: string): tuple[baseUrl, model: string] =
  for i in 0..<DefaultProviders.len:
    if DefaultProviders[i][0] == provider:
      return DefaultProviders[i][1]
  return ("", "")

proc cycleProvider*(current: string, direction: int): string =
  let providers = @["deepseek", "openai", "mimo", "custom"]
  var idx = providers.find(current)
  if idx < 0: idx = 0
  idx = (idx + direction + providers.len) mod providers.len
  return providers[idx]

proc maskedKey*(cfg: TuiConfig): string =
  if cfg.apiKey.len <= 4:
    return ""
  return "*".repeat(cfg.apiKey.len - 4) & cfg.apiKey[^4..^1]
