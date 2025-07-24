#Requires AutoHotkey v2.0
#SingleInstance force ;; Auto-reload
#Warn ;; Enable warnings, show message box.

;;. Using space as the dual mode key for alt does not work: writing
;;  text fast always triggers alt-key hotkeys (google docs etc).
;;. Using caps lock as dual mode key for backspace does not work since
;;  it's often mispressed and "backspace" do terrible things like
;;  deleting items and so on.
;;. Using 'caps lock' as leader is better than 'tab' since leader is
;;  used a lot to emulate arrows, wheel and clicks, while left control
;;  (which caps lock originally was replaced to) is used much less,
;;  mostly as C-[ for escape in VIM, but leader-[ is also an escape,
;;  so nothing changes.
;;. 'ctrl-;' is used in Chrome for debugging, so it's not used as
;;  ctrl-click shortcut which is rare and 'tab+ctrl' can be holded for it.
;;. leaving backspace "as is" simply don't work: it's too far away.
;;. Windows detects physical shift while pressing shift-del, so keeping
;;  "del" as leader-shift-/ is not viable, it is detected as "skip recycle
;;  bin". Instead, leader-p is mapped to backspace, leader-shift-p to
;;  ctrl-backspace (delete word) and leader-p to "delete".
;;. DllCall("mouse_event", "UInt", 0x800, "UInt", 0, "UInt", 0, "UInt", 120)
;;  for mouse wheel will not work, on modern Windows it was replaced with
;;  SendInput.
;;. It's better to remap 'caps lock' to some not-used keys (like F24)
;;  using Windows registry and use that resulting key. Such trick prevents
;;  caps lock from triggering in situations where keyboard hook is not
;;  working (UAC, lock screen, "Grim Dawn" etc).
;;. '/' is much better fit for middle mouse button since triple-mode 'enter'
;;  is overkill.
;;. One-finger scroll is used too often for m1-]: too much load for pinkey,
;;  so it's better to move it to something that is easier to hold, ex
;;  m1-.
;;. Unlike MacOS where hammerspoon can click any dock item, Windows
;;  can switch only between 10 taskbar apps by itself, so mapping m1-plus
;;  for 11-th app is not easy.
;;. For games like WoW right buttons hold are used for movement, so
;;  sometimes caps lock is released while holding tick or semicolon. Holding
;;  caps lock again should enter button hold (ex pressing m1 while holding
;;  the corresponding key should emit keydown again). Current implementation
;;  simply does not release mouse button while releasing mod.

codepage := 65001 ; utf-8
;;  Reliable key state detection
InstallKeybdHook

;;  Map of all remap configurations
appRemap := Map()
appMeta := Map()
appKeysPressed := Map()
appLastLang := ""
appLastDebug := ""
appIsDebug := false
appDebugLog := []
appSymbols := []
appLastKeydown := ["", Map()]
appLastKeyup := ["", Map()]
appLastCfg := ""
appSettings := Map(
  ; PoE remaps
  "s-poe", false
)
MAX_DEBUG_LOG := 50
KEY_NAMES := Map(
  "vkc0", "~",
  "vk8", "backspace",
  "vkdb", "[",
  "vkdd", "]",
  "vkdc", "\",
  "vked", "caps",
  "vkba", ";",
  "vkde", "'",
  "vkbc", ",",
  "vkbe", ".",
  "vkbf", "/"
)

if (!A_IsAdmin) {
  Run "*RunAs" A_ScriptFullPath
  ExitApp
}

;;  No warning if key is hold for 2 seconds (HotkeyInterval)
A_MaxHotkeysPerInterval := 500

assert(condition, msg) {
  if (not condition) {
    OutputDebug("ahk assert: " . msg)
  }
}

repeatStr(times, str) {
  res := ""
  loop times
    res .= str
  return res
}

joinWithSep(sep, collection) {
  res := ""
  for _, item in collection {
    if (res) {
      res .= sep
    }
    res .= item
  }
  return res
}

includes(container, needles*) {
  if (needles.Length == 1) {
    needle := needles[1]
    for _, val in container {
      if val == needle {
        return true
      }
    }
  }
  else {
    found := 0
    for _, val in container {
      for _, needle in needles {
        if val == needle {
          found += 1
          if (found == needles.Length) {
            return true
          }
        }
      }
    }
  }
  return false
}

remove(container, needle) {
  for idx, val in container {
    if val == needle {
      container.RemoveAt(idx)
      return
    }
  }
}

mapToStr(container, oneline := false, indent := 0) {
  res := "{"
  if (not oneline) {
    res .= "`n"
  }
  for key, val in container {
    if (oneline) {
      padding := ""
    }
    else {
      padding := repeatStr(indent + 2, " ")
    }
    if (IsObject(val)) {
      res .= padding . key . ": " . mapToStr(val, oneline, indent + 2) . ","
    } else {
      if (Type(val) == "String") {
        res .= padding . key . ": `"" . val . "`","
      } else {
        res .= padding . key . ": " . val . ","
      }
    }
    if (oneline) {
      res .= " "
    }
    else {
      res .= "`n"
    }
  }
  return res . repeatStr(indent, " ") . "}"
}

arrayToStr(container) {
  res := "["
  for idx, val in container {
    if (idx > 1) {
      res .= ", "
    }
    if (Type(val) == "String") {
      res .= "`"" . val . "`""
    }
    else {
      res .= val
    }
  }
  res .= "]"
  return res
}

joinToStr(array, quote := false, oneline := false) {
  res := ""
  for idx, param in array {
    if (idx > 1) {
      res .= " "
    }
    if (Type(param) == "String") {
      if (quote) {
        res .= "`"" . param . "`""
      }
      else {
        res .= param
      }
    }
    else if (Type(param) == "Array") {
      res .= arrayToStr(param)
    }
    else if (Type(param) == "Map") {
      res .= mapToStr(param, oneline)
    }
    else if (Type(param) == "RegExMatchInfo") {
      res .= "RegExMatchInfo(count=" . param.Count . ")"
    }
    else {
      res .= param
    }
  }
  return res
}

sortArray(&items) {
  left := 1
  right := items.Length
  while (left < right) {
    minIdx := left
    search := left + 1
    while (search <= right) {
      if (items[search] < items[minIdx]) {
        minIdx := search
      }
      search += 1
    }
    if (minIdx != left) {
      tmp := items[left]
      items[left] := items[minIdx]
      items[minIdx] := tmp
    }
    left += 1
  }
}

compareArray(left, right) {
  if (left.Length != right.Length) {
    return false
  }

  i := 1
  while (i <= left.Length) {
    if (left[i] != right[i]) {
      return false
    }
    i += 1
  }

  return true
}

debugDebounce(params*) {
  global appLastDebug
  msg := joinToStr(params, quote := true)
  if (msg != appLastDebug) {
    OutputDebug(msg)
    appLastDebug := msg
  }
}

debugDebounceOneline(params*) {
  global appLastDebug
  msg := joinToStr(params, quote := true, oneline := true)
  if (msg != appLastDebug) {
    OutputDebug(msg)
    appLastDebug := msg
  }
}

debugLogDebounce(params*) {
  msg := joinToStr(params)
  if (appDebugLog.Length and appDebugLog[appDebugLog.Length] == msg) {
    ; debounce
    return
  }
  appDebugLog.Push(msg)
  if (appDebugLog.Length > MAX_DEBUG_LOG) {
    appDebugLog.RemoveAt(1)
  }
}

urlEncode(url) {
  flags := 0x000C3000
	cc := 4096
  esc := ""
  res := ""
  E_POINTER := 0x80004003
	loop {
		VarSetStrCapacity(&esc, cc)
		res := DllCall(
      "Shlwapi.dll\UrlEscapeW",
      "Str", url,
      "Str", &esc,
      "UIntP", &cc,
      "UInt", flags,
      "UInt")
	} until (res != E_POINTER)
	return esc
}

urlDecode(url) {
  flags := 0x00140000
  res := DllCall(
    "Shlwapi.dll\UrlUnescape",
    "Ptr", StrPtr(url),
    "Ptr", 0,
    "UInt", 0,
    "UInt", flags,
    "UInt")
  if (res == 0) {
    return ""
  }
  return url
}

getReadableKeyName(key) {
  name := StrLower(key)
  if (KEY_NAMES.Has(name)) {
    return KEY_NAMES.Get(name)
  }
  else {
    return name
  }
}

getLocale() {
  hwnd := WinExist("A")
  if (not hwnd) {
    return ""
  }

  threadId := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0)
  locale := DllCall("GetKeyboardLayout", "Ptr", threadId, "Ptr")
  return locale
}

