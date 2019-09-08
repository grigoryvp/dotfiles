#SingleInstance force
;;. Using space as dual mode key for alt does not work, since writing
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

remap(direction, from, to1, to2, to3) {
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
      send {%to2% %direction%}
    }
    else if (GetKeyState("tab", "P")) {
      SendInput {%to3% %direction%}
    }
    else {
      send {%to1% %direction%}
    }
  }
  else {
    send {blind}{%from% %direction%}
  }
}

;;  Switch between normal and 'compatible' mode for apps/games that
;;  can't handle multi-key virtual combinations, like "Grim Dawn"
!pgdn::
  path := A_MyDocuments "\..\.box-cfg\keyboard_compat.ahk"
  run autohotkey.exe %path%,, Hide
  Suspend
  return

;;  Use caps lock as 'meta' key to trigger things (caps remapped to f24).
$vked up::
  appLeaderUpTick = %A_TickCount%
  return

;;  caps + enter is middle mouse button
$rctrl::
  ;;  First press since release? (beware repetition)
  if (appReturnUpTick >= appReturnDownTick) {
    appReturnDownTick = %A_TickCount%
  }
  if (GetKeyState("vked", "P")) {
    send {mbutton down}
    ;;  For games where holding mouse button moves something and caps can
    ;;  be released and pressed back while still holding key).
    while (GetKeyState("vked", "P") && GetKeyState("enter", "P")) {
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

;;  ==========================================================================
;;  Keys and combinations remap
;;  ==========================================================================

;;  'meta-open-bracket' for escape (vim-like).
*$[::remap("down", "vkdb", "esc", "vkdb", "vkdb")
*$[ up::remap("up", "vkdb", "esc", "vkdb", "vkdb")

$]::
  if (GetKeyState("vked", "P")) {
    ;;  'meta-close-bracket' for switching between apps
    send !{tab down}
  }
  else {
    send {vkdd down}
  }
  return

$] up::
  if (GetKeyState("vked", "P")) {
    ;;  'meta-close-bracket' for switching between apps
    send !{tab up}
  }
  else {
    send {vkdd up}
  }
  return

$backspace::
  if (GetKeyState("vked", "P")) {
    ;;  'meta-backspace' (delete on osx) for closing apps
    winclose A
  }
  else {
    send {backspace}
  }
  return

*$p::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
      ;;  'meta-shift-p' for deleting things.
      if (WinActive("ahk_exe explorer.exe")) {
        ;;  Explorer monitors physical 'shift' key, so sending 'delete'
        ;;  will trigger whift-delete, which is "permanently delete", while
        ;;  ctrl-d key combination is just 'delte' in most apps.
        send ^d
      }
      else {
        send {delete}
      }
    }
    else {
      ;;  'meta-p' for backspace
      send {backspace}
    }
  }
  else {
    send {blind}{vk50}
  }
  return

;;  'meta-h' for left arrow (vim-like).
;;  'meta-shift-h' for home (vim-like).
;;  'meta-caps-h' for wheel left (but touchpad normally used for pan).
*$h::remap("down", "vk48", "left", "home", "wheelleft")
*$h up::remap("up", "vk48", "left", "home", "wheelleft")

;;  'meta-j' for down arrow (vim-like).
;;  'meta-shift-j' for page down (vim-like).
;;  'meta-caps-j' for wheel down (but touchpad normally used for pan).
*$j::remap("down", "vk4a", "down", "pgdn", "wheeldown")
*$j up::remap("up", "vk4a", "down", "pgdn", "wheeldown")

;;  'meta-k' for up arrow (vim-like).
;;  'meta-shift-k' for page up (vim-like).
;;  'meta-caps-k' for wheel up (but touchpad normally used for pan).
*$k::remap("down", "vk4b", "up", "pgup", "wheelup")
*$k up::remap("up", "vk4b", "up", "pgup", "wheelup")

;;  'meta-l' for right arrow (vim-like).
;;  'meta-shift-l' for end (vim-like).
;;  'meta-caps-l' for wheel right (but touchpad normally used for pan).
*$l::remap("down", "vk4c", "right", "end", "wheelright")
*$l up::remap("up", "vk4c", "right", "end", "wheelright")

*$7::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
      ;;  'meta-s-7' for password manager; run under non-elevated user
      send #^5
    }
    else {
      ;;  'meta-7' for file manager; run under non-elevated user
      send #^1
    }
  }
  else {
    send {blind}{vk37}
  }
  return

*$8::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
      ;;  'meta-s-8' for task manager; run under non-elevated user
      send #^6
    }
    else {
      ;;  'meta-8' for editor; run under non-elevated user
      send #^2
    }
  }
  else {
    send {blind}{vk38}
  }
  return

*$9::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
      ;;  'meta-s-9' for mail and calendar; run under non-elevated user
      send #^7
    }
    else {
      ;;  'meta-9' for browser; run under non-elevated user
      send #^3
    }
  }
  else {
    send {blind}{vk39}
  }
  return

*$0::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
      ;;  'meta-s-0' for slack; run under non-elevated user
      send #^8
    } else {
      ;;  'meta-0' for messenger; run under non-elevated user
      send #^4
    }
  }
  else {
    send {blind}{vk30}
  }
  return

*$-::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
      ;;  Not used
    }
    else {
      ;;  Reserve
      send #^9
    }
  }
  else {
    send {blind}{vkbd}
  }
  return

