#Requires AutoHotkey v2
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

codepage := 65001 ; utf-8
;;  Map of all remap configurations
appRemap := Map()
appLastLang := ""
appLeaderUpTick := 0
appLeaderDownTick := 0
;;  Separate flags for alt down emulation with m2 while m1 is
;;  pressed and m1 while m2 is pressed. This is used to ensure
;;  that the same key that set alt down will also put it up and do nothing
;;  else. Otherwise it's possible to down m1, down m2 (holds alt),
;;  up m1 (incorrectly releases alt), up m2 (incorrectly triggers esc).
appAltHoldByM1 := false
appAltHoldByM2 := false

if (!A_IsAdmin) {
  Run "*RunAs" A_ScriptFullPath
  ExitApp
}

;;  No warning if key is hold for 2 seconds (HotkeyInterval)
A_MaxHotkeysPerInterval := 500

;;  F5 (meata-x) for game bar
f5::send "#g"
;;  F6 (m1-c) for "record last 30 seconds" game bar function
f6::send "#!g"

repeatStr(times, str) {
  res := ""
  loop times
    res .= str
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

mapToStr(map, indent := 0) {
  res := "{`n"
  for key, val in map {
    padding := repeatStr(indent + 2, " ")
    if (IsObject(val)) {
      res .= padding . key . ": " . mapToStr(val, indent + 2) . ",`n"
    } else {
      if (Type(val) == "String") {
        res .= padding . key . ": `"" . val . "`",`n"
      } else {
        res .= padding . key . ": " . val . ",`n"
      }
    }
  }
  return res . repeatStr(indent, " ") . "}"
}

;;  TODO: add in correct order (ex "m1" + "shift" before "m1")
addRemap(from, fromMods, to, toMods := []) {
  config := Map("from_mods", fromMods, "to", to, "to_mods", toMods)
  if (appRemap.has(from)) {
    appRemap[from].push(config)
  }
  else {
    appRemap[from] := [config]
  }
}

;;  Receives the list of modifiers like ["m1", "shift"] and evaluates to
;;  true if the corresponding keys are pressed
modsPressed(mods) {
  for i, modName in mods {
    if (modName == "m1") {
      if (not GetKeyState("vked", "P")) {
        return false
      }
    }
    else if (modName == "m2") {
      ;;  left alt, which is remapped to esc
      if (not GetKeyState("esc", "P")) {
        return false
      }
    }
    else if (modName == "m3") {
      ;;  right alt, which is remapped to return
      if (not GetKeyState("enter", "P")) {
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
      ;;  TODO: assertion
    }
  }
  return res
}

;;  Given list of maps describing monitors evaluate to the index in that
;;  list where the window specified by the description is located
monitorFromWnd(monitors, wnd) {
  for monitorIdx, monitor in monitors {
    if (
      wnd["right"] > monitor["left"] and
      wnd["left"] < monitor["right"] and
      wnd["top"] < monitor["bottom"] and
      wnd["bottom"] > monitor["top"]
    ) {
      return monitorIdx
    }
  }
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
  if (pos == "topleft") {
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
    ;;  assert
  }
}

setCurWinMon(dir) {
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

switchToLang(lang) {
  if (lang == "en") {
    send("^+4")
  }
  else if (lang == "ru") {
    send("^+5")
  }
  else if (lang == "jp") {
    if (appLastLang == "jp") {
      ;;  Switch between Hiragana and Latin input for Japanese keyboard
      send "!``"
    }
    else {
      send("^+6")
    }
  }
  global appLastLang
  appLastLang := lang
}

onKeyCommand(items) {
  command := items.RemoveAt(1)
  if (command == "winclose") {
    winclose "A"
  }
  if (command == "delete") {
    if (WinActive("ahk_exe explorer.exe")) {
      ;;  Explorer monitors physical 'shift' key, so sending 'delete'
      ;;  will trigger whift-delete, which is "permanently delete", while
      ;;  ctrl-d key combination is just 'delte' in most apps.
      send "^d"
    }
    else {
      send "{delete}"
    }
  }
  else if (command == "send") {
    input := items.RemoveAt(1)
    Send(input)
  }
  else if (command == "winpos") {
    pos := items.RemoveAt(1)
    setCurWinPos(pos)
  }
  else if (command == "winmon") {
    dir := items.RemoveAt(1)
    setCurWinMon(dir)
  }
  else if (command == "lang") {
    lang := items.RemoveAt(1)
    switchToLang(lang)
  }
  else {
    ;;  assert
  }
}

; TODO: enable debug mode to OutputDebug()
onKey(key, dir) {
  if (appRemap.has(key)) {
    for _, config in appRemap[key] {
      fromMods := config["from_mods"]
      if (modsPressed(fromMods)) {
        to := config["to"]
        if (Type(to) == "String") {
          mods := modsToStr(config["to_mods"])
          send mods . "{" . to . " " . dir . "}"
          return
        }
        else if (Type(to) == "Array") {
          if (dir == "up") {
            onKeyCommand(to.Clone())
          }
          ;; skip original key behaviour on "down"
          return
        }
        else {
          ;; assertion
        }
      }
    }
  }
  send "{blind}{" . key . " " . dir . "}"
}

onKeydown(key) {
  onKey(key, "down")
}

onKeyup(key) {
  onKey(key, "up")
}

;;  Use caps lock as 'm1' key to trigger things (caps remapped to f24).
$vked:: {
  ;;  First press since release? (beware repetition)
  if (appLeaderUpTick >= appLeaderDownTick) {
    global appLeaderDownTick
    appLeaderDownTick := A_TickCount
  }
  ;;  For games like WoW right buttons hold are used for movement, so
  ;;  sometimes caps lock is released while holding tick or semicolon.
  ;;  Holding caps lock again should enter button hold.
  if (GetKeyState(";", "P")) {
    send "{lbutton down}"
    while (GetKeyState("vked", "P") && GetKeyState(";", "P")) {
      Sleep 10
    }
    send "{lbutton up}"
  }
  else if (GetKeyState("'", "P")) {
    send "{rbutton down}"
    while (GetKeyState("vked", "P") && GetKeyState("'", "P")) {
      Sleep 10
    }
    send "{rbutton up}"
  }
  else if (GetKeyState("/", "P")) {
    send "{mbutton down}"
    while (GetKeyState("vked", "P") && GetKeyState("/", "P")) {
      Sleep 10
    }
    send "{mbutton up}"
  }
  ;;  m1+m2+shift for left alt (while using external mouse)
  else if (GetKeyState("esc", "P") and GetKeyState("lshift", "P")) {
    global appAltHoldByM1
    appAltHoldByM1 := true
    send "{lalt down}"
  }
}

;;  Use caps lock as 'm1' key to trigger things (caps remapped to f24).
$vked up:: {
  global appLeaderUpTick
  appLeaderUpTick := A_TickCount

  global appAltHoldByM1
  ;;  m1+m2 for left alt (while using external mouse)
  if (appAltHoldByM1) {
    appAltHoldByM1 := false
    send "{lalt up}"
  }
}

;;  Supress rshift+caps that produces char codes in chrome and erases
;;  cell content in spreadsheets while switching language via m1-s-f.
$+vked:: {
  global appLeaderDownTick
  if (appLeaderUpTick >= appLeaderDownTick) {
    appLeaderDownTick := A_TickCount
  }
}
$+vked up:: {
  global appLeaderUpTick
  appLeaderUpTick := A_TickCount
}

*$esc:: {
  ;;  m1+m2+shift for left alt (while using external mouse)
  if (GetKeyState("vked", "P") and GetKeyState("lshift", "P")) {
    global appAltHoldByM2
    appAltHoldByM2 := true
    send "{lalt down}"
  }
  ;;  m2 + shift for holding esc
  else if (GetKeyState("lshift", "P")) {
    send "{esc down}"
  }
}

;;  Single esc (lalt) press => esc, otherwise it's m2
*$esc up:: {
  ;;  m1+m2+shift for left alt (while using external mouse)
  if (appAltHoldByM2) {
    global appAltHoldByM2
    appAltHoldByM2 := false
    send "{lalt up}"
  }
  ;;  m2+shift for holding esc
  else if (GetKeyState("lshift", "P")) {
    send "{esc up}"
  }
  else if (A_PriorKey == "Escape") {
    send "{esc}"
  }
}

;;  Single enter (ralt) press => enter, otherwise it's m3
*$enter up:: {
  if (A_PriorKey == "Enter") {
    send "{enter}"
  }
}

;;  Single tab press => tab
~$lctrl up:: {
  if (A_PriorKey == "LControl") {
    send "{tab}"
  }
  else if (GetKeyState("rctrl", "P")) {
    send "^{tab}"
  }
}

;;  'Enter' up
~$rctrl up:: {
  if (A_PriorKey == "RControl") {
    send "{enter}"
  }
  else if (GetKeyState("lctrl", "P")) {
    send "^{enter}"
  }
  else if (GetKeyState("lshift", "P")) {
    send "+{enter}"
  }
}

;;  ==========================================================================
;;  Keys and combinations remap
;;  ==========================================================================

;;  'm1-open-bracket' for escape (vim-like).
addRemap("vkdb", ["m1"], "esc")
*$[::onKeydown("vkdb")
*$[ up::onKeyup("vkdb")

;;  'm1-m2-.' => move window top 1/2 display
addRemap("vkbe", ["m1", "m2"], ["winpos", "top"])
;;  'm1-.' for mouse button 4 (scroll)
addRemap("vkbe", ["m1"], "xbutton1")
*$.::onKeydown("vkbe")
*$. up::onKeyup("vkbe")

;;  'm1-shift-h' for shift-left-arrow (vim-like + selection modify).
addRemap("vk48", ["m1", "shift"], "left", ["shift"])
;;  'm1-h' for left arrow (vim-like).
addRemap("vk48", ["m1"], "left")
*$h::onKeydown("vk48")
*$h up::onKeyup("vk48")

;;  'm1-m2-j' move window one monitor down
addRemap("vk4a", ["m1", "m2"], ["winmon", "down"])
;;  'm1-shift-j' for shift-down-arrow (vim-like + selection modify).
addRemap("vk4a", ["m1", "shift"], "down", ["shift"])
;;  'm1-j' for down arrow (vim-like).
addRemap("vk4a", ["m1"], "down")
*$j::onKeydown("vk4a")
*$j up::onKeyup("vk4a")

;;  'm1-m2-k' move window one monitor up
addRemap("vk4b", ["m1", "m2"], ["winmon", "up"])
;;  'm1-shift-k' for shift-up-arrow (vim-like + selection modify).
addRemap("vk4b", ["m1", "shift"], "up", ["shift"])
;;  'm1-k' for up arrow (vim-like).
addRemap("vk4b", ["m1"], "up")
*$k::onKeydown("vk4b")
*$k up::onKeyup("vk4b")

;;  'm1-shift-l' for shift-right-arrow (vim-like + selection modify).
addRemap("vk4c", ["m1", "shift"], "right", ["shift"])
;;  'm1-l' for right arrow (vim-like).
addRemap("vk4c", ["m1"], "right")
*$l::onKeydown("vk4c")
*$l up::onKeyup("vk4c")

;;  'm1-w' for home.
addRemap("vk57", ["m1"], "home")
*$w::onKeydown("vk57")
*$w up::onKeyup("vk57")

;;  'm1-e' for page down.
addRemap("vk45", ["m1"], "pgdn")
;;  'm2-e' for email
addRemap("vk45", ["m2"], ["send", "grigoryvp{@}gmail.com"])
*$e::onKeydown("vk45")
*$e up::onKeyup("vk45")

;;  'm1-r' for page up.
addRemap("vk52", ["m1"], "pgup")
*$r::onKeydown("vk52")
*$r up::onKeyup("vk52")

;;  'm1-t' for end.
addRemap("vk54", ["m1"], "end")
*$t::onKeydown("vk54")
*$t up::onKeyup("vk54")

;;  'm1-x' for F5.
addRemap("vk58", ["m1"], "f5")
*$x::onKeydown("vk58")
*$x up::onKeyup("vk58")

;;  'm1-c' for F6.
addRemap("vk43", ["m1"], "f6")
*$c::onKeydown("vk43")
*$c up::onKeyup("vk43")

;;  'm1-v' for F7.
addRemap("vk56", ["m1"], "f7")
*$v::onKeydown("vk56")
*$v up::onKeyup("vk56")

;;  'm1-b' for F8.
addRemap("vk42", ["m1"], "f8")
*$b::onKeydown("vk42")
*$b up::onKeyup("vk42")

;;  'm1-c-backslash' for game HUD's (GOG, steam etc)
addRemap("vkdc", ["m1", "ctrl"], "tab", ["shift"])
;;  'm1-s-backslash' for notifications.
addRemap("vkdc", ["m1", "shift"], "a", ["win"])
;;  'm1-backslash' for launchpad.
addRemap("vkdc", ["m1"], "lwin")
*$\::onKeydown("vkdc")
*$\ up::onKeyup("vkdc")

;;  ==========================================================================
;;  App launcher
;;  ==========================================================================

;;  'm1-2' fo 1st app
addRemap("vk32", ["m1"], "1", ["win", "ctrl"])
*$2::onKeydown("vk32")
*$2 up::onKeyup("vk32")

;;  'm1-3' fo 2nd app
addRemap("vk33", ["m1"], "2", ["win", "ctrl"])
*$3::onKeydown("vk33")
*$3 up::onKeyup("vk33")

;;  'm1-4' fo 3rd app
addRemap("vk34", ["m1"], "3", ["win", "ctrl"])
*$4::onKeydown("vk34")
*$4 up::onKeyup("vk34")

;;  'm1-5' fo 4th app
addRemap("vk35", ["m1"], "4", ["win", "ctrl"])
*$5::onKeydown("vk35")
*$5 up::onKeyup("vk35")

;;  'm1-6' fo 5th app
addRemap("vk36", ["m1"], "5", ["win", "ctrl"])
*$6::onKeydown("vk36")
*$6 up::onKeyup("vk36")

;;  'm1-7' fo 6th app
addRemap("vk37", ["m1"], "6", ["win", "ctrl"])
*$7::onKeydown("vk37")
*$7 up::onKeyup("vk37")

;;  'm1-8' fo 7th app
addRemap("vk38", ["m1"], "7", ["win", "ctrl"])
*$8::onKeydown("vk38")
*$8 up::onKeyup("vk38")

;;  'm1-9' fo 8th app
addRemap("vk39", ["m1"], "8", ["win", "ctrl"])
*$9::onKeydown("vk39")
*$9 up::onKeyup("vk39")

;;  'm1-0' for 9th app
addRemap("vk30", ["m1"], "9", ["win", "ctrl"])
*$0::onKeydown("vk30")
*$0 up::onKeyup("vk30")

;;  'm1-minus' for 10th app
addRemap("vkbd", ["m1"], "0", ["win", "ctrl"])
;;  'm2-minus' for em-dash
addRemap("vkbd", ["m2"], ["send", "—"])
*$-::onKeydown("vkbd")
*$- up::onKeyup("vkbd")

;;  ==========================================================================
;;  Language switch
;;  ==========================================================================

;;  m1-m2-g for S-F4
addRemap("vk47", ["m1", "m2"], "vk73", ["shift"])
;;  m1-shift-g for emoji selector
addRemap("vk47", ["m1", "shift"], "vkbe", ["win"])
;;  m1-g for F4
addRemap("vk47", ["m1"], "vk73")
*$g::onKeydown("vk47")
*$g up::onKeyup("vk47")

;;  m1-m2-f for S-F3
addRemap("vk46", ["m1", "m2"], "vk72", ["shift"])
;;  m1-shift-f switch to 1st language
addRemap("vk46", ["m1", "shift"], ["lang", "en"])
;;  m1-f for F3
addRemap("vk46", ["m1"], "vk72")
;;  m2-f for game command
addRemap("vk46", ["m2"], ["send", "{enter}/exit{enter}"])
*$f::onKeydown("vk46")
*$f up::onKeyup("vk46")

;;  m1-m2-d for S-F2
addRemap("vk44", ["m1", "m2"], "vk71", ["shift"])
;;  m1-shift-d switch to 2nd language
addRemap("vk44", ["m1", "shift"], ["lang", "ru"])
;;  m1-d for F2
addRemap("vk44", ["m1"], "vk71")
;;  m2-d for game command
addRemap("vk44", ["m2"], ["send", "{enter}/hideout{enter}"])
*$d::onKeydown("vk44")
*$d up::onKeyup("vk44")

;;  m1-m2-s for S-F1
addRemap("vk53", ["m1", "m2"], "vk70", ["shift"])
;;  m1-shift-s switch to 3nd language
addRemap("vk53", ["m1", "shift"], ["lang", "jp"])
;;  m1-s for F1
addRemap("vk53", ["m1"], "vk70")
;;  m2-s for english signature
addRemap("vk53", ["m2"], ["send", "Best regards, {enter}Grigory Petrov,{enter}{+}31681345854{enter}{@}grigoryvp"])
*$s::onKeydown("vk53")
*$s up::onKeyup("vk53")

;;  ==========================================================================
;;  Fast text entry
;;  TODO: check if game is foreground for "send"
;;  ==========================================================================

;;  m2-1 for game text 1
addRemap("1", ["m2"], ["send", "-[rgb]-|nne|rint"])
*$1::onKeydown("1")
*$1 up::onKeyup("1")

;;  m2-q for game text 2
addRemap("q", ["m2"], ["send", "-\w-.-|r-g-b|r-b-g|b-r-g|b-g-r|g-r-b|g-b-r|rint"])
*$q::onKeydown("q")
*$q up::onKeyup("q")

;; ===========================================================================
;; Multi-key combinations
;; ===========================================================================

;;  'm1-m2-u' => top left
addRemap("vk55", ["m1", "m2"], ["winpos", "topleft"])
*$u::onKeydown("vk55")
*$u up::onKeyup("vk55")

;;  'm1-m2-i' => top right
addRemap("vk49", ["m1", "m2"], ["winpos", "topright"])
*$i::onKeydown("vk49")
*$i up::onKeyup("vk49")

;;  'm1-m2-o' => botom right
addRemap("vk4f", ["m1", "m2"], ["winpos", "bottomleft"])
*$o::onKeydown("vk4f")
*$o up::onKeyup("vk4f")

;;  'm1-m2-p' => bottom right
addRemap("vk50", ["m1", "m2"], ["winpos", "bottomright"])
;;  'm1-m3-p' for deleting things.
addRemap("vk50", ["m1", "m3"], ["delete"])
;;  'm1-p' for backspace
addRemap("vk50", ["m1"], "backspace")
*$p::onKeydown("vk50")
*$p up::onKeyup("vk50")

;; m1-m3-n => close window
addRemap("vk4e", ["m1", "m3"], ["winclose"])
*$n::onKeydown("vk4e")
*$n up::onKeyup("vk4e")

;; m1-m2-space => fullscreen
addRemap("vk20", ["m1", "m2"], ["winpos", "max"])
*$space::onKeydown("vk20")
*$space up::onKeyup("vk20")

;;  'm1-m2-m' => left 1/2 screen
addRemap("vk4d", ["m1", "m2"], ["winpos", "left"])
*$m::onKeydown("vk4d")
*$m up::onKeyup("vk4d")

;;  'm1-m2-comma' => right 1/2 screen
addRemap("vkbc", ["m1", "m2"], ["winpos", "right"])
*$,::onKeydown("vkbc")
*$, up::onKeyup("vkbc")

;; ===========================================================================
;; Left, right and middle mouse buttons
;; ===========================================================================

;;  'm1-semicolon' for left mouse button.
*$;:: {
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("lctrl", "P") && GetKeyState("shift", "P")) {
      send "^+{lbutton down}"
    }
    else if (GetKeyState("lctrl", "P")) {
      send "^{lbutton down}"
    }
    else if (GetKeyState("shift", "P")) {
      send "+{lbutton down}"
    }
    else if (GetKeyState("escape", "P")) {
      send "!{lbutton down}"
    }
    else {
      send "{lbutton down}"
    }

    ;;  For games where holding mouse button moves something and caps can
    ;;  be released and pressed back while still holding key).
    while (GetKeyState("vked", "P") && GetKeyState(";", "P")) {
      Sleep 10
    }

    ;;! Sending button up with modifier key requires for apps like
    ;;  mspaint to correctly detect shift+drag followed by release and
    ;;  for chrome to correctly detect shift-click
    if (GetKeyState("lctrl", "P") && GetKeyState("shift", "P")) {
      send "^+{lbutton up}"
    }
    if (GetKeyState("lctrl", "P")) {
      send "^{lbutton up}"
    }
    else if (GetKeyState("shift", "P")) {
      send "+{lbutton up}"
    }
    else if (GetKeyState("escape", "P")) {
      send "!{lbutton up}"
    }
    else {
      send "{lbutton up}"
    }
  }
  else {
    send "{blind}{vkba}"
  }
}

;;  'm1-quote' for right mouse button.
*$':: {
  if (GetKeyState("vked", "P")) {
    send "{rbutton down}"
    ;;  For games where holding mouse button moves something and caps can
    ;;  be released and pressed back while still holding key).
    while (GetKeyState("vked", "P") && GetKeyState("'", "P")) {
      Sleep 10
    }
    send "{rbutton up}"
  }
  else {
    send "{blind}{vkde}"
  }
}

