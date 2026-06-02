# TUI Screens for cljnim
# All UI screens: Main Menu, AI Settings, Compile, Run, Generate, Help

import std/[os, strutils, osproc]
import illwill
import tui_config, ai_assist

type
  ScreenType* = enum
    stMainMenu, stAiSettings, stCompile, stRun, stAiGenerate, stHelp, stRepl

  InputField* = object
    label*: string
    value*: string
    cursorPos*: int
    password*: bool
    active*: bool

  ScreenState* = object
    currentScreen*: ScreenType
    prevScreen*: ScreenType
    menuIndex*: int
    config*: TuiConfig
    configDirty*: bool
    fields*: seq[InputField]
    activeField*: int
    statusMsg*: string
    statusColor*: ForegroundColor
    popupMsg*: string
    popupActive*: bool
    outputText*: seq[string]
    outputScroll*: int
    quit*: bool

proc initState*(cfg: TuiConfig): ScreenState =
  result.currentScreen = stMainMenu
  result.prevScreen = stMainMenu
  result.menuIndex = 0
  result.config = cfg
  result.configDirty = false
  result.activeField = 0
  result.statusMsg = "Ready"
  result.statusColor = fgGreen
  result.popupMsg = ""
  result.popupActive = false
  result.outputText = @[]
  result.outputScroll = 0
  result.quit = false

const
  MenuItems = @[
    "Compile .clj → .nim",
    "Run .clj file",
    "Start REPL",
    "AI Code Generator",
    "AI Settings",
    "Help",
    "Exit"
  ]

# ─── Helpers ─────────────────────────────────────────────────────────

proc centerX(text: string, width: int): int =
  max(0, (width - text.len) div 2)

proc truncate(s: string, maxLen: int): string =
  if s.len <= maxLen: s
  else: s[0..<maxLen-3] & "..."

proc wrapText(text: string, maxWidth: int): seq[string] =
  result = @[]
  for line in text.splitLines():
    if line.len <= maxWidth:
      result.add(line)
    else:
      var i = 0
      while i < line.len:
        let endIdx = min(i + maxWidth, line.len)
        result.add(line[i..<endIdx])
        i = endIdx

proc drawBox(tb: var TerminalBuffer, x1, y1, x2, y2: int, title = "") =
  tb.drawRect(x1, y1, x2, y2)
  if title.len > 0 and title.len < (x2 - x1):
    let tx = centerX(title, x2 - x1 - 1) + x1 + 1
    tb.write(tx, y1, fgCyan, " ", title, " ")

proc drawButton(tb: var TerminalBuffer, x, y: int, label: string, active: bool) =
  if active:
    tb.write(x, y, bgWhite, fgBlack, " ", label, " ", resetStyle)
  else:
    tb.write(x, y, fgWhite, "[", label, "]")

proc drawOutputArea(tb: var TerminalBuffer, x1, y1, x2, y2: int, lines: seq[string], scroll: int) =
  tb.drawRect(x1, y1, x2, y2)
  let visibleHeight = y2 - y1 - 1
  let startIdx = if scroll < 0: max(0, lines.len - visibleHeight) else: scroll
  for i in 0..<visibleHeight:
    let lineIdx = startIdx + i
    if lineIdx < lines.len:
      tb.write(x1 + 1, y1 + 1 + i, fgWhite, truncate(lines[lineIdx], x2 - x1 - 2))
    else:
      tb.write(x1 + 1, y1 + 1 + i, fgBlack, "~")

# ─── Popup ───────────────────────────────────────────────────────────

proc drawPopup*(tb: var TerminalBuffer, state: var ScreenState) =
  if not state.popupActive or state.popupMsg.len == 0: return
  let w = terminalWidth()
  let h = terminalHeight()
  let lines = state.popupMsg.wrapText(w - 8)
  let pw = min(w - 4, 60)
  let ph = lines.len + 4
  let px = max(2, (w - pw) div 2)
  let py = max(2, (h - ph) div 2)

  tb.fill(px, py, px + pw, py + ph, " ")
  tb.drawBox(px, py, px + pw, py + ph, "Message")
  for i, line in lines:
    tb.write(px + 2, py + 2 + i, fgWhite, truncate(line, pw - 4))
  tb.write(px + 2, py + ph - 1, fgYellow, "Press ENTER or ESC to close")

