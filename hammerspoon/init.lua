-- See ./.vscode/settings.json for linter configuration

-- Load dependencies from git-controlled dotfiles dir
package.path = package.path .. ";/Users/user/dotfiles/hammerspoon/?.lua"

require "helpers"
require "menuitem"


menuItem = menuitem:new()
lastCpuUsage = hs.host.cpuUsageTicks()
cpuLoadHistory = {}
maxCpuLoadHistory = 20
routerIcmpHistory = {}
inetIcmpHistory = {}
-- Interval, in seconds, to send pings, check cpu load etc.
heartbeatInterval = 0.2
heartbeatsPerSec = 5
-- Increased on first loop, start with 0 to kick off all % checks
heartbeatCounter = -1
heartbeatTime = hs.timer.absoluteTime() / 1000000000;
maxIcmpHistory = 20
lastBattery = nil
secondsSinceBatteryDec = 0
-- Keys are the charge amount the decrease is from, values are number of
-- seconds it took for battery to discharge from that value. Ex, if key 90
-- contains value of 1000 that means that it took 1000 seconds for a battery
-- to discharge from 90 to 89 percents.
batteryDecHistory = {}
dock = hs.application("Dock")
dockItems = hs.axuielement.applicationElement(dock)[1]
telegramDockItem = nil
mailDockItem = nil
slackDockItem = nil
discordDockItem = nil
bitlyToken = nil
-- Can't get if not connected to the network.
ipv4IfaceName = nil
lastIp = nil
routerIp = nil
routerIpTask = nil


function ipStrToList(ip)
  local items = {}
  for v in (ip):gmatch("[^.]+") do
    table.insert(items, tonumber(v))
  end
  return items
end


function clickDockItem(number)
  local currentNumber = 1
  local isSeparatorFound = false
  for _, item in ipairs(dockItems) do
    if item.AXRoleDescription == "application dock item" then
      -- Hotkeys affect items to the right of user-placed separator
      -- (system preferences for now). To the left are items that are
      -- iterested only for notifications.
      if isSeparatorFound then
        if currentNumber == number then
          item:doAXPress()
          return
        end
        currentNumber = currentNumber + 1
      else
        if item.AXTitle == "System Preferences" then
          isSeparatorFound = true
        end
      end
    end
  end
end


local hotkeys = {"2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="}
for i, hotkey in ipairs(hotkeys) do
  hs.hotkey.bind({"⌘", "⌃", "⌥"}, hotkey, function()
    clickDockItem(i)
  end)
end


-- meta-shift-2 opens Trello
hs.hotkey.bind({"⌘", "⌃", "⌥", "⇧"}, "2", function()
  local reasonableNumOfSeconds = 5
  local waitApp = reasonableNumOfSeconds
  local waitWindow = true
  local app = hs.application.open("com.apple.Safari", waitApp, waitWindow)
  if not app then return end
  local menuItem = app:findMenuItem("Save As...")
  -- Current tab has some page open?
  if menuItem.enabled then
    app:selectMenuItem("New Tab")
  end
  hs.eventtap.keyStrokes("https://trello.com\n", app)
end)


function icmpPingToHistory(history, msg, ...)
  if msg == "didStart" then
    local address = ...
  elseif msg == "didFail" then
    local error = ...
    print("ping server failed with " .. error)
  elseif msg == "sendPacket" or msg == "sendPacketFailed" then
    local icmp, seq = ...
    timeSec = hs.timer.absoluteTime() / 1000000000;
    table.insert(history, {seq = seq, timeSend = timeSec})
    if #history > maxIcmpHistory then
      table.remove(history, 1)
    end
  elseif msg == "receivedPacket" then
    local icmp, seq = ...
    for _, item in ipairs(history) do
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
end


inetPingSrv = hs.network.ping.echoRequest("1.1.1.1")
inetPingSrv:setCallback(function(self, msg, ...)
  icmpPingToHistory(inetIcmpHistory, msg, ...)
end)
inetPingSrv:start()


routerPingSrv = hs.network.ping.echoRequest("192.168.0.1")
function restartRouterPing(toIp)
  routerIp = toIp
  routerPingSrv:stop()
  routerPingSrv:setCallback(nil)
  routerPingSrv = hs.network.ping.echoRequest(toIp)
  routerPingSrv:setCallback(function(self, msg, ...)
    icmpPingToHistory(routerIcmpHistory, msg, ...)
  end)
  routerPingSrv:start()
end


