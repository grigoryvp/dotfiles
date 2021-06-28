#SingleInstance force ;; Auto-reload
#NoEnv ;; Do not substitute env var value on unbound identifier access.
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
;;. One-finger scroll is used too often for meta-]: too much load for pinkey,
;;  so it's better to move it to something that is easier to hold, ex
;;  meta-.

codepage := 65001 ; utf-8
appLastLangHotkey := ""
appLeaderDownTick := 0
appLeaderUpTick := 0
appEnterDownTick := 0
appEnterUpTick := 0
appReturnUpTick := 0
appReturnDownTick := 0

if (!A_IsAdmin) {
  Run *RunAs "%A_ScriptFullPath%"
  ExitApp
}

;;  No warning if key is hold for 2 seconds (HotkeyInterval)
#MaxHotkeysPerInterval 500

#inputlevel 1
tab::lctrl
enter::rctrl
backspace::ralt
#inputlevel 0

perform(cmd, arg, direction) {
  if (cmd = "winclose") {
    winclose A
  }
  else if (cmd = "winmaximize") {
    winmaximize A
  }
  ;;  Delete things.
  else if (cmd = "delete") {
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
  ;;  Do nothing (ex for remapping key up action)
  else if (cmd = "none") {
  }
  ;;  Default remap is 'send' with modifier and direction.
  else {
    send %cmd%{%arg% %direction%}
  }
}

;;  Remap keydown (direction 'down') or keyup (direction 'up') from key
;;  specified by 'from' into different things to do. Each thing is specified
;;  with modifier and 'to'-clause. If modifier is an empty string (default),
;;  'to'-clause specifies a key to remap. If modifier is reserved string
;;  see 'perform' implementation. If modifier is ahk key modifier (like '^')
;;  it is used as modified for key remap.
remap(direction, from, mod1, to1, mod2, to2, mod3, to3) {
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
      perform(mod2, to2, direction)
    }
    else if (GetKeyState("tab", "P")) {
      perform(mod3, to3, direction)
    }
    else {
      perform(mod1, to1, direction)
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
  else if (GetKeyState("/", "P")) {
    send {mbutton down}
    while (GetKeyState("vked", "P") && GetKeyState("/", "P")) {
      Sleep 10
    }
    send {mbutton up}
  }
  return

;;  Use caps lock as 'meta' key to trigger things (caps remapped to f24).
$vked up::
  appLeaderUpTick = %A_TickCount%
  return

;;  Supress rshift+caps that produces char codes in chrome and erases
;;  cell content in spreadsheets while switching language via meta-s-f.
$+vked::
  if (appLeaderUpTick >= appLeaderDownTick) {
    appLeaderDownTick = %A_TickCount%
  }
  return
$+vked up::
  appLeaderUpTick = %A_TickCount%
  return

;;  'Enter' up
$rctrl up::
  appReturnUpTick = %A_TickCount%
  send {rctrl up}
  if (A_PriorKey = "RControl") {
    send {enter}
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
*$[::remap("down", "vkdb", "", "esc", "", "vkdb", "", "vkdb")
*$[ up::remap("up", "vkdb", "", "esc", "", "vkdb", "", "vkdb")

;;  'meta-period' for mouse button 4 (scroll)
*$.::remap("down", "vkbe", "", "xbutton1", "", "vkbe", "", "vkbe")
*$. up::remap("up", "vkbe", "", "xbutton1", "", "vkbe", "", "vkbe")

;;  'meta-shift-plus' for closing apps
*$=::remap("down", "vkbb", "", "vkbb", "none", "", "", "vkbb")
*$= up::remap("up", "vkbb", "", "vkbb", "winclose", "", "", "vkbb")

;;  'meta-p' for backspace
;;  'meta-shift-p' for deleting things.
*$p::remap("down", "vk50", "", "backspace", "none", "", "", "vk50")
*$p up::remap("up", "vk50", "", "backspace", "delete", "", "", "vk50")

;;  'meta-h' for left arrow (vim-like).
;;  'meta-shift-h' for shift-left-arrow (vim-like + selection modify).
*$h::remap("down", "vk48", "", "left", "+", "left", "", "vk48")
*$h up::remap("up", "vk48", "", "left", "+", "left", "", "vk48")

;;  'meta-j' for down arrow (vim-like).
;;  'meta-shift-j' for shift-down-arrow (vim-like + selection modify).
*$j::remap("down", "vk4a", "", "down", "+", "down", "", "vk4a")
*$j up::remap("up", "vk4a", "", "down", "+", "down", "", "vk4a")

;;  'meta-k' for up arrow (vim-like).
;;  'meta-shift-k' for shift-up-arrow (vim-like + selection modify).
*$k::remap("down", "vk4b", "", "up", "+", "up", "", "vk4b")
*$k up::remap("up", "vk4b", "", "up", "+", "up", "", "vk4b")

;;  'meta-l' for right arrow (vim-like).
;;  'meta-shift-l' for shift-right-arrow (vim-like + selection modify).
*$l::remap("down", "vk4c", "", "right", "+", "right", "", "vk4c")
*$l up::remap("up", "vk4c", "", "right", "+", "right", "", "vk4c")

;;  'meta-w' for home.
*$w::remap("down", "vk57", "", "home", "", "vk57", "", "vk57")
*$w up::remap("up", "vk57", "", "home", "", "vk57", "", "vk57")

;;  'meta-e' for page down.
*$e::remap("down", "vk45", "", "pgdn", "", "vk45", "", "vk45")
*$e up::remap("up", "vk45", "", "pgdn", "", "vk45", "", "vk45")

;;  'meta-r' for page up.
*$r::remap("down", "vk52", "", "pgup", "", "vk52", "", "vk52")
*$r up::remap("up", "vk52", "", "pgup", "", "vk52", "", "vk52")

;;  'meta-t' for end.
*$t::remap("down", "vk54", "", "end", "", "vk54", "", "vk54")
*$t up::remap("up", "vk54", "", "end", "", "vk54", "", "vk54")

;;  'meta-x' for F5.
*$x::remap("down", "vk58", "", "f5", "", "vk58", "", "vk58")
*$x up::remap("up", "vk58", "", "f5", "", "vk58", "", "vk58")

;;  'meta-c' for F6.
*$c::remap("down", "vk43", "", "f6", "", "vk43", "", "vk43")
*$c up::remap("up", "vk43", "", "f6", "", "vk43", "", "vk43")

;;  'meta-v' for F7.
*$v::remap("down", "vk56", "", "f7", "", "vk56", "", "vk56")
*$v up::remap("up", "vk56", "", "f7", "", "vk56", "", "vk56")

;;  'meta-b' for F8.
*$b::remap("down", "vk42", "", "f8", "", "vk42", "", "vk42")
*$b up::remap("up", "vk42", "", "f8", "", "vk42", "", "vk42")

;;  'meta-|' for launchpad.
;;  'meta-s-|' for notifications.
;;  'meta-c-|' for game HUD's (GOG, steam etc)
*$\::remap("down", "vkdc", "", "lwin", "#", "a", "+", "tab")
*$\ up::remap("up", "vkdc", "", "lwin", "#", "a", "+", "tab")

;;  ==========================================================================
;;  App launcher
;;  ==========================================================================

;;  'meta-2' fo 1st app
*$2::remap("down", "vk32", "#^", "1", "", "vk32", "", "vk32")
*$2 up::remap("up", "vk32", "#^", "1", "", "vk32", "", "vk32")

;;  'meta-3' fo 2nd app
*$3::remap("down", "vk33", "#^", "2", "", "vk33", "", "vk33")
*$3 up::remap("up", "vk33", "#^", "2", "", "vk33", "", "vk33")

;;  'meta-4' fo 3nd app
*$4::remap("down", "vk34", "#^", "3", "", "vk34", "", "vk34")
*$4 up::remap("up", "vk34", "#^", "3", "", "vk34", "", "vk34")

;;  'meta-5' fo 4th app
*$5::remap("down", "vk35", "#^", "4", "", "vk35", "", "vk35")
*$5 up::remap("up", "vk35", "#^", "4", "", "vk35", "", "vk35")

;;  'meta-6' fo 5th app
*$6::remap("down", "vk36", "#^", "5", "", "vk36", "", "vk36")
*$6 up::remap("up", "vk36", "#^", "5", "", "vk36", "", "vk36")

;;  'meta-7' for 6th app
*$7::remap("down", "vk37", "#^", "6", "", "vk37", "", "vk37")
*$7 up::remap("up", "vk37", "#^", "6", "", "vk37", "", "vk37")

;;  'meta-8' for 7th app
*$8::remap("down", "vk38", "#^", "7", "", "vk38", "", "vk38")
*$8 up::remap("up", "vk38", "#^", "7", "", "vk38", "", "vk38")

;;  'meta-9' for 8th app
*$9::remap("down", "vk39", "#^", "8", "", "vk39", "", "vk39")
*$9 up::remap("up", "vk39", "#^", "8", "", "vk39", "", "vk39")

;;  'meta-0' for 9th app
*$0::remap("down", "vk30", "#^", "9", "", "vk30", "", "vk30")
*$0 up::remap("up", "vk30", "#^", "9", "", "vk30", "", "vk30")

;;  'meta-minus' for 10th app
*$-::remap("down", "vkbd", "#^", "0", "", "vkbd", "", "vkbd")
*$- up::remap("up", "vkbd", "#^", "0", "", "vkbd", "", "vkbd")

;;  ==========================================================================
;;  Language switch
;;  ==========================================================================

;;  meta-g for F4
;;  meta-shift-g for emoji selector
*$g::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
      send #{vkbe}
    }
    else {
      send {blind}{vk73 down}
    }
    return
  }
  send {blind}{vk47 down}
  return

*$g up::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
    }
    else {
      send {blind}{vk73 up}
    }
    return
  }
  send {blind}{vk47 up}
  return

;;  meta-f for F3
;;  meta-shift-f switch to 1st language
*$f::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
      appLastLangHotkey := "4"
      send ^+4
    }
    else {
      send {blind}{vk72 down}
    }
    return
  }
  send {blind}{vk46 down}
  return