# ─── Main Menu ───────────────────────────────────────────────────────

proc drawMainMenu*(tb: var TerminalBuffer, state: var ScreenState) =
  let w = terminalWidth()
  let h = terminalHeight()

  # Header
  let title = "Bara Lang TUI"
  tb.write(centerX(title, w), 1, fgCyan, title)
  tb.drawHorizLine(0, w - 1, 2, doubleStyle = true)

  # Menu box
  let boxW = 50
  let boxH = MenuItems.len + 6
  let bx = centerX("", boxW)
  let by = max(4, (h - boxH) div 2)
  drawBox(tb, bx, by, bx + boxW, by + boxH, "Main Menu")

  for i, item in MenuItems:
    let y = by + 2 + i
    let arrow = if i == state.menuIndex: ">>> " else: "    "
    let color = if i == state.menuIndex: fgYellow else: fgWhite
    tb.write(bx + 4, y, color, arrow, item)

  # Footer status
  tb.drawHorizLine(0, w - 1, h - 2, doubleStyle = true)
  let aiStatus = if state.config.isValid: state.config.provider & " (configured)" else: "not configured"
  let status = "Status: " & state.statusMsg & " | AI: " & aiStatus
  tb.write(2, h - 1, state.statusColor, truncate(status, w - 4))

proc handleMainMenu*(key: Key, state: var ScreenState) =
  case key
  of Key.Up:
    state.menuIndex = (state.menuIndex - 1 + MenuItems.len) mod MenuItems.len
  of Key.Down:
    state.menuIndex = (state.menuIndex + 1) mod MenuItems.len
  of Key.Enter:
    case state.menuIndex
    of 0:
      state.currentScreen = stCompile
      state.fields = @[InputField(label: "File", value: state.config.lastFile, cursorPos: state.config.lastFile.len, active: true)]
      state.activeField = 0
      state.outputText = @[]
    of 1:
      state.currentScreen = stRun
      state.fields = @[InputField(label: "File", value: state.config.lastFile, cursorPos: state.config.lastFile.len, active: true)]
      state.activeField = 0
      state.outputText = @[]
    of 2: state.currentScreen = stRepl
    of 3:
      state.currentScreen = stAiGenerate
      state.fields = @[InputField(label: "Description", value: "", cursorPos: 0, active: true)]
      state.activeField = 0
      state.outputText = @[]
    of 4:
      state.prevScreen = stMainMenu
      state.currentScreen = stAiSettings
      state.activeField = 0
      state.fields = @[
        InputField(label: "Provider", value: state.config.provider, cursorPos: state.config.provider.len, active: true),
        InputField(label: "Model", value: state.config.model, cursorPos: state.config.model.len, active: false),
        InputField(label: "Base URL", value: state.config.baseUrl, cursorPos: state.config.baseUrl.len, active: false),
        InputField(label: "API Key", value: state.config.apiKey, cursorPos: state.config.apiKey.len, password: true, active: false),
        InputField(label: "Timeout (ms)", value: $state.config.timeoutMs, cursorPos: ($state.config.timeoutMs).len, active: false)
      ]
    of 5: state.currentScreen = stHelp
    of 6: state.quit = true
    else: discard
  of Key.Escape: state.quit = true
  else: discard

# ─── AI Settings ─────────────────────────────────────────────────────