*$=::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
      ;;  Not used
    }
    else {
      ;;  Reserve
      send #^0
    }
  }
  else {
    send {blind}{vkbb}
  }
  return

*$\::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
      ;;  'meta-s-|' for notifications.
      send #a
    }
    else if (GetKeyState("tab", "P")) {
      ;;  GOG HUD
      send ^+{tab}
    }
    else {
      ;;  'meta-|' for launchpad.
      send {lwin}
    }
  }
  else {
    send {blind}{vkdc}
  }
  return

;;  ==========================================================================
;;  Language switch
;;  ==========================================================================

*$vk34::
  if (GetKeyState("vked", "P")) {
    appLastLangHotkey := "4"
    send ^+4
  }
  else {
    send {blind}{vk34}
  }
  return

*$vk35::
  if (GetKeyState("vked", "P")) {
    appLastLangHotkey := "5"
    send ^+5
  }
  else {
    send {blind}{vk35}
  }
  return

*$vk36::
  if (GetKeyState("vked", "P")) {
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
;; Multi-key combinations
;; ===========================================================================

;;  'meta-shift-y' => top left (third party tool mapped to f13)
*$y::remap("down", "vk59", "vk59", "f13", "vk59")
*$y up::remap("up", "vk59", "vk59", "f13", "vk59")

;;  'meta-shift-u' => bottom left (third party tool mapped to f14)
*$u::remap("down", "vk55", "vk55", "f14", "vk55")
*$u up::remap("up", "vk55", "vk55", "f14", "vk55")

;;  'meta-shift-i' => top right (third party tool mapped to f15)
*$i::remap("down", "vk49", "vk49", "f15", "vk49")
*$i up::remap("up", "vk49", "vk49", "f15", "vk49")

;;  'meta-shift-o' => botom right (third party tool mapped to f16)
*$o::remap("down", "vk4f", "vk4f", "f16", "vk4f")
*$o up::remap("up", "vk4f", "vk4f", "f16", "vk4f")

;;  'meta-shift-n' => left 1/2, 1/3, 2/3 (third party tool mapped to f17)
*$n::remap("down", "vk4e", "vk4e", "f17", "vk4e")
*$n up::remap("up", "vk4e", "vk4e", "f17", "vk4e")

;;  'meta-shift-m' => right 1/2, 1/3, 2/3 (third party tool mapped to f18)
*$m::remap("down", "vk4d", "vk4d", "f18", "vk4d")
*$m up::remap("up", "vk4d", "vk4d", "f18", "vk4d")

;;  'meta-shift-,' => top 1/2, 1/3, 2/3 (third party tool mapped to f19)
*$,::remap("down", "vkbc", "vkbc", "f19", "vkbc")
*$, up::remap("up", "vkbc", "vkbc", "f19", "vkbc")

;;  'meta-shift-.' => bottom 1/2, 1/3, 2/3 (third party tool mapped to f20)
*$.::remap("down", "vkbe", "vkbe", "f20", "vkbe")
*$. up::remap("up", "vkbe", "vkbe", "f20", "vkbe")

;;  'meta-shift-/' => maximize (third party tool mapped to f21)
*$/::remap("down", "vkbf", "vkbf", "f21", "vkbf")
*$/ up::remap("up", "vkbf", "vkbf", "f21", "vkbf")

;; ===========================================================================
;; Left and right mouse buttons
;; ===========================================================================

$vked::
  ;;  First press since release? (beware repetition)
  if (appLeaderUpTick >= appLeaderDownTick) {
    appLeaderDownTick = %A_TickCount%
  }
  ;;  For games like WoW right buttons hold are used for movement, so
  ;;  sometimes caps lock is released while holding tick or semicolon.
  ;;  Holding caps lock again should return button hold.
  if (GetKeyState(";", "P")) {
    send {lbutton down}
    while (GetKeyState("vked", "P") && GetKeyState(";", "P")) {
      Sleep 10
    }
    send {lbutton up}
  }
  else if (GetKeyState("'", "P")) {
    send {rbutton down}
    while (GetKeyState("vked", "P") && GetKeyState("'", "P")) {
      Sleep 10
    }
    send {rbutton up}
  }
  return

;;  'meta-semicolon' for left mouse button.
*$`;::
  if (GetKeyState("vked", "P")) {
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
    while (GetKeyState("vked", "P") && GetKeyState(";", "P")) {
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

;;  'meta-quote' for right mouse button.
*$'::
  if (GetKeyState("vked", "P")) {
    send {rbutton down}
    ;;  For games where holding mouse button moves something and caps can
    ;;  be released and pressed back while still holding key).
    while (GetKeyState("vked", "P") && GetKeyState("'", "P")) {
      Sleep 10
    }
    send {rbutton up}
  }
  else {
    send {blind}{vkde}
  }
  return

;; ===========================================================================
;; Misc
;; ===========================================================================

::sigen::
  ClipBoard := "Best regards,`nGrigory Petrov,`n+7-926-225-16-08`nhttp://facebook.com/grigoryvp"
  send ^v
  return

::sigru::
  ClipBoard := "С уважением,`nГригорий Петров,`n+7-926-225-16-08`nhttp://facebook.com/grigoryvp"
  send ^v
  return

;;  Some keyboards emulate "edge swipes" by sending these key combonations
$#a::
  return
$#down::
  return
$#tab::
  return
