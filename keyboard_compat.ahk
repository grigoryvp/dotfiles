#SingleInstance force

`;::SendInput {lbutton}
'::SendInput {rbutton}
[::SendInput {esc}
\::SendInput {lwin}

!`::
  path := A_MyDocuments "\PowerShell\keyboard.ahk"
  run autohotkey.exe %path%,, Hide
  Suspend
  return