setLocale(locale) {
  setLocaleAsync() {
    hwnd := WinExist("A")
    if (not hwnd) {
      return ""
    }
    loop 10 {
      if (getLocale() == locale) {
        break
      }
      ; Not always set from the first try
      PostMessage(WM_INPUTLANGCHANGEREQUEST := 0x50, 0, locale, hwnd)
      Sleep(100)
    }
  }
  ; Don't block current thread and make it interruptable, this can mess
  ; with the state and result in "alone" keys not correctly triggering
  ; after switching language since language switch keys are not correctly
  ; put in / removed from the appKeysPressed map.
  SetTimer(setLocaleAsync, -10)
}

;;  TODO: add in correct order (ex "m1" + "shift" before "m1")
addRemap(from, fromMods, to, toMods := []) {
  config := Map(
    "from_mods", fromMods,
    "to", to,
    "to_mods", toMods,
    "options", [])
  if (Type(from) == "Array") {
    options := from.Clone()
    from := options.RemoveAt(1)
    config["options"] := options
  }
  if (appRemap.Has(from)) {
    appRemap[from].Push(config)
  }
  else {
    appRemap[from] := [config]
  }
}

;;  Receives the list of modifiers like ["m1", "shift"] and evaluates to
;;  true if the corresponding keys are pressed
modsPressedForKey(mods, key) {
  for i, modName in mods {
    ; used first to unset meta if it was set during initial keydown
    if (modName == "always") {
      return true
    }
    if (modName == "m1" or modName == "m2" or modName == "m3") {
      if (not appMeta.Has(modName)) {
        return false
      }
      if (not appMeta[modName]) {
        return false
      }
    }
    else if (modName == "alone") {
      for curKey, keyInfo in appKeysPressed {
        if (curKey != key) {
          return false
        }
        else if (not keyInfo["alone"]) {
          return false
        }
      }
    }
    ; Setting name?
    else if (SubStr(modName, 1, StrLen("s-")) == "s-") {
      return appSettings[modName]
    }
    ; left and right controls are dual-mode from tab and enter, so treat
    ; them specially
    else if (modName == "ctrl") {
      if (key == "lctrl") {
        ; Prevent lctrl (tab) to reat it's own state as ctrl mod, rctrl
        ; (enter) is used to trigger ctrl-tab
        if (not GetKeyState("rctrl", "P")) {
          return false
        }
      }
      else if (key == "rctrl") {
        ; Prevent rctrl (enter) to reat it's own state as ctrl mod, lctrl
        ; (tab) is used to trigger ctrl-enter
        if (not GetKeyState("lctrl", "P")) {
          return false
        }
      }
      else {
        if (not GetKeyState("ctrl", "P")) {
          return false
        }
      }
    }
    else if (modName == "win") {
      ; lwin and rwin
      if (not GetKeyState("vk5b", "P") and not GetKeyState("vk5c", "P")) {
        return false
      }
    }
    ;;  keys like "shift" etc
    else if (not GetKeyState(modName, "P")) {
      return false
    }
  }
  return true
}

