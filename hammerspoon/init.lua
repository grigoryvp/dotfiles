-- Load dependencies from git-controlled dotfiles dir
package.path = package.path .. ";/Users/user/dotfiles/hammerspoon/?.lua"

require "helpers"
require "menuitem"


menuItem = menuitem:new()
lastCpuUsage = hs.host.cpuUsageTicks()
cpuLoadHistory = {}
maxCpuLoadHistory = 20
icmpHistory = {}
-- Five pings per seconf for near-realtime network monitoring
icmpSendInterval = 0.2
maxIcmpHistory = 20


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

  local curCpuUsage = hs.host.cpuUsageTicks()
  local activeDiff = curCpuUsage.overall.active - lastCpuUsage.overall.active
  local idleDiff = curCpuUsage.overall.idle - lastCpuUsage.overall.idle
  lastCpuUsage = curCpuUsage
  local cpuLoad = activeDiff / (activeDiff + idleDiff)
  table.insert(cpuLoadHistory, cpuLoad)
  if #cpuLoadHistory > maxCpuLoadHistory then
    table.remove(cpuLoadHistory, 1)
  end

  -- Updating too often yields high CPU usage
  if counter % 5 ~= 0 then
    return
  end

  local netGraph = {}
  for i = #icmpHistory, 1, -1 do
    local item = icmpHistory[i]
    local graphItem = nil
    if item.timeRecv then
      local ping = item.timeRecv - item.timeSend
      if ping < 0.05 then
        local green = {green = 1}
        local val = (ping / 0.05) * 0.25
        graphItem = {val = val, color = green}
      elseif ping < 0.2 then
        local yellow = {red = 1, green = 1}
        local val = (ping / 0.20) * 0.25 + 0.25
        graphItem = {val = val, color = yellow}
      elseif ping < 0.5 then
        local orange = {red = 1, green = 0.5}
        local val = (ping / 0.50) * 0.25 + 0.50
        graphItem = {val = val, color = orange}
      elseif ping < 2.0 then
        local red = {red = 1}
        local val = (ping / 2.00) * 0.25 + 0.75
        graphItem = {val = val, color = red}
      end
      -- Pings more than 2 seconds are as bad as having no internet
    end
    if not graphItem then
      -- If no reply is received or reply took more than 2 seconds draw gray
      -- columns of different height for visual "in progress" feedback
      local grey = {red = 0.5, green = 0.5, blue = 0.5}
      if (counter + i) % 2 == 0 then
        table.insert(netGraph, {val = 0.2, color = grey})
      else
        table.insert(netGraph, {val = 0.4, color = grey})
      end
    end
    table.insert(netGraph, graphItem)
  end

  local cpuGraph = {}
  for i = #cpuLoadHistory, 1, -1 do
    local load = cpuLoadHistory[i]
    if load < 0.10 then
      local green = {green = 1}
      local val = (load / 0.10) * 0.25
      table.insert(cpuGraph, {val = val, color = green})
    elseif load < 0.20 then
      local yellow = {red = 1, green = 1}
      local val = (load / 0.20) * 0.25 + 0.25
      table.insert(cpuGraph, {val = val, color = yellow})
    elseif load < 0.50 then
      local orange = {red = 1, green = 0.5}
      local val = (load / 0.50) * 0.25 + 0.50
      table.insert(cpuGraph, {val = val, color = orange})
    else
      local red = {red = 1}
      local val = (load / 1.00) * 0.25 + 0.75
      table.insert(cpuGraph, {val = val, color = red})
    end
  end

  menuItem:clear()
  menuItem:addText("net")
  menuItem:addSpacer(4)
  menuItem:addGraph(netGraph)
  menuItem:addSpacer(4)
  menuItem:addText("cpu")
  menuItem:addSpacer(4)
  menuItem:addGraph(cpuGraph)
  menuItem:addSpacer(4)
  menuItem:addText("bat")
  menuItem:addSpacer(4)
  menuItem:addText(string.format("%.0f", hs.battery.percentage()))
  menuItem:update()
end


timer = hs.timer.doEvery(icmpSendInterval, function()
  local isOk, err = pcall(onTimer)
  if not isOk then
    print(err)
  end
end)


hs.hotkey.bind("⌃", "w", function()
  local wnd = hs.window.frontmostWindow()
  if not wnd then return end
  local app = wnd:application()

  -- Speed optimization to close tabs fast if they are exposed like in
  -- Safari or iTerm2 (searching for app menu items takes some time)
  if wnd:tabCount() > 0 then
    local delay = 50000
    hs.eventtap.keyStroke({"⌘"}, "w", delay, app)
    return
  end

  local menu = app:findMenuItem("Close Editor")
  if menu and menu.enabled then
    app:selectMenuItem("Close Editor")
    return
  end

  local menu = app:findMenuItem("Close Tab")
  if menu and menu.enabled then
    app:selectMenuItem("Close Tab")
    return
  end

  wnd:close()
end)