proc drawAiSettings*(tb: var TerminalBuffer, state: var ScreenState) =
  let w = terminalWidth()
  let h = terminalHeight()

  tb.write(centerX("AI Configuration", w), 1, fgCyan, "AI Configuration")
  tb.drawHorizLine(0, w - 1, 2, doubleStyle = true)

  let startY = 4
  let labelW = 14
  for i, f in state.fields:
    let y = startY + i * 2
    let lblColor = if i == state.activeField: fgYellow else: fgWhite
    tb.write(4, y, lblColor, truncate(f.label, labelW) & ":")

    let valX = 4 + labelW + 2
    let valW = min(50, w - valX - 4)
    var display = f.value
    if f.password:
      display = if f.value.len > 4: "*".repeat(f.value.len - 4) & f.value[^4..^1] else: f.value
    display = truncate(display, valW)

    if i == state.activeField:
      tb.write(valX, y, bgWhite, fgBlack, display & " ".repeat(valW - display.len), resetStyle)
    else:
      tb.write(valX, y, fgWhite, display)

  # Provider hint
  if state.activeField == 0:
    let (defaultUrl, defaultModel) = providerDefaults(state.fields[0].value)
    if defaultUrl.len > 0:
      tb.write(4, startY + state.fields.len * 2 + 1, fgBlack, "Defaults: " & defaultUrl & " | " & defaultModel)

  # Buttons
  let btnY = h - 5
  drawButton(tb, 4, btnY, "Save", state.activeField == state.fields.len)
  drawButton(tb, 14, btnY, "Test", state.activeField == state.fields.len + 1)
  drawButton(tb, 26, btnY, "Back", state.activeField == state.fields.len + 2)

  # Footer
  tb.drawHorizLine(0, w - 1, h - 2, doubleStyle = true)
  tb.write(2, h - 1, state.statusColor, truncate(state.statusMsg, w - 4))

proc handleAiSettings*(key: Key, state: var ScreenState) =
  if state.popupActive:
    case key
    of Key.Enter, Key.Escape:
      state.popupActive = false
      state.popupMsg = ""
    else: discard
    return

  let totalFields = state.fields.len + 3  # fields + Save + Test + Back

  case key
  of Key.Up:
    state.activeField = (state.activeField - 1 + totalFields) mod totalFields
  of Key.Down:
    state.activeField = (state.activeField + 1) mod totalFields
  of Key.Tab:
    state.activeField = (state.activeField + 1) mod totalFields
  of Key.Backspace:
    if state.activeField < state.fields.len:
      var f = addr state.fields[state.activeField]
      if f.cursorPos > 0:
        f.value.delete(f.cursorPos - 1 .. f.cursorPos - 1)
        f.cursorPos.dec
  of Key.Left:
    if state.activeField < state.fields.len and state.fields[state.activeField].cursorPos > 0:
      state.fields[state.activeField].cursorPos.dec
  of Key.Right:
    if state.activeField < state.fields.len and state.fields[state.activeField].cursorPos < state.fields[state.activeField].value.len:
      state.fields[state.activeField].cursorPos.inc
  of Key.Enter:
    if state.activeField < state.fields.len:
      state.activeField = (state.activeField + 1) mod totalFields
    elif state.activeField == state.fields.len:  # Save
      state.config.provider = state.fields[0].value
      state.config.model = state.fields[1].value
      state.config.baseUrl = state.fields[2].value
      state.config.apiKey = state.fields[3].value
      try:
        state.config.timeoutMs = parseInt(state.fields[4].value)
      except:
        state.config.timeoutMs = 15000
      saveConfig(state.config)
      state.statusMsg = "Configuration saved!"
      state.statusColor = fgGreen
    elif state.activeField == state.fields.len + 1:  # Test
      let testCfg = TuiConfig(
        provider: state.fields[0].value,
        model: state.fields[1].value,
        baseUrl: state.fields[2].value,
        apiKey: state.fields[3].value,
        timeoutMs: (try: parseInt(state.fields[4].value) except: 15000),
        lastFile: ""
      )
      state.statusMsg = "Testing connection..."
      state.statusColor = fgYellow
      let aiCfg = toAiConfig(testCfg)
      let res = callAiApi(aiCfg, "Say 'OK' if you can read this.")
      if res.ok:
        state.popupMsg = "Connection successful!\nModel: " & testCfg.model & "\nResponse: " & res.suggestion
        state.statusMsg = "Connection OK"
        state.statusColor = fgGreen
      else:
        state.popupMsg = "Connection failed:\n" & res.suggestion
        state.statusMsg = "Connection failed"
        state.statusColor = fgRed
      state.popupActive = true
    else:  # Back
      state.currentScreen = state.prevScreen
      state.statusMsg = "Ready"
      state.statusColor = fgGreen
  of Key.Escape:
    state.currentScreen = state.prevScreen
    state.statusMsg = "Ready"
    state.statusColor = fgGreen
  else:
    if state.activeField < state.fields.len:
      let ch = char(key.ord)
      if ch >= ' ' and ch <= '~':
        var f = addr state.fields[state.activeField]
        f.value.insert($ch, f.cursorPos)
        f.cursorPos.inc
        if state.activeField == 0:
          let (url, model) = providerDefaults(f.value)
          if url.len > 0:
            state.fields[1].value = model
            state.fields[2].value = url
            state.fields[1].cursorPos = model.len
            state.fields[2].cursorPos = url.len
  for i in 0..<state.fields.len:
    state.fields[i].active = (i == state.activeField)