function netGraphFromIcmpHistory(history)
  local graph = {}
  for i = #history, 1, -1 do
    local item = history[i]
    local graphItem = nil
    if item.timeRecv then
      local ping = item.timeRecv - item.timeSend
      if ping < 0.05 then
        local green = {green = 1}
        local val = (ping / 0.05) * 0.25
        graphItem = {val = val, color = green}
      elseif ping < 0.2 then
        local yellow = {red = 1, green = 1}
        local val = ((ping - 0.05) / (0.20 - 0.05)) * 0.25 + 0.25
        graphItem = {val = val, color = yellow}
      elseif ping < 0.5 then
        local orange = {red = 1, green = 0.5}
        local val = ((ping - 0.20) / (0.50 - 0.20)) * 0.25 + 0.50
        graphItem = {val = val, color = orange}
      elseif ping < 2.0 then
        local red = {red = 1}
        local val = ((ping - 0.50) / (2.00 - 0.50)) * 0.25 + 0.75
        graphItem = {val = val, color = red}
      end
      -- Pings more than 2 seconds are as bad as having no internet
    end
    if not graphItem then
      -- If no reply is received or reply took more than 2 seconds draw gray
      -- columns of different height for visual "in progress" feedback
      local grey = {red = 0.5, green = 0.5, blue = 0.5}
      if (heartbeatCounter + i) % 2 == 0 then
        table.insert(graph, {val = 0.2, color = grey})
      else
        table.insert(graph, {val = 0.4, color = grey})
      end
    end
    table.insert(graph, graphItem)
  end
  return graph
end


function cpuGraphFromLoadHistory(history)
  local graph = {}
  for i = #history, 1, -1 do
    local load = history[i]
    if load < 0.10 then
      local green = {green = 1}
      local val = (load / 0.10) * 0.25
      table.insert(graph, {val = val, color = green})
    elseif load < 0.20 then
      local yellow = {red = 1, green = 1}
      local val = ((load - 0.10) / (0.20 - 0.10)) * 0.25 + 0.25
      table.insert(graph, {val = val, color = yellow})
    elseif load < 0.50 then
      local orange = {red = 1, green = 0.5}
      local val = ((load - 0.20) / (0.50 - 0.20)) * 0.25 + 0.50
      table.insert(graph, {val = val, color = orange})
    else
      local red = {red = 1}
      local val = ((load - 0.50) / (1.00 - 0.50)) * 0.25 + 0.75
      table.insert(graph, {val = val, color = red})
    end
  end
  return graph
end


