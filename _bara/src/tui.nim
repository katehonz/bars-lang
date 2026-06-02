# Bara Lang TUI — Terminal User Interface
# Fullscreen menu-driven interface for cljnim

import std/os
import illwill
import tui_config, tui_screens, repl

proc runTui*() =
  ## Main TUI entry point
  let cfg = loadConfig()
  var state = initState(cfg)

  # ── illwill init ────────────────────────────────────────────────
  proc exitProc() {.noconv.} =
    illwillDeinit()
    showCursor()
    quit(0)

  illwillInit(fullscreen = true)
  setControlCHook(exitProc)
  hideCursor()

  var tb = newTerminalBuffer(terminalWidth(), terminalHeight())

  # ── main loop ───────────────────────────────────────────────────
  while not state.quit:
    let w = terminalWidth()
    let h = terminalHeight()

    # Resize buffer if terminal changed
    if tb.width != w or tb.height != h:
      tb = newTerminalBuffer(w, h)

    # Clear
    tb.clear()
    tb.setForegroundColor(fgWhite)

    # Draw current screen
    case state.currentScreen
    of stMainMenu:
      drawMainMenu(tb, state)
    of stAiSettings:
      drawAiSettings(tb, state)
    of stCompile:
      drawCompile(tb, state)
    of stRun:
      drawRun(tb, state)
    of stAiGenerate:
      drawAiGenerate(tb, state)
    of stHelp:
      drawHelp(tb, state)
    of stRepl:
      drawRepl(tb, state)

    # Draw popup on top if active
    drawPopup(tb, state)

    # Render
    tb.display()

    # Handle input
    var key = getKey()
    if key == Key.None:
      sleep(20)
      continue

    # Special handling for REPL launch
    if state.currentScreen == stRepl and state.popupActive and state.popupMsg == "LAUNCH_REPL":
      state.popupActive = false
      state.popupMsg = ""
      # Suspend TUI and launch REPL
      illwillDeinit()
      showCursor()
      echo ""
      echo "=== Starting Bara Lang REPL ==="
      echo "Type :quit to return to TUI"
      echo ""
      var replState = initReplState(rmHuman)
      try:
        runHumanRepl(replState)
      finally:
        replState.cleanup()
      # Re-init TUI
      illwillInit(fullscreen = true)
      setControlCHook(exitProc)
      hideCursor()
      tb = newTerminalBuffer(terminalWidth(), terminalHeight())
      state.currentScreen = stMainMenu
      continue

    # Route input to current screen handler
    if state.popupActive:
      # Popup consumes Enter/Escape
      case key
      of Key.Enter, Key.Escape:
        state.popupActive = false
        state.popupMsg = ""
      else: discard
    else:
      case state.currentScreen
      of stMainMenu:
        handleMainMenu(key, state)
      of stAiSettings:
        handleAiSettings(key, state)
      of stCompile:
        handleCompile(key, state)
      of stRun:
        handleRun(key, state)
      of stAiGenerate:
        handleAiGenerate(key, state)
      of stHelp:
        handleHelp(key, state)
      of stRepl:
        handleRepl(key, state)

    sleep(20)

  # ── cleanup ─────────────────────────────────────────────────────
  illwillDeinit()
  showCursor()