*$f up::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
    }
    else {
      send {blind}{vk72 up}
    }
    return
  }
  send {blind}{vk46 up}
  return

;;  meta-d for F2
;;  meta-d switch to 2nd language
*$d::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
      appLastLangHotkey := "5"
      send ^+5
    }
    else {
      send {blind}{vk71 down}
    }
    return
  }
  send {blind}{vk44 down}
  return

*$d up::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
    }
    else {
      send {blind}{vk71 up}
    }
    return
  }
  send {blind}{vk44 up}
  return

;;  meta-s for F1
;;  meta-s switch to 3nd language
*$s::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
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
      send {blind}{vk70 down}
    }
    return
  }
  send {blind}{vk53 down}
  return

*$s up::
  if (GetKeyState("vked", "P")) {
    if (GetKeyState("shift", "P")) {
    }
    else {
      send {blind}{vk70 up}
    }
    return
  }
  send {blind}{vk53 up}
  return

;; ===========================================================================
;; Multi-key combinations
;; ===========================================================================

;;  'meta-shift-y' => top left (third party tool mapped to f13)
*$y::remap("down", "vk59", "", "vk59", "", "f13", "", "vk59")
*$y up::remap("up", "vk59", "", "vk59", "", "f13", "", "vk59")

;;  'meta-shift-u' => bottom left (third party tool mapped to f14)
*$u::remap("down", "vk55", "", "vk55", "", "f14", "", "vk55")
*$u up::remap("up", "vk55", "", "vk55", "", "f14", "", "vk55")