# ─── Compile Screen ──────────────────────────────────────────────────

proc drawCompile*(tb: var TerminalBuffer, state: var ScreenState) =
  let w = terminalWidth()
  let h = terminalHeight()

  tb.write(centerX("Compile to Nim", w), 1, fgCyan, "Compile to Nim")
  tb.drawHorizLine(0, w - 1, 2, doubleStyle = true)

  let valX = 12
  let valW = min(50, w - valX - 4)
  let f = state.fields[0]
  let display = truncate(f.value, valW)
  tb.write(4, 4, fgWhite, "File:")
  if state.activeField == 0:
    tb.write(valX, 4, bgWhite, fgBlack, display & " ".repeat(valW - display.len), resetStyle)
  else:
    tb.write(valX, 4, fgWhite, display)

  # Buttons
  let btnY = 7
  drawButton(tb, 4, btnY, "Compile", state.activeField == 1)
  drawButton(tb, 16, btnY, "Browse", state.activeField == 2)
  drawButton(tb, 28, btnY, "Back", state.activeField == 3)

  # Output
  if state.outputText.len > 0:
    drawOutputArea(tb, 2, 9, w - 2, h - 3, state.outputText, state.outputScroll)

  tb.drawHorizLine(0, w - 1, h - 2, doubleStyle = true)
  tb.write(2, h - 1, state.statusColor, truncate(state.statusMsg, w - 4))

proc handleCompile*(key: Key, state: var ScreenState) =
  if state.popupActive:
    case key
    of Key.Enter, Key.Escape:
      state.popupActive = false
      state.popupMsg = ""
    else: discard
    return

  let totalFields = 4  # file + Compile + Browse + Back
  case key
  of Key.Up:
    state.activeField = (state.activeField - 1 + totalFields) mod totalFields
  of Key.Down:
    state.activeField = (state.activeField + 1) mod totalFields
  of Key.Tab:
    state.activeField = (state.activeField + 1) mod totalFields
  of Key.Backspace:
    if state.activeField == 0 and state.fields[0].cursorPos > 0:
      state.fields[0].value.delete(state.fields[0].cursorPos - 1 .. state.fields[0].cursorPos - 1)
      state.fields[0].cursorPos.dec
  of Key.Left:
    if state.activeField == 0 and state.fields[0].cursorPos > 0:
      state.fields[0].cursorPos.dec
  of Key.Right:
    if state.activeField == 0 and state.fields[0].cursorPos < state.fields[0].value.len:
      state.fields[0].cursorPos.inc
  of Key.Enter:
    if state.activeField == 0:
      state.activeField = 1
    elif state.activeField == 1:  # Compile
      let filePath = state.fields[0].value.strip()
      if filePath.len == 0:
        state.statusMsg = "Please enter a file path"
        state.statusColor = fgRed
      elif not fileExists(filePath):
        state.statusMsg = "File not found: " & filePath
        state.statusColor = fgRed
      else:
        state.config.lastFile = filePath
        saveConfig(state.config)
        state.statusMsg = "Compiling..."
        state.statusColor = fgYellow
        let appDir = getAppDir()
        let cljnimBin = if fileExists(appDir / "cljnim"): appDir / "cljnim" else: "./cljnim"
        let (output, exitCode) = execCmdEx(cljnimBin & " compile " & quoteShell(filePath))
        state.outputText = output.splitLines()
        if exitCode == 0:
          state.statusMsg = "Compilation successful!"
          state.statusColor = fgGreen
        else:
          state.statusMsg = "Compilation failed"
          state.statusColor = fgRed
    elif state.activeField == 2:  # Browse
      state.statusMsg = "Browse not implemented — type path manually"
      state.statusColor = fgYellow
    else:  # Back
      state.currentScreen = stMainMenu
      state.statusMsg = "Ready"
      state.statusColor = fgGreen
  of Key.Escape:
    state.currentScreen = stMainMenu
    state.statusMsg = "Ready"
    state.statusColor = fgGreen
  else:
    if state.activeField == 0:
      let ch = char(key.ord)
      if ch >= ' ' and ch <= '~':
        state.fields[0].value.insert($ch, state.fields[0].cursorPos)
        state.fields[0].cursorPos.inc

