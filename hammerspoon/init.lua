-- Load dependencies from git-controlled dotfiles dir
package.path = package.path .. ";/Users/user/dotfiles/hammerspoon/?.lua"

require "helpers"


menuItem = hs.menubar.new()
lastCpuUsage = hs.host.cpuUsageTicks()
cpuLoadHistory = {}
maxCpuLoadHistory = 10
cpuLoadAverage = 0
icmpHistory = {}
-- Five pings per seconf for near-realtime network monitoring
icmpSendInterval = 0.2
-- Pings more than 2 seconds are as bad as having no internet
icmpTimeout = 2.0
maxIcmpHistory = (1 / icmpSendInterval) * icmpTimeout + 1
pingAverage = 0
batteryCharge = 0


function clickDockItem(number)
  local dock = hs.application("Dock")
  local axapp = hs.axuielement.applicationElement(dock)
  local currentNumber = 1
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


local hotkeys = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0"}
for i, hotkey in ipairs(hotkeys) do
  hs.hotkey.bind({"⌘", "⌃", "⌥", "⇧"}, hotkey, function()
    -- skip finder in dock
    clickDockItem(i + 1)
  end)
end


pingSrv = hs.network.ping.echoRequest("1.1.1.1")
pingSrv:setCallback(function(self, msg, ...)
  if msg == "didStart" then
    local address = ...
  elseif msg == "didFail" then
    local error = ...
    print("ping server failed with " .. error)
  elseif msg == "sendPacket" then
    local icmp, seq = ...
    timeSec = hs.timer.absoluteTime() / 1000000000;
    table.insert(icmpHistory, {seq=seq, timeSend=timeSec})
    if #icmpHistory > maxIcmpHistory then
      table.remove(icmpHistory, 1)
    end
  elseif msg == "sendPacketFailed" then
    local icmp, seq, error = ...
    print("ping send error " .. error)
    table.insert(pingHistory, -1)
  elseif msg == "receivedPacket" then
    local icmp, seq = ...
    for _, item in ipairs(icmpHistory) do
      if item.seq == seq then
        timeSec = hs.timer.absoluteTime() / 1000000000;
        item.timeRecv = timeSec
        break
      end
    end
  elseif msg == "receivedUnexpectedPacket" then
    local icmp = ...
    print("received unexpected icmp ")
  end
end)
pingSrv:start()


counter = 0
function onTimer()

  counter = counter + 1
  pingSrv:sendPayload()

  local curCpuUsage = hs.host.cpuUsageTicks()
  local activeDiff = curCpuUsage.overall.active - lastCpuUsage.overall.active
  local idleDiff = curCpuUsage.overall.idle - lastCpuUsage.overall.idle
  lastCpuUsage = curCpuUsage
  local cpuLoad = activeDiff * 100 / (activeDiff + idleDiff)
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

  -- Updating ping too often make "numbers jump"
  if counter % 5 == 0 then
    pingAverage = 0
    local pingItems = 0
    for _, item in ipairs(icmpHistory) do
      if item.timeRecv then
        local ping = item.timeRecv - item.timeSend
        pingAverage = pingAverage + ping
        pingItems = pingItems + 1
      end
    end
    if pingItems > 0 then
      pingAverage = pingAverage / pingItems
    end
  end

  batteryCharge = hs.battery.percentage()

  local titleStr = "cpu: " .. string.format("%05.2f", cpuLoadAverage)
  if pingAverage ~= 0 then
    pingStr = string.format("%04.0f", pingAverage * 1000)
    titleStr = titleStr .. " net: " .. pingStr
  else
    titleStr = titleStr .. " net: n/a"
  end
  titleStr = titleStr .. " bat: " .. string.format("%.0f", batteryCharge)
  titleObj = hs.styledtext.new(titleStr, {font={name="Courier"}})
  menuItem:setTitle(titleObj)
end


timer = hs.timer.doEvery(icmpSendInterval, function()
  isOk, err = pcall(onTimer)
  if not isOk then
    print(err)
  end
end)
