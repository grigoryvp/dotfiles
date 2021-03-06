dir = function (o) for k, v in pairs(o) do print(k, "=>", v) end end
idir = function (o) for i, v in ipairs(o) do print(i, "~>", v) end end
cls = hs.console.clearConsole


function clickDockItem(number)
  dock = hs.application("Dock")
  axapp = hs.axuielement.applicationElement(dock)
  currentNumber = 1
  for _, item in ipairs(axapp[1]) do
    if item.AXRoleDescription == "application dock item" then
      if currentNumber == number then
        item:doAXPress()
        return
      end
      currentNumber = currentNumber + 1
    end
  end
end


hotkeys = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0"}
for i, hotkey in ipairs(hotkeys) do
  hs.hotkey.bind({"⌘", "⌃", "⌥", "⇧"}, hotkey, function()
    -- skip finder in dock
    clickDockItem(i + 1)
  end)
end
