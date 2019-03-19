global foundWindow
set foundWindow to null
global foundTab
set foundTab to null

tell application "Safari"
  set windowCount to number of windows
  repeat with curWindowIdx from 1 to windowCount
    set tabCount to number of tabs in window curWindowIdx
    repeat with curTabIdx from 1 to tabCount
      set tabName to name of tab curTabIdx of window curWindowIdx
      if tabName contains "Trello" then
        set foundWindow to curWindowIdx
        set foundTab to curTabIdx
      end if
    end repeat
  end repeat
end tell

if foundWindow is not null
  tell application "System Events" 
    tell process "Safari"
      perform action "AXRaise" of window foundWindow
    end tell
  end tell
  tell window foundWindow of application "Safari" to set current tab to tab foundTab
else
  tell application "Safari"
    set dst to "https://trello.com/b/PRTGVQEY/??"
    make new document with properties {URL:dst}
  end tell
end if
