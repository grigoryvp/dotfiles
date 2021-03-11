-- Load dependencies from git-controlled dotfiles dir
package.path = package.path .. ";/Users/user/dotfiles/hammerspoon/?.lua"

require "helpers"
require "menuitem"


menuItem = menuitem:new()
lastCpuUsage = hs.host.cpuUsageTicks()
cpuLoadHistory = {}
maxCpuLoadHistory = 10
cpuLoadAverage = 0
icmpHistory = {}
-- Five pings per seconf for near-realtime network monitoring
icmpSendInterval = 0.2
-- Pings more than 2 seconds are as bad as having no internet
icmpTimeout = 2.0
maxIcmpHistory = 20
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
  elseif msg == "sendPacket" or msg == "sendPacketFailed" then
    local icmp, seq = ...
    timeSec = hs.timer.absoluteTime() / 1000000000;
    table.insert(icmpHistory, {seq = seq, timeSend = timeSec})
    if #icmpHistory > maxIcmpHistory then
      table.remove(icmpHistory, 1)
    end
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

  -- Updating too often yields high CPU usage
  if counter % 5 ~= 0 then
    return
  end

  local curCpuUsage = hs.host.cpuUsageTicks()
  local activeDiff = curCpuUsage.overall.active - lastCpuUsage.overall.active
  local idleDiff = curCpuUsage.overall.idle - lastCpuUsage.overall.idle
  lastCpuUsage = curCpuUsage
  local cpuLoad = activeDiff * 100 / (activeDiff + idleDiff)
  table.insert(cpuLoadHistory, cpuLoad)
  if #cpuLoadHistory > maxCpuLoadHistory then
    table.remove(cpuLoadHistory, 1)
  end

  cpuLoadAverage = 0
  for _, v in ipairs(cpuLoadHistory) do
    cpuLoadAverage = cpuLoadAverage + v
  end
  cpuLoadAverage = cpuLoadAverage / #cpuLoadHistory

  local graph = {}
  for i = #icmpHistory, 1, -1 do
    local item = icmpHistory[i]
    if item.timeRecv then
      local ping = item.timeRecv - item.timeSend
      if ping < 0.05 then
        local green = {green = 1}
        table.insert(graph, {val = (ping / 0.05) * 0.25, color = green})
      elseif ping < 0.2 then
        local yellow = {red = 1, green = 1}
        table.insert(graph, {val = (ping / 0.20) * 0.50, color = yellow})
      elseif ping < 0.5 then
        local orange = {red = 1, green = 0.5}
        table.insert(graph, {val = (ping / 0.50) * 0.75, color = orange})
      elseif ping < 2.0 then
        local red = {red = 1}
        table.insert(graph, {val = (ping / 2.0) * 1.00, color = red})
      end
    else
      -- If no reply is received draw gray columns of different height
      -- for visual "in progress" feedback
      local grey = {red = 0.5, green = 0.5, blue = 0.5}
      if (counter + i) % 2 == 0 then
        table.insert(graph, {val = 0.2, color = grey})
      else
        table.insert(graph, {val = 0.4, color = grey})
      end
    end
  end

  batteryCharge = hs.battery.percentage()

  local titleStr = "cpu: " .. string.format("%05.2f", cpuLoadAverage)
  titleStr = titleStr .. " bat: " .. string.format("%.0f", batteryCharge)

  menuItem:clear()
  menuItem:addGraph(graph)
  menuItem:addSpacer(4)
  menuItem:addText(titleStr)
  menuItem:update()
end


timer = hs.timer.doEvery(icmpSendInterval, function()
  isOk, err = pcall(onTimer)
  if not isOk then
    print(err)
  end
end)
