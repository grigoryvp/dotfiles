#SingleInstance force

`;::SendInput {lbutton}
'::SendInput {rbutton}
[::SendInput {esc}
\::SendInput {lwin}

!pgup::
  path := A_MyDocuments "\..\.box-cfg\keyboard.ahk"
  run autohotkey.exe %path%,, Hide
  Suspend
  return
