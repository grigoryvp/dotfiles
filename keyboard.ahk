#SingleInstance force
;;  . Using space as dual mode key for alt does not work, since writing
;;    text fast always triggers alt-key hotkeys (google docs etc).
;;  . Using caps lock as dual mode key for backspace does not work since
;;    it's often mispressed and "backspace" do terrible things like
;;    deleting items and so on.
;;  . Using 'caps lock' as leader is better than 'tab' since leader is
;;    used a lot to emulate arrows, wheel and clicks, while left control
;;    (which caps lock originally was replaced to) is used much less,
;;    mostly as C-[ for escape in VIM, but leader-[ is also an escape,
;;    so nothing changes.
;;  . 'ctrl-;' is used in Chrome for debugging, so it's not used as
;;    ctrl-click shortcut which is rare and 'tab+ctrl' can be holded for it.
;;  . leaving backspace "as is" simply don't work: it's too far away.
;;  . Windows detects physical shift while pressing shift-del, so keeping
;;    "del" as leader-shift-/ is not viable, it is detected as "skip recycle
;;    bin". Instead, leader-p is mapped to backspace, leader-shift-p to
;;    ctrl-backspace (delete word) and leader-p to "delete".
;;  - DllCall("mouse_event", "UInt", 0x800, "UInt", 0, "UInt", 0, "UInt", 120)
;;    for mouse wheel will not work, on modern Windows it was replaced with
;;    SendInput.
;;  - It's better to remap 'caps lock' to some not-used keys (like F20)
;;    using Windows registry and use that resulting key. Such trick prevents
;;    caps lock from triggering in situations where keyboard hook is not
;;    working (UAC, lock screen, "Grim Dawn" etc).

codepage = 65001 ; utf-8
appLastLangHotkey := ""
appLeaderDownTick = 0
appLeaderUpTick = 0
appEnterDownTick = 0
appEnterUpTick = 0

if !A_IsAdmin {
  Run *RunAs "%A_ScriptFullPath%"
  ExitApp
}

;;  No warning if key is hold for 2 seconds (HotkeyInterval)
#MaxHotkeysPerInterval 500

#inputlevel 1
tab::lctrl
enter::rctrl
#inputlevel 0

;;  caps + enter is middle mouse button
$rctrl::
  ;;  First press since release? (beware repetition)
  if (appReturnUpTick >= appReturnDownTick) {
    appReturnDownTick = %A_TickCount%
  }
  if (GetKeyState("f20", "P")) {
    send {mbutton down}
    ;;  For games where holding mouse button moves something and caps can
    ;;  be released and pressed back while still holding key).
    while (GetKeyState("f20", "P") && GetKeyState("enter", "P")) {
      Sleep 10
    }
    send {mbutton up}
  }
  return

$rctrl up::
  appReturnUpTick = %A_TickCount%
  send {rctrl up}
  if (A_PriorKey = "RControl") {
    ;;  No 'caps lock' was released after return was pressed? (protect
    ;;  against accidental caps lock release while enter is used with it).
    if (appLeaderUpTick < appReturnDownTick) {
      send {enter}
    }
  }
  return

;;  Single tab press = tab
$lctrl up::
  send {lctrl up}
  if (A_PriorKey = "LControl") {
    send {tab}
  }
  return

$^rctrl up:: send ^{enter}
$+rctrl up:: send +{enter}
$^lctrl up:: send ^{tab}

;; ===========================================================================
;; Language switch
;; ===========================================================================

*$vk34::
  if (GetKeyState("f20", "P")) {
    appLastLangHotkey := "4"
    send ^+4
  }
  else {
    send {blind}{vk34}
  }
  return

*$vk35::
  if (GetKeyState("f20", "P")) {
    appLastLangHotkey := "5"
    send ^+5
  }
  else {
    send {blind}{vk35}
  }
  return

*$vk36::
  if (GetKeyState("f20", "P")) {
    if (appLastLangHotkey = "6") {
      ;;  Switch between Hiragana and Latin input for Japanese keyboard
      send !``
    }
    else {
      appLastLangHotkey := "6"
      send ^+6
    }
  }
  else {
    send {blind}{vk36}
  }
  return

;; ===========================================================================
;; Keys and combinations remap
;; ===========================================================================

$[::
  if (GetKeyState("f20", "P")) {
    send {esc}
  }
  else {
    send {vkdb}
  }
  return

*$/::
  if (GetKeyState("f20", "P")) {
    if (GetKeyState("shift", "P")) {
      send +{delete}
    }
    else {
      send {delete}
    }
  }
  else {
    send {blind}{vkbf}
  }
  return

$]::
  if (GetKeyState("f20", "P")) {
    send !{tab}
  }
  else {
    send {vkdd}
  }
  return

*$\::
  if (GetKeyState("f20", "P")) {
    if (GetKeyState("shift", "P")) {
      send #a
    }
    else {
      send {lwin}
    }
  }
  else {
    send {blind}{vkdc}
  }
  return

*$7::
  if (GetKeyState("f20", "P")) {
    send #1
  }
  else {
    send {blind}{vk37}
  }
  return

*$8::
  if (GetKeyState("f20", "P")) {
    ;;  Run under non-elevated user
    send #2
  }
  else {
    send {blind}{vk38}
  }
  return

*$9::
  if (GetKeyState("f20", "P")) {
    ;;  Run under non-elevated user
    send #3
  }
  else {
    send {blind}{vk39}
  }
  return

*$0::
  if (GetKeyState("f20", "P")) {
    ;;  Run under non-elevated user
    send #4
  }
  else {
    send {blind}{vk30}
  }
  return

*$-::
  if (GetKeyState("f20", "P")) {
    if (GetKeyState("shift", "P")) {
      ;;  Restore from tray if "allow only one instance" option is set"
      Run KeePass.exe,, hide
      WinActivate, ahk_exe KeePass.exe
    }
    else {
      ;;  Run under non-elevated user
      send #5
    }
  }
  else {
    send {blind}{vkbd}
  }
  return

*$=::
  if (GetKeyState("f20", "P")) {
    if (GetKeyState("shift", "P")) {
      send #e
    }
    else {
      ;;  Run under non-elevated user
      send #6
    }
  }
  else {
    send {blind}{vkbb}
  }
  return

$backspace::
  if (GetKeyState("f20", "P")) {
    wingetactivetitle, title
    if (instr(title, "KeePass")) {
      winminimize A
    }
    else {
      winclose A
    }
  }
  else {
    send {backspace}
  }
  return

$home::
  if (GetKeyState("f20", "P")) {
    winmaximize A
  }
  else {
    send 7
  }
  return

*$h::
  if (GetKeyState("f20", "P")) {
    if (GetKeyState("shift", "P")) {
      SendInput {wheelleft}
    }
    else if (GetKeyState("tab", "P")) {
      send {home}
    }
    else {
      send {left}
    }
  }
  else {
    send {blind}{vk48}
  }
  return
*$j::
  if (GetKeyState("f20", "P")) {
    if (GetKeyState("shift", "P")) {
      Send {wheeldown}
    }
    else if (GetKeyState("tab", "P")) {
      send {pgdn}
    }
    else {
      send {down}
    }
  }
  else {
    send {blind}{vk4a}
  }
  return
*$k::
  if (GetKeyState("f20", "P")) {
    if (GetKeyState("shift", "P")) {
      Send {wheelup}
    }
    else if (GetKeyState("tab", "P")) {
      send {pgup}
    }
    else {
      send {up}
    }
  }
  else {
    send {blind}{vk4b}
  }
  return
*$l::
  if (GetKeyState("f20", "P")) {
    if (GetKeyState("shift", "P")) {
      SendInput {wheelright}
    }
    else if (GetKeyState("tab", "P")) {
      send {end}
    }
    else {
      send {right}
    }
  }
  else {
    send {blind}{vk4c}
  }
  return

*$p::
  if (GetKeyState("f20", "P")) {
    if (GetKeyState("shift", "P")) {
      send ^{backspace}
    }
    else {
      send {backspace}
    }
  }
  else {
    send {blind}{vk50}
  }
  return

!`::
  path := A_MyDocuments "\..\.box-cfg\keyboard_compat.ahk"
  run autohotkey.exe %path%,, Hide
  Suspend
  return

;;  Some keyboards emulate "edge swipes" by sending these key combonations
$#a::
  return
$#down::
  return
$#tab::
  return

;; ===========================================================================
;; Left and right mouse buttons
;; ===========================================================================

$f20::
  ;;  First press since release? (beware repetition)
  if (appLeaderUpTick >= appLeaderDownTick) {
    appLeaderDownTick = %A_TickCount%
  }
  ;;  For games like WoW right buttons hold are used for movement, so
  ;;  sometimes caps lock is released while holding tick or semicolon.
  ;;  Holding caps lock again should return button hold.
  if (GetKeyState(";", "P")) {
    send {lbutton down}
    while (GetKeyState("f20", "P") && GetKeyState(";", "P")) {
      Sleep 10
    }
    send {lbutton up}
  }
  else if (GetKeyState("'", "P")) {
    send {rbutton down}
    while (GetKeyState("f20", "P") && GetKeyState("'", "P")) {
      Sleep 10
    }
    send {rbutton up}
  }
  return

$f20 up::
  appLeaderUpTick = %A_TickCount%
  return

;;  caps + ; is left mouse button
*$`;::
  if (GetKeyState("f20", "P")) {
    if (GetKeyState("tab", "P") && GetKeyState("shift", "P")) {
      send ^+{lbutton down}
    }
    else if (GetKeyState("tab", "P")) {
      send ^{lbutton down}
    }
    else if (GetKeyState("shift", "P")) {
      send +{lbutton down}
    }
    else if (GetKeyState("alt", "P")) {
      send !{lbutton down}
    }
    else {
      send {lbutton down}
    }

    ;;  For games where holding mouse button moves something and caps can
    ;;  be released and pressed back while still holding key).
    while (GetKeyState("f20", "P") && GetKeyState(";", "P")) {
      Sleep 10
    }

    ;;! Sending button up with modifier key requires for apps like
    ;;  mspaint to correctly detect shift+drag followed by release and
    ;;  for chrome to correctly detect shift-click
    if (GetKeyState("tab", "P") && GetKeyState("shift", "P")) {
      send ^+{lbutton up}
    }
    if (GetKeyState("tab", "P")) {
      send ^{lbutton up}
    }
    else if (GetKeyState("shift", "P")) {
      send +{lbutton up}
    }
    else if (GetKeyState("alt", "P")) {
      send !{lbutton up}
    }
    else {
      send {lbutton up}
    }
  }
  else {
    send {blind}{vkba}
  }
  return

;;  caps + ' is right mouse button
*$'::
  if (GetKeyState("f20", "P")) {
    send {rbutton down}
    ;;  For games where holding mouse button moves something and caps can
    ;;  be released and pressed back while still holding key).
    while (GetKeyState("f20", "P") && GetKeyState("'", "P")) {
      Sleep 10
    }
    send {rbutton up}
  }
  else {
    send {blind}{vkde}
  }
  return

::sigen::
  ClipBoard := "Best regards,`nGrigory Petrov,`n+7-926-225-16-08`nhttp://facebook.com/grigoryvp"
  send ^v
  return

::sigru::
  ClipBoard := "С уважением,`nГригорий Петров,`n+7-926-225-16-08`nhttp://facebook.com/grigoryvp"
  send ^v
  return