;;  'meta-shift-i' => top right (third party tool mapped to f15)
*$i::remap("down", "vk49", "", "vk49", "", "f15", "", "vk49")
*$i up::remap("up", "vk49", "", "vk49", "", "f15", "", "vk49")

;;  'meta-shift-o' => botom right (third party tool mapped to f16)
*$o::remap("down", "vk4f", "", "vk4f", "", "f16", "", "vk4f")
*$o up::remap("up", "vk4f", "", "vk4f", "", "f16", "", "vk4f")

;;  'meta-shift-n' => left 1/2, 1/3, 2/3 (third party tool mapped to f17)
;;  Stub implementation.
*$n::remap("down", "vk4e", "", "vk4e", "#", "left", "", "vk4e")
*$n up::remap("up", "vk4e", "", "vk4e", "#", "left", "", "vk4e")

;;  'meta-shift-m' => right 1/2, 1/3, 2/3 (third party tool mapped to f18)
;;  Stub implementation.
*$m::remap("down", "vk4d", "", "vk4d", "#", "right", "", "vk4d")
*$m up::remap("up", "vk4d", "", "vk4d", "#", "right", "", "vk4d")

;;  'meta-shift-,' => top 1/2, 1/3, 2/3 (third party tool mapped to f19)
*$,::remap("down", "vkbc", "", "vkbc", "", "f19", "", "vkbc")
*$, up::remap("up", "vkbc", "", "vkbc", "", "f19", "", "vkbc")

;;  'meta-shift-.' => bottom 1/2, 1/3, 2/3 (third party tool mapped to f20)
*$.::remap("down", "vkbe", "", "vkbe", "", "f20", "", "vkbe")
*$. up::remap("up", "vkbe", "", "vkbe", "", "f20", "", "vkbe")

;;  'meta-shift-space' => maximize
*$space::remap("down", "vk20", "", "f21", "none", "", "", "vk20")
*$space up::remap("up", "vk20", "", "f21", "winmaximize", "", "", "vk20")

;; ===========================================================================
;; Left, right and middle mouse buttons
;; ===========================================================================

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

;;  'meta-slash' for middle mouse button.
*$/::
  if (GetKeyState("vked", "P")) {
    send {mbutton down}
    ;;  For games where holding mouse button moves something and caps can
    ;;  be released and pressed back while still holding key).
    while (GetKeyState("vked", "P") && GetKeyState("/", "P")) {
      Sleep 10
    }
    send {mbutton up}
  }
  else {
    send {blind}{vkbf}
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