;;  Receives the list of modifiers like ["ctrl", alt"] and evaluates to
;;  an autohotkey modifiers string for send command, ex "^!"
modsToStr(mods) {
  res := ""
  for _, modName in mods {
    if (modName == "win") {
      res .= "#"
    }
    else if (modName == "ctrl") {
      res .= "^"
    }
    else if (modName == "alt") {
      res .= "!"
    }
    else if (modName == "shift") {
      res .= "+"
    }
    else {
      assert(false, "unknown mod in " . arrayToStr(mods))
    }
  }
  return res
}

;;  Given list of maps describing monitors evaluate to the index in that
;;  list where the window specified by the description is located
monitorFromWnd(monitors, wnd) {
  maxArea := 0
  maxMonitorIdx := ""

  for monitorIdx, monitor in monitors {
    if (
      wnd["right"] <= monitor["left"] or
      wnd["left"] >= monitor["right"] or
      wnd["top"] >= monitor["bottom"] or
      wnd["bottom"] <= monitor["top"]
    ) {
      continue
    }

    left := Max(wnd["left"], monitor["left"])
    right := Min(wnd["right"], monitor["right"])
    top := Max(wnd["top"], monitor["top"])
    bottom := Min(wnd["bottom"], monitor["bottom"])
    area := (right - left) * (bottom - top)

    if (area > maxArea) {
      maxArea := area
      maxMonitorIdx := monitorIdx
    }
  }

  return maxMonitorIdx
}

;;  Takes map of "left", "right", "top", "bottom", "width", "height"
;;  and recalculates specified attributes.
recalculateGeometry(geometry, attributes*) {
  for _, attr in attributes {
    if (attr == "left") {
      geometry["left"] := geometry["right"] - geometry["width"]
    }
    if (attr == "right") {
      geometry["right"] := geometry["left"] + geometry["width"]
    }
    else if (attr == "top") {
      geometry["top"] := geometry["bottom"] - geometry["height"]
    }
    else if (attr == "bottom") {
      geometry["bottom"] := geometry["top"] + geometry["height"]
    }
    else if (attr == "width") {
      geometry["width"] := geometry["right"] - geometry["left"]
    }
    else if (attr == "height") {
      geometry["height"] := geometry["bottom"] - geometry["top"]
    }
  }
}

moveActiveWnd(wndInfo) {
  WinMove(
    wndInfo["left"],
    wndInfo["top"],
    wndInfo["width"],
    wndInfo["height"],
    "A")
}

getCurWinPos() {
  WinGetPos(&x, &y, &width, &height, "A")
  return Map(
    "left", x,
    "right", x + width,
    "top", y,
    "bottom", y + height,
    "width", width,
    "height", height)
}

getMonitors() {
  monitors := []
  monitorCount := MonitorGetCount()
  loop monitorCount {
    MonitorGetWorkArea(a_index, &left, &top, &right, &bottom)
    monitors.Push(Map(
      "index", a_index,
      "left", left,
      "right", right,
      "top", top,
      "bottom", bottom,
      "width", right - left,
      "height", bottom - top
    ))
  }
  return monitors
}

setCurWinPos(pos) {
  hwnd := WinExist("A")
  if (not hwnd) {
    return
  }

  wndInfo := getCurWinPos()
  monitors := getMonitors()
  monIdx := monitorFromWnd(monitors, wndInfo)
  if (not monIdx) {
    return
  }
  monInfo := monitors[monIdx]

  if (pos == "left") {
    wndInfo["left"] := monInfo["left"]
    wndInfo["top"] := monInfo["top"]
    wndInfo["width"] := monInfo["width"] / 2
    wndInfo["height"] := monInfo["height"]
    recalculateGeometry(wndInfo, "right", "bottom")
    moveActiveWnd(wndInfo)
  }
  else if (pos == "right") {
    wndInfo["right"] := monInfo["right"]
    wndInfo["top"] := monInfo["top"]
    wndInfo["width"] := monInfo["width"] / 2
    wndInfo["height"] := monInfo["height"]
    recalculateGeometry(wndInfo, "left", "bottom")
    moveActiveWnd(wndInfo)
  }
  else if (pos == "top") {
    wndInfo["left"] := monInfo["left"]
    wndInfo["top"] := monInfo["top"]
    wndInfo["width"] := monInfo["width"]
    wndInfo["height"] := monInfo["height"] / 2
    recalculateGeometry(wndInfo, "right", "bottom")
    moveActiveWnd(wndInfo)
  }
  else if (pos == "bottom") {
    wndInfo["left"] := monInfo["left"]
    wndInfo["bottom"] := monInfo["bottom"]
    wndInfo["width"] := monInfo["width"]
    wndInfo["height"] := monInfo["height"] / 2
    recalculateGeometry(wndInfo, "right", "top")
    moveActiveWnd(wndInfo)
  }
  else if (pos == "topleft") {
    wndInfo["left"] := monInfo["left"]
    wndInfo["top"] := monInfo["top"]
    wndInfo["width"] := monInfo["width"] / 2
    wndInfo["height"] := monInfo["height"] / 2
    recalculateGeometry(wndInfo, "right", "bottom")
    moveActiveWnd(wndInfo)
  }
  else if (pos == "topright") {
    wndInfo["right"] := monInfo["right"]
    wndInfo["top"] := monInfo["top"]
    wndInfo["width"] := monInfo["width"] / 2
    wndInfo["height"] := monInfo["height"] / 2
    recalculateGeometry(wndInfo, "left", "bottom")
    moveActiveWnd(wndInfo)
  }
  else if (pos == "bottomleft") {
    wndInfo["left"] := monInfo["left"]
    wndInfo["bottom"] := monInfo["bottom"]
    wndInfo["width"] := monInfo["width"] / 2
    wndInfo["height"] := monInfo["height"] / 2
    recalculateGeometry(wndInfo, "right", "top")
    moveActiveWnd(wndInfo)
  }
  else if (pos == "bottomright") {
    wndInfo["right"] := monInfo["right"]
    wndInfo["bottom"] := monInfo["bottom"]
    wndInfo["width"] := monInfo["width"] / 2
    wndInfo["height"] := monInfo["height"] / 2
    recalculateGeometry(wndInfo, "left", "top")
    moveActiveWnd(wndInfo)
  }
  ; Setting size instead of "maximizing" is better since "maximized"
  ; windows cannot be moved programmatically to the left and right
  else if (pos == "max") {
    wndInfo["left"] := monInfo["left"]
    wndInfo["right"] := monInfo["right"]
    wndInfo["top"] := monInfo["top"]
    wndInfo["bottom"] := monInfo["bottom"]
    recalculateGeometry(wndInfo, "width", "height")
    moveActiveWnd(wndInfo)
  }
  else {
    assert(false, "unknown pos " . pos)
  }
}

setCurWinMon(dir) {
  hwnd := WinExist("A")
  if (not hwnd) {
    return
  }

  wndInfo := getCurWinPos()
  monitors := getMonitors()
  monIdx := monitorFromWnd(monitors, wndInfo)
  if (not monIdx) {
    return
  }
  monInfo := monitors[monIdx]

  dstMonIdx := ""
  for curMonIdx, curMonInfo in monitors {
    if (curMonIdx != monIdx) {
      if (dir == "up") {
        if (curMonInfo["bottom"] <= monInfo["top"]) {
          dstMonIdx := curMonIdx
          break
        }
      }
      else if (dir == "down") {
        if (curMonInfo["top"] >= monInfo["bottom"]) {
          dstMonIdx := curMonIdx
          break
        }
      }
      else if (dir == "left") {
        if (curMonInfo["right"] <= monInfo["left"]) {
          dstMonIdx := curMonIdx
          break
        }
      }
      else if (dir == "right") {
        if (curMonInfo["left"] >= monInfo["right"]) {
          dstMonIdx := curMonIdx
          break
        }
      }
    }
  }

  if (not dstMonIdx) {
    return
  }

  dstMonInfo := monitors[dstMonIdx]

  ; Scale window for the target monitor
  dx := Abs(monInfo["left"] - wndInfo["left"]) / monInfo["width"]
  dy := Abs(monInfo["top"] - wndInfo["top"]) / monInfo["height"]
  dw := wndInfo["width"] / monInfo["width"]
  dh := wndInfo["height"] / monInfo["height"]
  wndInfo["left"] := dstMonInfo["left"] + dstMonInfo["width"] * dx
  wndInfo["top"] := dstMonInfo["top"] + dstMonInfo["height"] * dy
  wndInfo["width"] := dstMonInfo["width"] * dw
  wndInfo["height"] := dstMonInfo["height"] * dh
  recalculateGeometry(wndInfo, "right", "bottom")

  ; If window is bigger than display it will not be correctly placed
  if (wndInfo["left"] < dstMonInfo["left"]) {
    wndInfo["left"] := dstMonInfo["left"]
  }
  if (wndInfo["right"] > dstMonInfo["right"]) {
    wndInfo["right"] := dstMonInfo["right"]
  }
  if (wndInfo["top"] < dstMonInfo["top"]) {
    wndInfo["top"] := dstMonInfo["top"]
  }
  if (wndInfo["bottom"] > dstMonInfo["bottom"]) {
    wndInfo["bottom"] := dstMonInfo["bottom"]
  }
  recalculateGeometry(wndInfo, "width", "height")
  moveActiveWnd(wndInfo)
}

cycleCurWin(dir) {
  hwnd := WinExist("A")
  if (not hwnd) {
    return
  }

  pid := WinGetPID("A")
  process := WinGetProcessName("A")

  windows := WinGetList()
  sortArray(&windows)
  activeWndFound := false
  firstWnd := ""
  prevWnd := ""
  nextWnd := ""
  lastWnd := ""

  for win in windows {
    if (WinGetProcessName(win) == process) {
      if (not firstWnd) {
        firstWnd := win
      }
      if (win == hwnd) {
        activeWndFound := true
      }
      else {
        if (not activeWndFound) {
          prevWnd := win
        }
        else if(not nextWnd) {
          nextWnd := win
        }
      }
      lastWnd := win
    }
  }

  ; active wnd is first?
  if (not prevWnd) {
    prevWnd := lastWnd
  }
  ; active wnd is last?
  if (not nextWnd) {
    nextWnd := firstWnd
  }

  if (dir == "prev") {
    WinActivate(prevWnd)
  }
  else {
    WinActivate(nextWnd)
  }
}

switchToLang(lang) {
  if (lang == "en") {
    setLocale(0x04090409)
  }
  else if (lang == "ru") {
    setLocale(0x04190419)
  }
  else if (lang == "jp") {
    if (appLastLang == "jp") {
      ;;  Switch between Hiragana and Latin input for Japanese keyboard
      Send("!``")
    }
    else {
      setLocale(0x04110411)
    }
  }
  global appLastLang
  appLastLang := lang
}

showSymbolPicker() {
  wndInfo := getCurWinPos()
  monitors := getMonitors()
  monIdx := monitorFromWnd(monitors, wndInfo)
  if (not monIdx) {
    return
  }
  monInfo := monitors[monIdx]

  wnd := Gui()
  editBox := wnd.Add("Edit", "w300 h32 r1")
  textBox := wnd.Add("Edit", "w300 h200 Disabled")
  wnd.OnEvent("Escape", closeSymbolPicker)
  wnd.OnEvent("Close", closeSymbolPicker)

  symbolsByFilter(filter) {
    filtered := []
    for _, pair in appSymbols {
      symbol := pair[1]
      name := pair[2]
      if (not filter or InStr(StrLower(name), StrLower(filter)) == 1) {
        filtered.Push(pair)
      }
    }
    return filtered
  }

  onUpdateSymbols(filter) {
    filtered := symbolsByFilter(filter)
    lines := []
    for _, pair in filtered {
      symbol := pair[1]
      name := pair[2]
      lines.Push(symbol . " " . name)
    }
    ControlSetText(joinWithSep("`r`n", lines), textBox)
  }

  onSymbolPickerKeydown(wParam, lParam, *) {
    keyName := GetKeyName(Format('vk{:X}', wParam))
    filter := ControlGetText(editBox)
    if (keyName == "Enter") {
      closeSymbolPicker()
      pairs := symbolsByFilter(filter)
      if (pairs) {
        pair := pairs[1]
        symbol := pair[1]
        Send(symbol)
      }
      return
    }
  }
  OnMessage(WM_KEYDOWN := 0x100, onSymbolPickerKeydown)

  closeSymbolPicker(*) {
    ; OnMessage keeps a list of all registered functions
    OnMessage(WM_KEYDOWN := 0x100, onSymbolPickerKeydown, 0)
    OnMessage(WM_KEYUP := 0x101, onSymbolPickerKeyup, 0)
    wnd.Destroy()
  }

  onSymbolPickerKeyup(wParam, lParam, *) {
    keyName := GetKeyName(Format('vk{:X}', wParam))
    filter := ControlGetText(editBox)
    onUpdateSymbols(filter)
  }
  OnMessage(WM_KEYUP := 0x101, onSymbolPickerKeyup)

  width := 320
  height := 240
  x := monInfo["left"] + (monInfo["width"] - width) / 2
  y := monInfo["top"] + (monInfo["height"] - height) / 2
  ; Show initial unfiltered list of symbols
  onUpdateSymbols("")
  wnd.Show("x" . x . " y" . y . " w" . width . " h" . height)
}

onKeyCommand(items, dir) {
  command := items.RemoveAt(1)
  if (command == "nothing") {
    return
  }
  if (command == "meta") {
    name := items.RemoveAt(1)
    if (dir == "down") {
      appMeta[name] := true
    }
    else if (dir == "up") {
      appMeta[name] := false
    }
    else {
      assert(false, "unknown dir " . dir)
    }
    return
  }
  if (dir == "down") {
    ; Switch language on key down: since chord is very fast, switching it
    ; on key up will result in situations where modifier is released before
    ; the langauge switch key and key release will miss some modifier and
    ; will not be triggered.
    if (command == "lang") {
      lang := items.RemoveAt(1)
      switchToLang(lang)
      return
    }
    else if (command == "symbols") {
      showSymbolPicker()
    }
  }
  if (dir == "up") {
    if (command == "winclose") {
      hwnd := WinExist("A")
      if (hwnd) {
        if (WinGetTitle("A") == "Zoom Workplace") {
          Run("taskkill /f /im zCefAgent.exe",, "Hide")
          Run("taskkill /f /im Zoom.exe",, "Hide")
        }
        else {
          winclose "A"
        }
      }
      return
    }
    if (command == "delete") {
      if (WinActive("ahk_exe explorer.exe")) {
        ;;  Explorer monitors physical 'shift' key, so sending 'delete'
        ;;  will trigger whift-delete, which is "permanently delete", while
        ;;  ctrl-d key combination is just 'delte' in most apps.
        Send("^d")
      }
      else {
        Send("{delete}")
      }
      return
    }
    if (command == "send") {
      input := items.RemoveAt(1)
      Send(input)
      return
    }
    if (command == "click") {
      MouseGetPos(&curX, &curY)
      xRelative := items.RemoveAt(1)
      yRelative := items.RemoveAt(1)
      x := A_ScreenWidth * xRelative
      y := A_ScreenHeight * yRelative
      MouseMove(x, y)
      Sleep(150)
      Click()
      Sleep(150)
      MouseMove(curX, curY)
      return
    }
    if (command == "winpos") {
      pos := items.RemoveAt(1)
      setCurWinPos(pos)
      return
    }
    if (command == "winmon") {
      dir := items.RemoveAt(1)
      setCurWinMon(dir)
      return
    }
    if (command == "wincycle") {
      dir := items.RemoveAt(1)
      cycleCurWin(dir)
      return
    }
    if (command == "winactivate") {
      name := items.RemoveAt(1)
      if (WinExist(name)) {
        WinActivate(name)
      }
      return
    }
    if (command == "appactivate") {
      name := items.RemoveAt(1)
      if (WinExist("ahk_exe " . name)) {
        WinActivate("ahk_exe " . name)
      }
      return
    }
    if (command == "lock") {
      ; Locking workstation prevents "key up" events and results in
      ; "stuck" meta.
      appMeta.Clear()
      DllCall("LockWorkStation")
      return
    }
    if (command == "shorten") {
      ; Suppress linter error
      clipboard := A_Clipboard
      if (not RegExMatch(clipboard, "^https?://")) {
        TrayTip("Error", "No URL in clipboard", ERR_ICON := 3)
        SetTimer(TrayTip, ONCE_AFTER_MS := -2000)
        return
      }
      if (RegExMatch(clipboard, "^https?://vk.cc")) {
        TrayTip("Error", "Short URL in clipboard", ERR_ICON := 3)
        SetTimer(TrayTip, ONCE_AFTER_MS := -2000)
        return
      }
      if (RegExMatch(clipboard, "^https?://bit.ly")) {
        TrayTip("Error", "Short URL in clipboard", ERR_ICON := 3)
        SetTimer(TrayTip, ONCE_AFTER_MS := -2000)
        return
      }
      token := EnvGet("VK_CC_TOKEN")
      ; https://learn.microsoft.com/en-us/windows/win32/winhttp/winhttprequest
      web := ComObject('WinHttp.WinHttpRequest.5.1')
      url := "https://api.vk.com/method/utils.getShortLink"
      url .= "?" . "url=" . urlEncode(clipboard)
      url .= "&" . "private=1"
      url .= "&" . "access_token=" . urlEncode(token)
      url .= "&" . "v=5.199"
      web.Open("GET", url)
      web.Send()
      web.WaitForResponse()
      text := web.ResponseText
      ; "short_url":"https:\/\/vk.cc\/cIdqeg"
      pattern := "`"short_url`":`"([^`"]+)`""
      RegExMatch(text, pattern, &match)
      if (match and match.Count) {
        A_Clipboard := StrReplace(match[1], "\/", "/")
        TrayTip("Success", A_Clipboard, INFO_ICON := 1)
        SetTimer(TrayTip, ONCE_AFTER_MS := -1000)
      }
      else {
        TrayTip("Error", "Failed", ERR_ICON := 3)
        SetTimer(TrayTip, ONCE_AFTER_MS := -2000)
      }
      return
    }
    if (command == "debugcopy") {
      onDebugCopy()
    }
  }
}

; returns key this was remapped to or empty string
onKey(key, dir) {
  global appIsDebug
  global appLastKeydown
  global appLastKeyup

  ; If key was remapped on keydown, use the same remap on keyup, otherwise
  ; {; down}{caps down}{caps up}{; up} will result in {mouse down}{; up}
  if (dir == "up" and appKeysPressed.Has(key)) {
    remapInfo := appKeysPressed[key]["remap_to"]
    if (remapInfo) {
      command := remapInfo["mods"] . "{" . remapInfo["key"] . " up}"
      if (appIsDebug) {
        name := getReadableKeyName(key)
        remappedName := getReadableKeyName(remapInfo["key"])
        debugLogDebounce("=> from " . name . " {" . remappedName . " up}")
        appLastKeyup := [command, Map()]
      }
      Send(command)
      return remapInfo
    }
  }

  hasAloneMappings := false
  remappedTo := ""

  if (appRemap.has(key)) {
    for _, config in appRemap[key] {
      fromMods := config["from_mods"]
      options := config["options"]
      if (includes(fromMods, "alone")) {
        hasAloneMappings := true
      }
      if (options.Length and options[1] == "app") {
        appName := options[2]
        if (not WinActive("ahk_exe " . appName)) {
          continue
        }
      }
      modsPressed := modsPressedForKey(fromMods, key)
      if (modsPressed) {
        to := config["to"]
        if (Type(to) == "String") {
          mods := modsToStr(config["to_mods"])
          ;; "alone" has meaning only on key up
          isAlone := includes(fromMods, "alone")
          isUponly := includes(options, "uponly")
          if (isAlone or isUponly) {
            if (dir == "up") {
              remappedTo := to
              command := mods . "{" . to . "}"
              if (appIsDebug) {
                name := getReadableKeyName(to)
                appLastKeyup := [command, config]
                debugLogDebounce("=> " . mods . "{" . name . "}")
              }
              Send(command)
            }
          }
          else {
            isNorepeat := includes(options, "norepeat")
            isPressed := appKeysPressed.Has(key)
            ; Don't send some buttons like left mouse button repeatedly
            ; if configured so (ex they are "hold type")
            if (dir == "up" or not isNorepeat or not isPressed) {
              ; remember remap so it can be released on key up
              remappedTo := Map("key", to, "mods", mods)
              command := mods . "{" . to . " " . dir . "}"
              if (appKeysPressed.Has(key)) {
                appKeysPressed[key]["remap_to"] := remappedTo
              }
              if (appIsDebug) {
                name := getReadableKeyName(to)
                debugLogDebounce("=> " . mods . "{" . name . " " . dir . "}")
                if (dir == "down") {
                  appLastKeydown := [command, config]
                  appLastKeyup := ["", Map()]
                }
                else {
                  appLastKeyup := [command, config]
                }
              }
              Send(command)
            }
          }
        }
        else if (Type(to) == "Array") {
          if (appIsDebug) {
            debugLogDebounce("=> " . arrayToStr(to))
          }
          onKeyCommand(to.Clone(), dir)
        }
        else if (Type(to) == "Func") {
          if (dir == "up") {
            to.Call(key)
          }
          return
        }
        else {
          assert(false, "unknown 'to' type " . Type(to))
        }
        if (not includes(fromMods, "always")) {
          ;; skip original key behavior
          if (appIsDebug) {
            debugLogDebounce("=> original skipped")
          }
          return remappedTo
        }
      }
    }
  }

  ; If key has at least one "alone" mapping (that triggers ONLY on
  ; "key up") then it should not be triggered on key down if no mapping
  ; is detected.
  if (not hasAloneMappings) {
    ; Native function is not suppressed, sending them breaks things like #a
    if (key == "lshift" or key == "rshift") {
      return
    }
    if (key == "lctrl" or key == "rctrl") {
      return
    }
    command := "{blind}{" . key . " " . dir . "}"
    if (appIsDebug) {
      name := getReadableKeyName(key)
      debugLogDebounce("=> {blind}{" . name . " " . dir . "}")
      if (dir == "down") {
        appLastKeydown := [command, Map()]
        appLastKeyup := ["", Map()]
      }
      else {
        appLastKeyup := [command, Map()]
      }
    }
    Send(command)
  }
}

onKeydown(key) {
  global appIsDebug
  isPressed := appKeysPressed.Has(key)
  if (appIsDebug and not isPressed) {
    name := getReadableKeyName(key)
    debugLogDebounce(name . " down")
  }

  remappedTo := onKey(key, "down")

  if (not isPressed) {
    ; Pressing rctrl (enter) or lectrl (tab) AFTER dome other keys are
    ; presset doesn't make it itself "alone". Otherwise "enter" will not
    ; work after entering some text due to lingering keys reported as
    ; still pressed down.
    alone := true
    if (appKeysPressed.Count > 0) {
      if (key != "rctrl" and key != "lctrl") {
        alone := false
      }
      for curKey, keyInfo in appKeysPressed {
        keyInfo["alone"] := false
      }
    }
    appKeysPressed[key] := Map(
      ; Key and it's mods can be released in a different sequence. This
      ; ensures that if remap happened on keydown, the same key will be
      ; released regardless on the individual keys release order (ex mod key
      ; released before key being remapped)
      "remap_to", remappedTo,
      ; Used to detect if no other key was pressed between this key press
      ; and release
      "alone", alone,
      ; Used to detect keys which are stuck in "pressed" state
      "stuck_counter", 0
    )
  }
  else {
    ; Keys recive constant "keydown" events while pressed. "keyup" event
    ; can be missed, so "stuck counter" is always incremented by a background
    ; thred, while receiving "keydown" event resets it. If counter overflows,
    ; this means that no "keydown" was received for this key recently,
    ; but no "keyup" either and it's "stuck".
    appKeysPressed[key]["stuck_counter"] := 0
  }
}

onKeyup(key) {
  global appIsDebug
  if (appIsDebug) {
    name := getReadableKeyName(key)
    alone := "unknown"
    if (appKeysPressed.Has(key)) {
      alone := appKeysPressed[key]["alone"]
    }
    debugLogDebounce(name . " up [alone=" . alone . "]")
  }

  if (not appKeysPressed.Has(key)) {
    if (key == "lctrl" or key == "rctrl") {
      ; {rctrl down}{w down} starts generating repeats for "w", but
      ; stops generating repeats for "rctrl". After releasing "w", no
      ; repeats are generated for "rctrl" and key is considered "stuck".
      ; ignore it's key up so no "enter" and "tab" events are generated
      if (appIsDebug) {
        debugLogDebounce("not in list, mod, skipping")
      }
      return
    }
  }

  onKey(key, "up")

  if (appKeysPressed.Has(key)) {
    appKeysPressed.Delete(key)
  }
}

appLastKeyTick := A_TickCount

onRepeatedClick() {
  global appLastKeyTick
  if (WinActive("ahk_exe PathOfExileSteam.exe")) {
    if (A_TickCount > appLastKeyTick + 100) {
      appLastKeyTick := A_TickCount
      Send("{blind}{lbutton}")
    }
  }
  else {
    Send("{bling}{WheelDown}")
  }
}

*$lalt::onKeydown("lalt") ; (esc)
*$lalt up::onKeyup("lalt") ; (esc)
*$vkc0::onKeydown("vkc0") ; "~"
*$vkc0 up::onKeyup("vkc0") ; "~"
*$1::onKeydown("1")
*$1 up::onKeyup("1")
*$2::onKeydown("2")
*$2 up::onKeyup("2")
*$3::onKeydown("3")
*$3 up::onKeyup("3")
*$4::onKeydown("4")
*$4 up::onKeyup("4")
*$5::onKeydown("5")
*$5 up::onKeyup("5")
*$6::onKeydown("6")
*$6 up::onKeyup("6")
*$7::onKeydown("7")
*$7 up::onKeyup("7")
*$8::onKeydown("8")
*$8 up::onKeyup("8")
*$9::onKeydown("9")
*$9 up::onKeyup("9")
*$0::onKeydown("0")
*$0 up::onKeyup("0")
*$-::onKeydown("-")
*$- up::onKeyup("-")
*$=::onKeydown("=")
*$= up::onKeyup("=")
*$vk8::onKeydown("backspace")
*$vk8 up::onKeyup("backspace")

*~$lctrl::onKeydown("lctrl") ; Don't suppress native "ctrl" function
*~$lctrl up::onKeyup("lctrl") ; Don't suppress native "ctrl" function
*$q::onKeydown("q")
*$q up::onKeyup("q")
*$w::onKeydown("w")
*$w up::onKeyup("w")
*$e::onKeydown("e")
*$e up::onKeyup("e")
*$r::onKeydown("r")
*$r up::onKeyup("r")
*$t::onKeydown("t")
*$t up::onKeyup("t")
*$y::onKeydown("y")
*$y up::onKeyup("y")
*$u::onKeydown("u")
*$u up::onKeyup("u")
*$i::onKeydown("i")
*$i up::onKeyup("i")
*$o::onKeydown("o")
*$o up::onKeyup("o")
*$p::onKeydown("p")
*$p up::onKeyup("p")
*$[::onKeydown("vkdb") ; "[", vk codes for lang layouts
*$[ up::onKeyup("vkdb") ; "["
*$]::onKeydown("vkdd") ; "]"
*$] up::onKeyup("vkdd") ; "]"
*$\::onKeydown("vkdc") ; "\"
*$\ up::onKeyup("vkdc") ; "\"

*$vked::onKeydown("vked") ; "caps lock"
*$vked up::onKeyup("vked") ; "caps lock"
*$a::onKeydown("a")
*$a up::onKeyup("a")
*$s::onKeydown("s")
*$s up::onKeyup("s")
*$d::onKeydown("d")
*$d up::onKeyup("d")
*$f::onKeydown("f")
*$f up::onKeyup("f")
*$g::onKeydown("g")
*$g up::onKeyup("g")
*$h::onKeydown("h")
*$h up::onKeyup("h")
*$j::onKeydown("j")
*$j up::onKeyup("j")
*$k::onKeydown("k")
*$k up::onKeyup("k")
*$l::onKeydown("l")
*$l up::onKeyup("l")
*$;::onKeydown("vkba") ; ";"
*$; up::onKeyup("vkba") ; ";"
*$'::onKeydown("vkde") ; "'"
*$' up::onKeyup("vkde") ; "'"
*~$rctrl::onKeydown("rctrl") ; Don't suppress native "ctrl" function
*~$rctrl up::onKeyup("rctrl") ; Don't suppress native "ctrl" function

*~$lshift::onKeydown("lshift") ; Don't suppress native "shift" function
*~$lshift up::onKeyup("lshift") ; Don't suppress native "shift" function
*$z::onKeydown("z")
*$z up::onKeyup("z")
*$x::onKeydown("x")
*$x up::onKeyup("x")
*$c::onKeydown("c")
*$c up::onKeyup("c")
*$v::onKeydown("v")
*$v up::onKeyup("v")
*$b::onKeydown("b")
*$b up::onKeyup("b")
*$n::onKeydown("n")
*$n up::onKeyup("n")
*$m::onKeydown("m")
*$m up::onKeyup("m")
*$,::onKeydown("vkbc") ; ","
*$, up::onKeyup("vkbc") ; ","
*$.::onKeydown("vkbe") ; "."
*$. up::onKeyup("vkbe") ; "."
*$/::onKeydown("vkbf") ; "/"
*$/ up::onKeyup("vkbf") ; "/"
*~$rshift::onKeydown("rshift") ; Don't suppress native "shift" function
*~$rshift up::onKeyup("rshift") ; Don't suppress native "shift" function

*$esc::onKeydown("esc") ; (lalt)
*$esc up::onKeyup("esc") ; (lalt)
*$space::onKeydown("space")
*$space up::onKeyup("space")
*$enter::onKeydown("enter") ; (ralt)
*$enter up::onKeyup("enter") ; (ralt)
*$left::onKeydown("left")
*$left up::onKeyup("left")
*$down::onKeydown("down")
*$down up::onKeyup("down")
*$up::onKeydown("up")
*$up up::onKeyup("up")
*$right::onKeydown("right")
*$right up::onKeyup("right")

^$WheelDown::onRepeatedClick()
+$WheelDown::onRepeatedClick()
^+$WheelDown::onRepeatedClick()

^$-::onRepeatedClick()
+$-::onRepeatedClick()
^+$-::onRepeatedClick()

; caps lock to meta-1
addRemap("vked", [], ["meta", "m1"])

addRemap("esc", ["always"], ["meta", "m2"])
;;  Single esc (lalt) press => esc
;;  TODO: hold "esc", press "4", release "esc" - triggers "esc"
addRemap("esc", ["alone"], "esc")
;;  m2 + shift for holding esc
addRemap("esc", ["shift"], "esc")

addRemap("enter", ["always"], ["meta", "m3"])
;;  Single enter (ralt) press => enter
addRemap("enter", ["alone"], "enter")

;;  ctrl-enter to shift-enter if ChatGPT is foremost
app := "ChatGPT.exe"
addRemap(["rctrl", "app", app], ["ctrl"], "enter", ["shift"])
;;  Single rctrl (enter) press => enter (with mods)
addRemap("rctrl", ["ctrl"], "enter", ["ctrl"])
addRemap("rctrl", ["shift"], "enter", ["shift"])
addRemap("rctrl", ["alone"], "enter")

;;  Single lctrl (tab) press => tab (with mods)
addRemap("lctrl", ["ctrl"], "tab", ["ctrl"])
addRemap("lctrl", ["alone"], "tab")

;;  ==========================================================================
;;  General keyboard mods
;;  ==========================================================================

;;  m1-m2-open-bracket for switching to previous app window
addRemap("vkdb", ["m1", "m2"], ["wincycle", "prev"])
;;  m1-open-bracket for escape (vim-like)
addRemap("vkdb", ["m1"], "esc")
;;  m1-open-bracket for «
addRemap("vkdb", ["m2"], ["send", "«"])

;;  m1-m2-close-bracket for switching to next app window
addRemap("vkdd", ["m1", "m2"], ["wincycle", "next"])
;;  m2-close-bracket for »
addRemap("vkdd", ["m2"], ["send", "»"])

;;  'm1-m2-p' => bottom right
addRemap("p", ["m1", "m2"], ["winpos", "bottomright"])
;;  m1-m3-p for Double Commander 'delete'
addRemap(["d", "app", "doublecmd.exe"], ["m1", "m3"], "f8")
;;  m1-m3-p for deleting things
addRemap("p", ["m1", "m3"], ["delete"])
;;  m1-p for backspace
addRemap("p", ["m1"], "backspace")

;;  'm1-semicolon' for left mouse button.
addRemap(["vkba", "norepeat"], ["m1", "m2"], "lbutton", ["alt"])
addRemap(["vkba", "norepeat"], ["m1", "ctrl"], "lbutton", ["ctrl"])
addRemap(["vkba", "norepeat"], ["m1", "shift"], "lbutton", ["shift"])
addRemap(["vkba", "norepeat"], ["m1"], "lbutton")

;;  'm1-quote' for right mouse button.
addRemap(["vkde", "norepeat"], ["m1"], "rbutton")

;;  'm1-ctrl-.' for mouse button 4 + ctrl (zoom in Figma)
addRemap(["vkbe", "norepeat"], ["m1", "ctrl"], "xbutton1", ["ctrl"])
;;  'm1-.' for mouse button 4 (scroll)
addRemap(["vkbe", "norepeat"], ["m1"], "xbutton1")

;;  'm1-shift-h' for shift-left-arrow (vim-like + selection modify).
addRemap("h", ["m1", "shift"], "left", ["shift"])
;;  'm1-h' for left arrow (vim-like).
addRemap("h", ["m1"], "left")

;;  'm1-m2-w' for home (line begin)
addRemap("w", ["m1", "m2"], "home")
;;  'm1-w' for home.
addRemap("w", ["m1"], "home")
app := "WindowsTerminal.exe"
addRemap(["w", "app", app], ["ctrl"], "w", ["ctrl", "shift"])

;;  'm1-m2-j' move window one monitor down
addRemap("j", ["m1", "m2"], ["winmon", "down"])
;;  'm1-shift-j' for shift-down-arrow (vim-like + selection modify).
addRemap("j", ["m1", "shift"], "down", ["shift"])
;;  'm1-j' for down arrow (vim-like).
addRemap("j", ["m1"], "down")
;;  'm2-j' for command-down_arrow (google spreadsheets hotkey)
addRemap("j", ["m2"], "down", ["ctrl"])

;;  'm1-e' for page down.
addRemap("e", ["m1"], "pgdn")
;;  'm2-e' for email
addRemap("e", ["m2"], ["send", "grigoryvp{@}gmail.com"])

;;  'm1-m2-k' move window one monitor up
addRemap("k", ["m1", "m2"], ["winmon", "up"])
;;  'm1-shift-k' for shift-up-arrow (vim-like + selection modify).
addRemap("k", ["m1", "shift"], "up", ["shift"])
;;  'm1-k' for up arrow (vim-like).
addRemap("k", ["m1"], "up")

;;  'm1-r' for page up.
addRemap("r", ["m1"], "pgup")
;;  'm2-r' for game command
addRemap("r", ["m2"], ["click", 0.488, 0.81])

;;  'm1-shift-l' for shift-right-arrow (vim-like + selection modify).
addRemap("l", ["m1", "shift"], "right", ["shift"])
;;  'm1-l' for right arrow (vim-like).
addRemap("l", ["m1"], "right")

;;  'm1-m2-t' for end (line end)
addRemap("t", ["m1", "m2"], "end")
;;  'm1-shift-t' for shift-end.
addRemap("t", ["m1", "shift"], "end", ["shift"])
;;  'm1-t' for end.
addRemap("t", ["m1"], "end")
;;  'm2-t' for phone
addRemap("t", ["m2"], ["send", "{+}31681345854"])
;;  'ctrl-t' to 'ctrl-shift-t' for WindowsTerminal
app := "WindowsTerminal.exe"
addRemap(["t", "app", app], ["ctrl"], "t", ["ctrl", "shift"])

;;  Generated by touchpad keyboard edge swipe
addRemap("a", ["win"], ["nothing"])

;;  m1-m2-s for S-F1
addRemap("s", ["m1", "m2"], "vk70", ["shift"])
;;  m1-shift-s switch to 3nd language
addRemap("s", ["m1", "shift"], ["lang", "jp"])
;;  m1-s for F1
addRemap("s", ["m1"], "vk70")
;;  m2-s for english signature
addRemap("s", ["m2"], ["send", "Best regards, {enter}Grigory Petrov,{enter}{+}31681345854{enter}{@}grigoryvp"])
;;  m3-s for short url
addRemap("s", ["m3"], ["shorten"])

;;  'm1-2' fo 1st app
addRemap("2", ["m1"], "1", ["win", "ctrl"])

;;  'm1-3' fo 2nd app
addRemap("3", ["m1"], "2", ["win", "ctrl"])

;;  'm1-4' fo 3rd app
addRemap("4", ["m1"], "3", ["win", "ctrl"])

;; m1-m2-5 => chatGPT
addRemap("5", ["m1", "m2"], ["appactivate", "ChatGPT.exe"])
;;  'm1-5' fo 4th app
addRemap("5", ["m1"], "4", ["win", "ctrl"])

;;  'm1-6' fo 5th app
addRemap("6", ["m1"], "5", ["win", "ctrl"])

;; m1-m2-7 => Slack
addRemap("7", ["m1", "m2"], ["winactivate", "Slack"])
;;  'm1-7' fo 6th app
addRemap("7", ["m1"], "6", ["win", "ctrl"])

;;  'm1-8' fo 7th app
addRemap("8", ["m1"], "7", ["win", "ctrl"])

;;  'm1-9' fo 8th app
addRemap("9", ["m1"], "8", ["win", "ctrl"])

;;  'm1-m2-0' for Notion
addRemap("0", ["m1", "m2"], ["appactivate", "Notion.exe"])
;;  'm1-0' for 9th app
addRemap("0", ["m1"], "9", ["win", "ctrl"])

;;  'm1-minus' for 10th app
addRemap("-", ["m1"], "0", ["win", "ctrl"])
;;  'm2-minus' for em-dash
addRemap("-", ["m2"], ["send", "—"])

;;  'm1-c-backslash' for game HUD's (GOG, steam etc)
addRemap("vkdc", ["m1", "ctrl"], "tab", ["shift"])
;;  'm1-s-backslash' for notifications.
addRemap("vkdc", ["m1", "shift"], "a", ["win"])
;;  'm1-backslash' for launchpad.
addRemap("vkdc", ["m1"], "lwin")
;;  'm2-backslash' for clear formatting in Google Spreadsheet
addRemap("vkdc", ["m2"], "vkdc", ["ctrl"])
;;  'm3-backslash' for screen lock
addRemap("vkdc", ["m3"], ["lock"])

;;  m1-m2-g for S-F4
addRemap("g", ["m1", "m2"], "vk73", ["shift"])
;;  m1-shift-g for emoji selector
addRemap("g", ["m1", "shift"], ["symbols"])
;;  m1-g for F4
addRemap("g", ["m1"], "vk73")

;;  m1-m2-f for S-F3
addRemap("f", ["m1", "m2"], "vk72", ["shift"])
;;  m1-shift-f switch to 1st language
addRemap("f", ["m1", "shift"], ["lang", "en"])
;;  m1-f for F3
addRemap("f", ["m1"], "vk72")
;;  m2-f for game command
addRemap("f", ["m2"], ["send", "{enter}/exit{enter}"])

;;  m1-m2-d for S-F2
addRemap("d", ["m1", "m2"], "vk71", ["shift"])
;;  m1-shift-d switch to 2nd language
addRemap("d", ["m1", "shift"], ["lang", "ru"])
;;  m1-d for Double Commander 'horizontal panels mode'
addRemap(["d", "app", "doublecmd.exe"], ["m1"], "h", ["ctrl", "shift"])
;;  m1-d for Chrome Bookmarks Bar
addRemap(["d", "app", "chrome.exe"], ["m1"], "b", ["ctrl", "shift"])
;;  m1-d for F2
addRemap("d", ["m1"], "vk71")
;;  m2-d for game command
addRemap("d", ["m2"], ["send", "{enter}/hideout{enter}"])
;;  m3-d for "copy debug to clipboard"
addRemap("d", ["m3"], ["debugcopy"])

;;  'm3-slash' for shift-command-4 (screenshot)
addRemap("vkbf", ["m3"], "s", ["win", "shift"])
;;  'm1-slash' for middle mouse button.
addRemap(["vkbf", "norepeat"], ["m1"], "mbutton")

poeFlasks(key) {
  Send(key)
  Sleep(50)
  ; also trigger guard if life flask ("panic button") is used
  if (key == "b") {
    Send("x")
    Sleep(50)
  }
  Send("+w")
  Sleep(50)
  Send("+e")
  Sleep(50)
  Send("+r")
  Sleep(50)
  Send("+t")
  ; also trigger convocation if life flask ("panic button") is used
  if (key == "b") {
    Sleep(50)
    Send("c")
  }
}

;;  'm1-b' for F8.
addRemap("b", ["m1"], "f8")
;;  "b" triggers flasks in PoE if enabled
addRemap("b", ["s-poe"], poeFlasks)

;;  'm1-v' for F7.
addRemap("v", ["m1"], "f7")

; 'm1-c' for F6.
addRemap("c", ["m1"], "f6")
; 'm2-c' for "record last 30 seconds" game bar function
addRemap("c", ["m2"], "g", ["win", "alt"])

;;  'm1-x' for F5.
addRemap("x", ["m1"], "f5")
;;  "m2-x" for game bar
addRemap("x", ["m2"], "g", ["win"])
;;  "x" triggers flasks in PoE if enabled
addRemap("x", ["s-poe"], poeFlasks)

;;  'm1-m2-u' => top left
addRemap("u", ["m1", "m2"], ["winpos", "topleft"])

;;  'm1-m2-i' => top right
addRemap("i", ["m1", "m2"], ["winpos", "topright"])

;;  'm1-m2-o' => botom right
addRemap("o", ["m1", "m2"], ["winpos", "bottomleft"])

;;  'm1-m2-y' => move window top 1/2 screen
addRemap("y", ["m1", "m2"], ["winpos", "top"])

;;  'm1-m2-n' => move window bottom 1/2 screen
addRemap("n", ["m1", "m2"], ["winpos", "bottom"])

;; m1-m3-n => close window
addRemap("n", ["m1", "m3"], ["winclose"])

;; m1-m2-space => fullscreen
addRemap("space", ["m1", "m2"], ["winpos", "max"])

;;  'm1-m2-m' => left 1/2 screen
addRemap("m", ["m1", "m2"], ["winpos", "left"])

;;  'm1-m2-comma' => right 1/2 screen
addRemap("vkbc", ["m1", "m2"], ["winpos", "right"])

;;  m2-1 for game text
addRemap("1", ["m2"], ["send", "-[rgb]-|nne|rint"])

;;  m2-s-1 for game text
;; FIXME: not working with 'shift'
addRemap("7", ["m2"], ["send", "-\w-.-|r-g-b|r-b-g|b-r-g|b-g-r|g-r-b|g-b-r|rint"])

;;  m2-2 for game text
addRemap("2", ["m2"], ["send", "`"{!}gen|elo|s rec|o al|non`""])

;;  m2-s-2 for game text
;; FIXME: not working with 'shift'
addRemap("6", ["m2"], ["send", "`"{!}gen|elo|s rec|o al|non|ask`""])

;;  m2-3 for game text
addRemap("3", ["m2"], ["send", "`"grand black|exceptional black|coin|the sun|medved|vorana|uhtred|olroth`""])

;;  m2-s-3 for game text
;; FIXME: not working with 'shift'
addRemap("8", ["m2"], ["send", "`"Bone R|Vermil|Amet|Vise|Heavy|Leather B|Crystal B|Convoking|Bone S|Ivory|Fossil|Leviathan|Velour|Warlock|Wyvernscale|Paladin|Phantom|Giantslayer|Majestic|Lich'|Haunted|Divine|Torturer'|Royal|Syndicate'|Twilight|Conquest|Sacred|Necrotic`""])

;;  m2-4 for game text
addRemap("4", ["m2"], ["send", "`"{!}(ap ti|ea le|nt sh|ed sh|r's sh|incu|scar|ch ri|em so)`" `"mirr|ine o|ent o|ted o|of ann|deck|r's p|aos o|regr|chis|foss|reson|cata|sco|aal or|glas|on oi|ck oi|ent oi|ver oi|en oi|envy|drea|scor|zeal|spit|chay|tic o|of fu|of ch|of alc|of ho|ghas`""])

;;  m2-s-4 for game text
;; FIXME: not working with 'shift'
addRemap("5", ["m2"], ["send", "`"{!}(ap ti|ea le|nt sh|ed sh|r's sh|incu|ch ri|ht co)`" `"r of k|ror sh|ine o|r's p|aos o|chis|se fo|al fo|ied fo|ring ca|ile ca|tic ca|on oi|ck oi|ent oi|ver oi|en oi|chay|en su|of conta|of awa|of pre|of cat|of inv|of bloodl|of cal|of corn`""])

;;  Generated by touchpad keyboard edge swipes
addRemap("right", ["win"], ["nothing"])
addRemap("tab", ["win"], ["nothing"])

;;  Used for remote debug purpose
SendMqtt() {
  ctrl_state := GetKeyState("control", "P")

  mqtt_url := EnvGet("MQTT_URL")
  mqtt_user := EnvGet("MQTT_USER")
  mqtt_pass := EnvGet("MQTT_PASS")
  mqtt_cert := EnvGet("MQTT_CERT")

  msg := A_TickCount . " C: " . ctrl_state

  cmd := "mosquitto_pub.exe"
  cmd := cmd . " --host " . mqtt_url
  cmd := cmd . " --port 8883 "
  cmd := cmd . " --cafile " . mqtt_cert
  cmd := cmd . " -u " . mqtt_user
  cmd := cmd . " -P " . mqtt_pass
  cmd := cmd . " -t debug"
  cmd := cmd . " -m `"" . msg . "`""
  run cmd,, "Hide"
}

appHomePath := EnvGet("USERPROFILE")
appIconPath := appHomePath . "\dotfiles\icons"
image_type := 1
appIconMain := LoadPicture(appIconPath . "\ahk.ico",, &image_type)
appIconDebug := LoadPicture(appIconPath . "\ahk_d.ico",, &image_type)
appIconDebugRed := LoadPicture(appIconPath . "\ahk_d_r.ico",, &image_type)
appShowDebugIcon := false

onSlowTimer() {
  global appShowDebugIcon
  if (appShowDebugIcon) {
    ;;  Use '*' to copy icon and don't destroy original on change
    if (appKeysPressed.Count) {
      TraySetIcon("HICON:*" . appIconDebugRed)
    }
    else {
      TraySetIcon("HICON:*" . appIconDebug)
    }
    appShowDebugIcon := false
  }
  else {
    TraySetIcon("HICON:*" . appIconMain)
    appShowDebugIcon := true
  }

  if (appIsDebug) {
    A_IconTip := joinWithSep("`n", [
      "↓",
      appLastKeydown[1],
      mapToStr(appLastKeydown[2], oneline := true),
      "↑",
      appLastKeyup[1],
      mapToStr(appLastKeyup[2], oneline := true),
      mapToStr(appKeysPressed, oneline := true)
    ])
  }
  else {
    A_IconTip := joinWithSep("`n", [
      "enable debug mode to see more",
      "keys state:`n" .  mapToStr(appKeysPressed)
    ])
  }
}

onFastTimer() {

  ; Check that no keys are "stuck"
  ;! Using GetKeyState() is not realiable
  toRemove := []
  for key, keyInfo in appKeysPressed {
    keyInfo["stuck_counter"] += 1
    ; No "keydown" events for 1sec - they are being received periodically
    ; if key is actually pressed down. This means that "key up" event was
    ; missed.
    if (keyInfo["stuck_counter"] > 6) {
      toRemove.Push(key)
    }
  }
  for _, key in toRemove {
    appKeysPressed.Delete(key)
  }
}

; High priority, make sure hotkey threads do not interrupt these and
; change global state mid-flight
SetTimer(onSlowTimer, 500, priority := 100)
SetTimer(onFastTimer, 100, priority := 200)

onDebugModeToggle(name, _, menu) {
  global appIsDebug
  appIsDebug := not appIsDebug
  if (appIsDebug) {
    menu.Check(name)
  }
  else {
    appDebugLog.Length := 0
    menu.Uncheck(name)
  }
}

onPoeModsToggle(name, _, menu) {
  appSettings["s-poe"] := not appSettings["s-poe"]
  if (appSettings["s-poe"]) {
    menu.Check(name)
  }
  else {
    menu.Uncheck(name)
  }
}

onDebugCopy(*) {
  text := ""
  for idx, record in appDebugLog {
    if (idx > 1) {
      text .= "`n"
    }
    text .= record
  }
  A_Clipboard := text
}

readSymolbs() {
  path := A_ScriptDir . "\symbols.csv"
  content := FileOpen(path, "r", "UTF-8").Read()
  for _, line in StrSplit(content, ["`r", "`n"]) {
    if (not RegExMatch(line, "^\s*#")) {
      symbol := ""
      name := ""
      for pos, sub in StrSplit(line, ",") {
        if (pos == 1) {
          symbol := Trim(sub)
        }
        if (pos == 2) {
          name := Trim(sub)
        }
      }
      if (symbol and name) {
        appSymbols.Push([symbol, name])
      }
    }
  }
}

onTests(*) {
  items := []
  sortArray(&items)
  assert(compareArray(items, []), "empty array sort")
  items := [1]
  sortArray(&items)
  assert(compareArray(items, [1]), "single array sort")
  items := [1, 2]
  sortArray(&items)
  assert(compareArray(items, [1, 2]), "sorted array re-sort")
  items := [2, 1]
  sortArray(&items)
  assert(compareArray(items, [1, 2]), "2-array sort")
  items := [3, 2, 1]
  sortArray(&items)
  assert(compareArray(items, [1, 2, 3]), "3-array sort")
}

A_TrayMenu.Add("Debug mode", onDebugModeToggle)
A_TrayMenu.Add("PoE modifications", onPoeModsToggle)
A_TrayMenu.Add("Copy debug to clipboard", onDebugCopy)
A_TrayMenu.Add("Run tests", onTests)
readSymolbs()

; TODO: native C++ COM dll that can press taskbar buttons by index and name
; TODO: Support for both English and Russian typographic quotes depending on
;       the layout
; TODO: remap mouse repeated click on some unused key, not minus
; FIXME: m2-5 followed by m1-p acts like m1-m2-p