# ─── Run Screen ──────────────────────────────────────────────────────

proc drawRun*(tb: var TerminalBuffer, state: var ScreenState) =
  let w = terminalWidth()
  let h = terminalHeight()

  tb.write(centerX("Run Bara Lang File", w), 1, fgCyan, "Run Bara Lang File")
  tb.drawHorizLine(0, w - 1, 2, doubleStyle = true)

  let valX = 12
  let valW = min(50, w - valX - 4)
  let display = truncate(state.fields[0].value, valW)
  tb.write(4, 4, fgWhite, "File:")
  if state.activeField == 0:
    tb.write(valX, 4, bgWhite, fgBlack, display & " ".repeat(valW - display.len), resetStyle)
  else:
    tb.write(valX, 4, fgWhite, display)

  let btnY = 7
  drawButton(tb, 4, btnY, "Run", state.activeField == 1)
  drawButton(tb, 14, btnY, "Browse", state.activeField == 2)
  drawButton(tb, 26, btnY, "Back", state.activeField == 3)

  if state.outputText.len > 0:
    drawOutputArea(tb, 2, 9, w - 2, h - 3, state.outputText, state.outputScroll)

  tb.drawHorizLine(0, w - 1, h - 2, doubleStyle = true)
  tb.write(2, h - 1, state.statusColor, truncate(state.statusMsg, w - 4))

proc handleRun*(key: Key, state: var ScreenState) =
  if state.popupActive:
    case key
    of Key.Enter, Key.Escape:
      state.popupActive = false
      state.popupMsg = ""
    else: discard
    return

  let totalFields = 4
  case key
  of Key.Up:
    state.activeField = (state.activeField - 1 + totalFields) mod totalFields
  of Key.Down:
    state.activeField = (state.activeField + 1) mod totalFields
  of Key.Tab:
    state.activeField = (state.activeField + 1) mod totalFields
  of Key.Backspace:
    if state.activeField == 0 and state.fields[0].cursorPos > 0:
      state.fields[0].value.delete(state.fields[0].cursorPos - 1 .. state.fields[0].cursorPos - 1)
      state.fields[0].cursorPos.dec
  of Key.Left:
    if state.activeField == 0 and state.fields[0].cursorPos > 0:
      state.fields[0].cursorPos.dec
  of Key.Right:
    if state.activeField == 0 and state.fields[0].cursorPos < state.fields[0].value.len:
      state.fields[0].cursorPos.inc
  of Key.Enter:
    if state.activeField == 0:
      state.activeField = 1
    elif state.activeField == 1:  # Run
      let filePath = state.fields[0].value.strip()
      if filePath.len == 0:
        state.statusMsg = "Please enter a file path"
        state.statusColor = fgRed
      elif not fileExists(filePath):
        state.statusMsg = "File not found: " & filePath
        state.statusColor = fgRed
      else:
        state.config.lastFile = filePath
        saveConfig(state.config)
        state.statusMsg = "Running..."
        state.statusColor = fgYellow
        let appDir = getAppDir()
        let cljnimBin = if fileExists(appDir / "cljnim"): appDir / "cljnim" else: "./cljnim"
        let (output, exitCode) = execCmdEx(cljnimBin & " run " & quoteShell(filePath))
        state.outputText = output.splitLines()
        if exitCode == 0:
          state.statusMsg = "Execution successful!"
          state.statusColor = fgGreen
        else:
          state.statusMsg = "Execution failed"
          state.statusColor = fgRed
    elif state.activeField == 2:  # Browse
      state.statusMsg = "Browse not implemented — type path manually"
      state.statusColor = fgYellow
    else:  # Back
      state.currentScreen = stMainMenu
      state.statusMsg = "Ready"
      state.statusColor = fgGreen
  of Key.Escape:
    state.currentScreen = stMainMenu
    state.statusMsg = "Ready"
    state.statusColor = fgGreen
  else:
    if state.activeField == 0:
      let ch = char(key.ord)
      if ch >= ' ' and ch <= '~':
        state.fields[0].value.insert($ch, state.fields[0].cursorPos)
        state.fields[0].cursorPos.inc