function onHeartbeat()

  heartbeatCounter = heartbeatCounter + 1
  -- 0.5% CPU
  inetPingSrv:sendPayload()
  if routerPingSrv:isRunning() then
    routerPingSrv:sendPayload()
  end

  -- 0.1% CPU
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
  if heartbeatCounter % heartbeatsPerSec ~= 0 then
    return
  end

  local curTime = hs.timer.absoluteTime() / 1000000000;
  local tooEarly = heartbeatTime + (heartbeatsPerSec - 1) * heartbeatInterval
  local tooLate = heartbeatTime + (heartbeatsPerSec + 1) * heartbeatInterval
  local isOneSecondPassed = false
  -- Around one second passed? (no sleep)
  if curTime >= tooEarly and curTime <= tooLate then
    isOneSecondPassed = true
  end
  heartbeatTime = curTime

  local routerGraph = netGraphFromIcmpHistory(routerIcmpHistory)
  local inetGraph = netGraphFromIcmpHistory(inetIcmpHistory)
  local cpuGraph = cpuGraphFromLoadHistory(cpuLoadHistory)

  if not telegramDockItem
     or not mailDockItem
     or not slackDockItem
     or not discordDockItem then
    -- Do not check too often, CPU expensive
    if heartbeatCounter == 0 or heartbeatCounter % 100 == 0 then
      for _, item in ipairs(dockItems) do
        if item.AXTitle == "Telegram" then
          telegramDockItem = item
        end
        if item.AXTitle == "Mail" then
          mailDockItem = item
        end
        if item.AXTitle == "Slack" then
          slackDockItem = item
        end
        if item.AXTitle == "Discord" then
          discordDockItem = item
        end
      end
    end
  end

  if not ipv4IfaceName then
    local ipv4, _ = hs.network.primaryInterfaces()
    if ipv4 then
      ipv4IfaceName = ipv4
    end
  end

  if ipv4IfaceName then
    local details = hs.network.interfaceDetails(ipv4IfaceName)
    if details then
      local ipv4IfaceDetails = details.IPv4
      if ipv4IfaceDetails then
        local curIp = ipv4IfaceDetails.Addresses[1]
        if lastIp ~= curIp then
          lastIp = curIp

          function onRouteToolExit(exitCode, stdOut, _)
            if exitCode ~= 0 or not stdOut then
              return restartRouterPing("192.168.0.1")
            end
            local pattern = "gateway: (%d+%.%d+%.%d+%.%d+)"
            local routerIp = stdOut:match(pattern)
            if not routerIp then
              return restartRouterPing("192.168.0.1")
            end
            return restartRouterPing(routerIp)
          end

          local args = {"get", "default"}
          routerIpTask = hs.task.new("/sbin/route", onRouteToolExit, args)
          routerIpTask:start()
        end
      end
    end
  end

  local notifications = {}
  if telegramDockItem and telegramDockItem.AXStatusLabel then
    table.insert(notifications, "T")
  end
  if mailDockItem and mailDockItem.AXStatusLabel then
    table.insert(notifications, "E")
  end
  if slackDockItem and slackDockItem.AXStatusLabel then
    table.insert(notifications, "S")
  end
  if discordDockItem and discordDockItem.AXStatusLabel then
    -- "•" indicates channel messages, counter indicates privats and mentions
    if discordDockItem.AXStatusLabel ~= "•" then
      table.insert(notifications, "D")
    end
  end

  menuItem:clear()

  if #notifications > 0 then
    -- Flash notification icons
    if heartbeatCounter % 10 == 0 then
      menuItem:addText(table.concat(notifications, " "))
    else
      menuItem:addText((" "):rep(#notifications * 2 - 1))
    end
    menuItem:addSpacer(10)
  end

  local battery = hs.battery.percentage()
  if not lastBattery then lastBattery = battery end

  -- 100 => 99 discharge takes too much time, assume "fully charged".
  if lastBattery == 100 then
    batteryDecHistory = {}
  -- "Battery care" stops charing on 80 percent, ignore 80 => 79 "discharge".
  elseif lastBattery == 80 then
  else
    if battery > lastBattery then
      -- Charge detected, clear history
      batteryDecHistory = {}
      secondsSinceBatteryDec = 0
    elseif battery == lastBattery then
      if isOneSecondPassed then
        secondsSinceBatteryDec = secondsSinceBatteryDec + 1
      end
    else
      -- Not a discharge jump: overnight stay etc?
      if battery == lastBattery - 1 then
        batteryDecHistory[lastBattery] = secondsSinceBatteryDec
      end
      secondsSinceBatteryDec = 0
    end
  end
  lastBattery = battery

  local recordCount = 0
  local totalTime = 0
  for _, seconds in pairs(batteryDecHistory) do
    recordCount = recordCount + 1
    totalTime = totalTime + seconds
  end
  local hrLeft = 0
  local minLeft = 0
  if recordCount > 0 then
    local secPerPercent = totalTime / recordCount
    local secRemaining = battery * secPerPercent
    hrLeft = math.floor(secRemaining / 3600)
    minLeft = math.floor((secRemaining - hrLeft * 3600) / 60)
  end

  local timeLeft = " ("
  if recordCount > 0 then
    if hrLeft > 0 then
      timeLeft = timeLeft .. hrLeft .. "h"
    end
    if minLeft > 0 then
      if hrLeft > 0 then timeLeft = timeLeft .. " " end
      timeLeft = timeLeft .. minLeft .. "m"
    end
    timeLeft = timeLeft .. ")"
  else
    timeLeft = ""
  end

  menuItem:addText("wifi")
  menuItem:addSpacer(4)
  menuItem:addGraph(routerGraph)
  menuItem:addSpacer(4)
  menuItem:addText("inet")
  menuItem:addSpacer(4)
  menuItem:addGraph(inetGraph)
  menuItem:addSpacer(4)
  menuItem:addText("cpu")
  menuItem:addSpacer(4)
  menuItem:addGraph(cpuGraph)
  menuItem:addSpacer(4)
  menuItem:addText("bat")
  menuItem:addSpacer(4)
  menuItem:addText(("%.0f"):format(battery) .. timeLeft)
  menuItem:update()
end


timer = hs.timer.doEvery(heartbeatInterval, function()
  onHeartbeat()
end)


hs.hotkey.bind("⌃", "w", function()
  local delay = 50000
  local wnd = hs.window.frontmostWindow()
  if not wnd then return end
  local app = wnd:application()

  if app:bundleID() == "com.apple.Safari" then
    local menuItem = app:findMenuItem("Close Tab")
    -- Not the last tab?
    if menuItem.enabled then
      -- Close active tab
      app:selectMenuItem("Close Tab")
    else
      local menuItem = app:findMenuItem("Save As...")
      -- Current tab has some page open?
      if menuItem.enabled then
        -- Safari can't close last tab
        app:selectMenuItem("New Tab")
        app:selectMenuItem("Show Previous Tab")
        app:selectMenuItem("Close Tab")
      end
    end
    return
  end

  -- Sometimes "Close Editor" menu item is disabled while there are available
  -- tabs, incorrectly closing VSCode instead of closing tab. Also,
  -- triggering "Close Editor" stops working if VSCode is moved between
  -- desktops.
  if app:bundleID() == "com.microsoft.VSCode" then
    -- ctrl-w to close editor
    hs.eventtap.keyStroke({"⌃"}, "w", delay, app)
    return
  end

  -- Speed optimization to close tabs fast if they are exposed like in
  -- Safari or iTerm2 (searching for app menu items takes some time)
  if wnd:tabCount() > 0 then
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


hs.hotkey.bind("⌃⇧", "v", function()
  local wnd = hs.window.frontmostWindow()
  if not wnd then return end
  local app = wnd:application()

  hs.pasteboard.setContents(hs.pasteboard.readString())
  app:selectMenuItem("Paste")
end)


hs.hotkey.bind("⌘⇧", "space", function()
  local wnd = hs.window.frontmostWindow()
  if not wnd then return end
  local frame = wnd:frame()
  ---@type table
  local screenFrame = wnd:screen():frame()
  local duration = 0
  wnd:setFrame(screenFrame, duration)
end)


hs.hotkey.bind("⌘⇧", "n", function()
  local wnd = hs.window.frontmostWindow()
  if not wnd then return end
  local frame = wnd:frame()
  ---@type table
  local screenFrame = wnd:screen():frame()

  frame.x = screenFrame.x
  frame.y = screenFrame.y
  frame.w = screenFrame.w / 2
  frame.h = screenFrame.h
  local duration = 0
  wnd:setFrame(frame, duration)
end)


hs.hotkey.bind("⌘⇧", "m", function()
  local wnd = hs.window.frontmostWindow()
  if not wnd then return end
  local frame = wnd:frame()
  ---@type table
  local screenFrame = wnd:screen():frame()

  frame.x = screenFrame.x + screenFrame.w / 2
  frame.y = screenFrame.y
  frame.w = screenFrame.w / 2
  frame.h = screenFrame.h
  local duration = 0
  wnd:setFrame(frame, duration)
end)


hs.hotkey.bind("⌘⇧", ",", function()
  local wnd = hs.window.frontmostWindow()
  if not wnd then return end
  local frame = wnd:frame()
  ---@type table
  local screenFrame = wnd:screen():frame()

  frame.x = screenFrame.x
  frame.y = screenFrame.y
  frame.w = screenFrame.w
  frame.h = screenFrame.h / 2
  local duration = 0
  wnd:setFrame(frame, duration)
end)


hs.hotkey.bind("⌘⇧", ".", function()
  local wnd = hs.window.frontmostWindow()
  if not wnd then return end
  local frame = wnd:frame()
  ---@type table
  local screenFrame = wnd:screen():frame()

  frame.x = screenFrame.x
  frame.y = screenFrame.y + screenFrame.h / 2
  frame.w = screenFrame.w
  frame.h = screenFrame.h / 2
  local duration = 0
  wnd:setFrame(frame, duration)
end)


hs.hotkey.bind("⌘⇧", "y", function()
  local wnd = hs.window.frontmostWindow()
  if not wnd then return end
  local frame = wnd:frame()
  ---@type table
  local screenFrame = wnd:screen():frame()

  frame.x = screenFrame.x
  frame.y = screenFrame.y
  frame.w = screenFrame.w / 2
  frame.h = screenFrame.h / 2
  local duration = 0
  wnd:setFrame(frame, duration)
end)


hs.hotkey.bind("⌘⇧", "u", function()
  local wnd = hs.window.frontmostWindow()
  if not wnd then return end
  local frame = wnd:frame()
  ---@type table
  local screenFrame = wnd:screen():frame()

  frame.x = screenFrame.x + screenFrame.w / 2
  frame.y = screenFrame.y
  frame.w = screenFrame.w / 2
  frame.h = screenFrame.h / 2
  local duration = 0
  wnd:setFrame(frame, duration)
end)


hs.hotkey.bind("⌘⇧", "i", function()
  local wnd = hs.window.frontmostWindow()
  if not wnd then return end
  local frame = wnd:frame()
  ---@type table
  local screenFrame = wnd:screen():frame()

  frame.x = screenFrame.x
  frame.y = screenFrame.y + screenFrame.h / 2
  frame.w = screenFrame.w / 2
  frame.h = screenFrame.h / 2
  local duration = 0
  wnd:setFrame(frame, duration)
end)


hs.hotkey.bind("⌘⇧", "o", function()
  local wnd = hs.window.frontmostWindow()
  if not wnd then return end
  local frame = wnd:frame()
  ---@type table
  local screenFrame = wnd:screen():frame()

  frame.x = screenFrame.x + screenFrame.w / 2
  frame.y = screenFrame.y + screenFrame.h / 2
  frame.w = screenFrame.w / 2
  frame.h = screenFrame.h / 2
  local duration = 0
  wnd:setFrame(frame, duration)
end)


local event = {hs.eventtap.event.types.otherMouseDragged}
mouseDragServer = hs.eventtap.new(event, function(e)
  local propDx = hs.eventtap.event.properties['mouseEventDeltaX']
  local propDy = hs.eventtap.event.properties['mouseEventDeltaY']
  local dx = e:getProperty(propDx)
  local dy = e:getProperty(propDy)
  -- Prevent mouse move
  hs.mouse.absolutePosition(hs.mouse.absolutePosition())
  local event = {dx, dy}
  local scrollEvent = hs.eventtap.event.newScrollEvent(event, {}, "pixel")
  return true, {scrollEvent}
end)


local event = {hs.eventtap.event.types.otherMouseDown}
otherMouseDownServer = hs.eventtap.new(event, function(e)
  local prop = hs.eventtap.event.properties['mouseEventButtonNumber']
  local btn = e:getProperty(prop)
  local mouseButton6 = 5
  if btn ~= mouseButton6 then return end
  mouseDragServer:start()
  return true --supress mouse click
end)
otherMouseDownServer:start()


local event = {hs.eventtap.event.types.otherMouseUp}
otherMouseUpServer = hs.eventtap.new(event, function(e)
  local prop = hs.eventtap.event.properties['mouseEventButtonNumber']
  local btn = e:getProperty(prop)
  local mouseButton6 = 5
  if btn ~= mouseButton6 then return end
  mouseDragServer:stop()
  return true --supress mouse click
end)
otherMouseUpServer:start()


menuItem:addSubmenuItem("Load passwords", function()
  local msg = "Enter master password"
  local secureField = true
  local _, masterPass = hs.dialog.textPrompt(msg, "", "", "", "", secureField)
  if masterPass == "" then
    return
  end
  local db = "/Users/user/dotfiles/passwords.kdbx"
  local app = "/opt/homebrew/bin/keepassxc-cli"
  local args = {"show", "-s", db, "bit.ly"}
  local onTaskExit = function(exitCode, stdOut, _)
    if exitCode ~= 0 then
      return hs.alert.show("Error executing keepassxc")
    end
    bitlyToken = stdOut:match("Notes: (.+)\n")
    hs.alert.show("Loaded")
  end
  local task = hs.task.new(app, onTaskExit, args)
  task:setInput(masterPass)
  -- Do not trust GC
  masterPass = ""
  task:start()
end)
menuItem:addSubmenuSeparator()


menuItem:addSubmenuItem("Shorten URL", function()
  if not bitlyToken then
    return hs.alert.show("Passwords not loaded")
  end

  local clipboard = hs.pasteboard.readString()
  if not clipboard:match("^https?://") then
    return hs.alert.show("No URL in clipboard")
  end

  -- Remove query string before shortening.
  local queryPos = clipboard:find("?")
  if queryPos then
    clipboard = clipboard:sub(1, queryPos - 1)
  end

  local url = "" ..
    "https://api-ssl.bitly.com/v3/shorten" ..
    "?access_token=" .. bitlyToken ..
    "&longUrl=" .. hs.http.encodeForQuery(clipboard)
  hs.http.asyncGet(url, {}, function(status, response, _)
    if status ~= 200 then
      return hs.alert.show("Failed")
    end
    local response = hs.json.decode(response)
    hs.pasteboard.setContents(response.data.url)
    return hs.alert.show("Success")
  end)
end)