;;  'm1-slash' for middle mouse button.
*$/:: {
  if (GetKeyState("vked", "P")) {
    send "{mbutton down}"
    ;;  For games where holding mouse button moves something and caps can
    ;;  be released and pressed back while still holding key).
    while (GetKeyState("vked", "P") && GetKeyState("/", "P")) {
      Sleep 10
    }
    send "{mbutton up}"
  }
  else {
    send "{blind}{vkbf}"
  }
}

;; ===========================================================================
;; Misc
;; ===========================================================================

;;  Some keyboards emulate "edge swipes" by sending these key combonations
$#a:: {
}
$#down:: {
}
$#tab:: {
}


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
appShowDebugIcon := false

;;  The AutoHotkey interpreter does not exist, re-specify in'Settings-AutoHotkey2.InterpreterPath'
;;  TODO: PR for https://github.com/thqby/vscode-autohotkey2-lsp to support ${userHome} for InterpreterPath
OnTimer() {

  global appShowDebugIcon
  if (appShowDebugIcon) {
    ;;  Use '*' to copy icon and don't destroy original on change
    TraySetIcon("HICON:*" . appIconDebug)
    appShowDebugIcon := false
  }
  else {
    TraySetIcon("HICON:*" . appIconMain)
    appShowDebugIcon := true
  }

}

SetTimer(OnTimer, 500)

;; TODO: url shortener on context menu
;; TODO: debug mode for context menu