# ─── AI Generate Screen ──────────────────────────────────────────────

proc drawAiGenerate*(tb: var TerminalBuffer, state: var ScreenState) =
  let w = terminalWidth()
  let h = terminalHeight()

  tb.write(centerX("AI Code Generator", w), 1, fgCyan, "AI Code Generator")
  tb.drawHorizLine(0, w - 1, 2, doubleStyle = true)

  let valX = 16
  let valW = min(50, w - valX - 4)
  let display = truncate(state.fields[0].value, valW)
  tb.write(4, 4, fgWhite, "Description:")
  if state.activeField == 0:
    tb.write(valX, 4, bgWhite, fgBlack, display & " ".repeat(valW - display.len), resetStyle)
  else:
    tb.write(valX, 4, fgWhite, display)

  let btnY = 7
  drawButton(tb, 4, btnY, "Generate", state.activeField == 1)
  drawButton(tb, 18, btnY, "Copy", state.activeField == 2)
  drawButton(tb, 28, btnY, "Back", state.activeField == 3)

  if state.outputText.len > 0:
    drawOutputArea(tb, 2, 9, w - 2, h - 3, state.outputText, state.outputScroll)

  tb.drawHorizLine(0, w - 1, h - 2, doubleStyle = true)
  tb.write(2, h - 1, state.statusColor, truncate(state.statusMsg, w - 4))

proc handleAiGenerate*(key: Key, state: var ScreenState) =
  if state.popupActive:
    case key
    of Key.Enter, Key.Escape:
      state.popupActive = false
      state.popupMsg = ""
    else: discard
    return

  let totalFields = 4
  case key
  of Key.Up:
    state.activeField = (state.activeField - 1 + totalFields) mod totalFields
  of Key.Down:
    state.activeField = (state.activeField + 1) mod totalFields
  of Key.Tab:
    state.activeField = (state.activeField + 1) mod totalFields
  of Key.Backspace:
    if state.activeField == 0 and state.fields[0].cursorPos > 0:
      state.fields[0].value.delete(state.fields[0].cursorPos - 1 .. state.fields[0].cursorPos - 1)
      state.fields[0].cursorPos.dec
  of Key.Left:
    if state.activeField == 0 and state.fields[0].cursorPos > 0:
      state.fields[0].cursorPos.dec
  of Key.Right:
    if state.activeField == 0 and state.fields[0].cursorPos < state.fields[0].value.len:
      state.fields[0].cursorPos.inc
  of Key.Enter:
    if state.activeField == 0:
      state.activeField = 1
    elif state.activeField == 1:  # Generate
      if not state.config.isValid:
        state.statusMsg = "AI not configured — go to AI Settings"
        state.statusColor = fgRed
      else:
        let desc = state.fields[0].value.strip()
        if desc.len == 0:
          state.statusMsg = "Please enter a description"
          state.statusColor = fgRed
        else:
          state.statusMsg = "Generating..."
          state.statusColor = fgYellow
          let res = generateCode(desc)
          if res.ok:
            state.outputText = res.suggestion.splitLines()
            state.statusMsg = "Code generated!"
            state.statusColor = fgGreen
          else:
            state.outputText = @["Error:", res.suggestion]
            state.statusMsg = "Generation failed"
            state.statusColor = fgRed
    elif state.activeField == 2:  # Copy
      if state.outputText.len > 0:
        let fullText = state.outputText.join("\n")
        # Try to copy to clipboard via xclip/xsel
        let (_, exitCode) = execCmdEx("echo " & quoteShell(fullText) & " | xclip -selection clipboard 2>/dev/null || echo " & quoteShell(fullText) & " | xsel --clipboard --input 2>/dev/null")
        if exitCode == 0:
          state.statusMsg = "Copied to clipboard!"
          state.statusColor = fgGreen
        else:
          state.statusMsg = "Copy failed — install xclip or xsel"
          state.statusColor = fgYellow
    else:  # Back
      state.currentScreen = stMainMenu
      state.statusMsg = "Ready"
      state.statusColor = fgGreen
  of Key.Escape:
    state.currentScreen = stMainMenu
    state.statusMsg = "Ready"
    state.statusColor = fgGreen
  else:
    if state.activeField == 0:
      let ch = char(key.ord)
      if ch >= ' ' and ch <= '~':
        state.fields[0].value.insert($ch, state.fields[0].cursorPos)
        state.fields[0].cursorPos.inc

