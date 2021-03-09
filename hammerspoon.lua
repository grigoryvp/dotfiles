dir = function (o) for k, v in pairs(o) do print(k, "=>", v) end end
idir = function (o) for i, v in ipairs(o) do print(i, "~>", v) end end
cls = hs.console.clearConsole


menuItem = hs.menubar.new()
lastCpuUsage = hs.host.cpuUsageTicks()
cpuLoadHistory = {}
maxCpuLoadHistory = 10
cpuLoadAverage = 0
batteryCharge = 0


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


pingSrv = hs.network.ping.echoRequest("1.1.1.1")
pingSrv:setCallback(function() end)
pingSrv:start()


counter = 0
function onTimer()

  counter = counter + 1
  pingSrv:sendPayload()

  curCpuUsage = hs.host.cpuUsageTicks()
  activeDiff = curCpuUsage.overall.active - lastCpuUsage.overall.active
  idleDiff = curCpuUsage.overall.idle - lastCpuUsage.overall.idle
  lastCpuUsage = curCpuUsage
  cpuLoad = activeDiff * 100 / (activeDiff + idleDiff)
  table.insert(cpuLoadHistory, cpuLoad)
  if #cpuLoadHistory > maxCpuLoadHistory then
    table.remove(cpuLoadHistory, 1)
  end

  -- Updating cpu load too often make "numbers jump"
  if counter % 5 == 0 then
    cpuLoadAverage = 0
    for _, v in ipairs(cpuLoadHistory) do
      cpuLoadAverage = cpuLoadAverage + v
    end
    cpuLoadAverage = cpuLoadAverage / #cpuLoadHistory
  end

  batteryCharge = hs.battery.percentage()

  titleStr = "cpu: " .. string.format("%05.2f", cpuLoadAverage) ..
    " bat: " .. string.format("%.0f", batteryCharge)
  titleObj = hs.styledtext.new(titleStr, {font={name="Courier"}})
  menuItem:setTitle(titleObj)
end


timer = hs.timer.doEvery(0.2, function()
  isOk, err = pcall(onTimer)
  if not isOk then
    print(err)
  end
end)
