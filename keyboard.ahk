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

codepage = 65001 ; utf-8
appLastLangHotkey := ""
;;  "Leader key", only works in combinations, doesn't work on it's own
SetCapsLockState, alwaysoff

if !A_IsAdmin {
  Run *RunAs "%A_ScriptFullPath%"
  ExitApp
}

;;  No warning if key is hold for 2 seconds (HotkeyInterval)
#MaxHotkeysPerInterval 500
;;  Better keyboard handling at the cost of +0.5mb of memory.
#InstallKeybdHook

#inputlevel 1
tab::lctrl
return::rctrl
#inputlevel 0

$rctrl up::
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

;; ===========================================================================
;; Language switch
;; ===========================================================================

$4::
  if (GetKeyState("capslock", "P")) {
    appLastLangHotkey := "4"
    send ^+4
  }
  else {
    send 4
  }
  return

$5::
  if (GetKeyState("capslock", "P")) {
    appLastLangHotkey := "5"
    send ^+5
  }
  else {
    send 5
  }
  return

$6::
  if (GetKeyState("capslock", "P")) {
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
    send 6
  }
  return

;; ===========================================================================
;; Keys and combinations remap
;; ===========================================================================

$[::
  if (GetKeyState("capslock", "P")) {
    send {esc}
  }
  else {
    send {vkdb}
  }
  return

*$/::
  if (GetKeyState("capslock", "P")) {
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
  if (GetKeyState("capslock", "P")) {
    send !{tab}
  }
  else {
    send {vkdd}
  }
  return

*$\::
  if (GetKeyState("capslock", "P")) {
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

$7::
  if (GetKeyState("capslock", "P")) {
    WinActivate, ahk_exe cmd.exe
  }
  else {
    send 7
  }
  return

$8::
  if (GetKeyState("capslock", "P")) {
    WinActivate, ahk_exe code.exe
  }
  else {
    send 8
  }
  return

$9::
  if (GetKeyState("capslock", "P")) {
    WinActivate, ahk_exe chrome.exe
  }
  else {
    send 9
  }
  return

$0::
  if (GetKeyState("capslock", "P")) {
    ; WinActivate, ahk_exe doublecmd.exe
    ; WinActivate, ahk_exe MailClient.exe
    WinActivate, ahk_exe thunderbird.exe
  }
  else {
    send 0
  }
  return

$-::
  if (GetKeyState("capslock", "P")) {
    WinActivate, ahk_exe telegram.exe
  }
  else {
    send -
  }
  return

*$=::
  if (GetKeyState("capslock", "P")) {
    if (GetKeyState("shift", "P")) {
      send #e
    }
    else {
      ; Restore from tray if "allow only one instance" option is set"
      Run KeePass.exe,, hide
      WinActivate, ahk_exe KeePass.exe
    }
  }
  else {
    send {blind}{vkbb}
  }
  return

$backspace::
  if (GetKeyState("capslock", "P")) {
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
  if (GetKeyState("capslock", "P")) {
    winmaximize A
  }
  else {
    send 7
  }
  return

*$h::
  if (GetKeyState("capslock", "P")) {
    if (GetKeyState("shift", "P")) {
      send {wheelleft}
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
  if (GetKeyState("capslock", "P")) {
    if (GetKeyState("shift", "P")) {
      send {wheeldown}
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
  if (GetKeyState("capslock", "P")) {
    if (GetKeyState("shift", "P")) {
      send {wheelup}
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
  if (GetKeyState("capslock", "P")) {
    if (GetKeyState("shift", "P")) {
      send {wheelright}
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
  if (GetKeyState("capslock", "P")) {
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

$capslock::
  ;;  For games like WoW right buttons hold are used for movement, so
  ;;  sometimescaps lock is released while holding tick or semicolon.
  ;;  Holding caps lock again should return button hold.
  if (GetKeyState(";", "P")) {
    send {lbutton down}
    while (GetKeyState("capslock", "P") && GetKeyState(";", "P")) {
      Sleep 10
    }
    send {lbutton up}
  }
  else if (GetKeyState("'", "P")) {
    send {rbutton down}
    while (GetKeyState("capslock", "P") && GetKeyState("'", "P")) {
      Sleep 10
    }
    send {rbutton up}
  }
  return

;;  caps + ; is left mouse button
*$`;::
  if (GetKeyState("capslock", "P")) {
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

    ;;  like WoW where holding left button moves camera and caps can
    ;;  be released while still holding semicolon).
    while (GetKeyState("capslock", "P") && GetKeyState(";", "P")) {
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
  if (GetKeyState("capslock", "P")) {
    send {rbutton down}
    ;;  hold; if 'caps' or 'tick' is up - stop hold (optimized for games
    ;;  like WoW where holding right button moves camera and caps can
    ;;  be released while still holding tick).
    while (GetKeyState("capslock", "P") && GetKeyState("'", "P")) {
      Sleep 10
    }
    send {rbutton up}
  }
  else {
    send {blind}{vkde}
  }
  return

::sigen::
  ClipBoard := "Best regards,`nGrigory Petrov,`nHead of Developer Relations`nVoximplant`n+16504575614`nhttp://facebook.com/grigoryvp"
  send ^v
  return

::sigru::
  ClipBoard := "С уважением,`nГригорий Петров,`nДиректор по Техническому Маркетингу`nVoximplant`n+7-926-225-16-08`nhttp://facebook.com/grigoryvp"
  send ^v
  return