# ─── Help Screen ─────────────────────────────────────────────────────

proc drawHelp*(tb: var TerminalBuffer, state: var ScreenState) =
  let w = terminalWidth()
  let h = terminalHeight()

  tb.write(centerX("Help", w), 1, fgCyan, "Help")
  tb.drawHorizLine(0, w - 1, 2, doubleStyle = true)

  let helpText = @[
    "Bara Lang TUI v0.1.0",
    "",
    "Navigation:",
    "  Arrow Keys / Tab  Navigate menus and fields",
    "  Enter             Select / Confirm",
    "  Escape            Go back / Cancel",
    "  Backspace         Delete character",
    "",
    "AI Configuration:",
    "  Set your API key in AI Settings. Supported providers:",
    "  - DeepSeek (deepseek-chat)",
    "  - OpenAI / OpenRouter (gpt-4o-mini)",
    "  - Xiaomi MiMo (mimo-chat)",
    "  - Custom OpenAI-compatible endpoints",
    "",
    "Config is saved to: ~/.config/cljnim/config.json",
    "",
    "Press ESC to return to Main Menu"
  ]

  for i, line in helpText:
    if 4 + i < h - 2:
      tb.write(4, 4 + i, fgWhite, truncate(line, w - 8))

  tb.drawHorizLine(0, w - 1, h - 2, doubleStyle = true)
  tb.write(2, h - 1, fgGreen, "Press ESC to go back")

proc handleHelp*(key: Key, state: var ScreenState) =
  case key
  of Key.Escape, Key.Enter:
    state.currentScreen = stMainMenu
  else: discard

# ─── REPL Screen ─────────────────────────────────────────────────────

proc drawRepl*(tb: var TerminalBuffer, state: var ScreenState) =
  let w = terminalWidth()
  let h = terminalHeight()

  tb.write(centerX("REPL", w), 1, fgCyan, "REPL")
  tb.drawHorizLine(0, w - 1, 2, doubleStyle = true)

  let msg = @[
    "The REPL runs in a separate terminal session.",
    "",
    "Press ENTER to start the REPL now.",
    "Press ESC to go back to the menu.",
    "",
    "You can also run REPL from command line:",
    "  ./cljnim repl          (human mode)",
    "  ./cljnim repl --json   (AI/structured mode)",
    "  ./cljnim repl --tcp 5555  (TCP server mode)"
  ]

  for i, line in msg:
    if 6 + i < h - 2:
      tb.write(4, 6 + i, fgWhite, truncate(line, w - 8))

  tb.drawHorizLine(0, w - 1, h - 2, doubleStyle = true)
  tb.write(2, h - 1, fgGreen, "ENTER = start REPL | ESC = back")

proc handleRepl*(key: Key, state: var ScreenState) =
  case key
  of Key.Escape:
    state.currentScreen = stMainMenu
  of Key.Enter:
    # Signal to main loop to suspend TUI and launch REPL
    state.popupMsg = "LAUNCH_REPL"
    state.popupActive = true
  else: discard
