require "helpers"
require "menuitem"


App = {}
function App:new()
  local inst = setmetatable({
  }, {__index = self})
  inst.menuItem = menuitem:new()
  inst.lastCpuUsage = hs.host.cpuUsageTicks()
  inst.cpuLoadHistory = {}
  inst.maxCpuLoadHistory = 20
  inst.routerIcmpHistory = {}
  inst.inetIcmpHistory = {}
  -- Interval, in seconds, to send pings, check cpu load etc.
  inst.heartbeatInterval = 0.2
  inst.heartbeatsPerSec = 5
  inst.heartbeatsInBigTimeout = inst.heartbeatsPerSec * 10
  -- Increased on first loop, start with 0 to kick off all % checks
  inst.heartbeatCounter = -1
  inst.heartbeatTime = hs.timer.absoluteTime() / 1000000000
  inst.maxIcmpHistory = 20
  inst.lastBattery = nil
  inst.secondsSinceBatteryDec = 0
  -- Keys are the charge amount the decrease is from, values are number
  -- of seconds it took for battery to discharge from that value. Ex, if
  -- key 90 contains value of 1000 that means that it took 1000 seconds for
  -- a battery to discharge from 90 to 89 percents.
  inst.batteryDecHistory = {}
  inst.dock = hs.application("Dock")
  local dockElement = hs.axuielement.applicationElement(inst.dock)
  inst.dockItems = dockElement.AXChildren[1].AXChildren
  inst.telegramDockItem = nil
  inst.mailDockItem = nil
  inst.slackDockItem = nil
  inst.discordDockItem = nil
  inst.bitlyToken = nil
  -- Can't get if not connected to the network.
  inst.ipv4IfaceName = nil
  inst.lastIp = nil
  inst.inteIp = "1.1.1.1"
  inst.routerIp = nil
  inst.routerIpTask = nil
  inst.routerPingSrv = nil
  inst.pingRouter = false
  inst.pingInet = false
  return inst
end


function App:loadSettings()
  self.pingRouter = hs.settings.get("pingRouter")
  self.pingInet = hs.settings.get("pingInet")
end


function App:ipStrToList(ip)
  local items = {}
  for v in (ip):gmatch("[^.]+") do
    table.insert(items, tonumber(v))
  end
  return items
end


function App:clickDockItem(number)
  local currentNumber = 1
  local isSeparatorFound = false
  for _, item in ipairs(self.dockItems) do
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


function App:registerHotkeys()
  local hotkeys = {"2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="}
  for i, hotkey in ipairs(hotkeys) do
    hs.hotkey.bind({"⌘", "⌃", "⌥"}, hotkey, function()
      self:clickDockItem(i)
    end)
  end

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
end


function App:registerMouse()
  local event = {hs.eventtap.event.types.otherMouseDragged}
  self.mouseDragServer = hs.eventtap.new(event, function(e)
    local propDx = hs.eventtap.event.properties["mouseEventDeltaX"]
    local propDy = hs.eventtap.event.properties["mouseEventDeltaY"]
    local dx = e:getProperty(propDx)
    local dy = e:getProperty(propDy)
    -- Prevent mouse move
    hs.mouse.absolutePosition(hs.mouse.absolutePosition())
    local event = {dx, dy}
    local scrollEvent = hs.eventtap.event.newScrollEvent(event, {}, "pixel")
    return true, {scrollEvent}
  end)

  local event = {hs.eventtap.event.types.otherMouseDown}
  self.otherMouseDownServer = hs.eventtap.new(event, function(e)
    local prop = hs.eventtap.event.properties['mouseEventButtonNumber']
    local btn = e:getProperty(prop)
    local mouseButton6 = 5
    if btn ~= mouseButton6 then return end
    self.mouseDragServer:start()
    return true --supress mouse click
  end)
  self.otherMouseDownServer:start()

  local event = {hs.eventtap.event.types.otherMouseUp}
  self.otherMouseUpServer = hs.eventtap.new(event, function(e)
    local prop = hs.eventtap.event.properties['mouseEventButtonNumber']
    local btn = e:getProperty(prop)
    local mouseButton6 = 5
    if btn ~= mouseButton6 then return end
    self.mouseDragServer:stop()
    return true --supress mouse click
  end)
  self.otherMouseUpServer:start()
end


function App:icmpPingToHistory(history, msg, ...)
  if msg == "didStart" then
    local address = ...
  elseif msg == "didFail" then
    local error = ...
    print("ping server failed with " .. error)
  elseif msg == "sendPacket" or msg == "sendPacketFailed" then
    local icmp, seq = ...
    timeSec = hs.timer.absoluteTime() / 1000000000;
    table.insert(history, {seq = seq, timeSend = timeSec})
    if #history > self.maxIcmpHistory then
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


function App:restartInetPing()
  if self.inetPingSrv then
    self.inetPingSrv:stop()
    self.inetPingSrv:setCallback(nil)
    self.inetPingSrv = nil
  end
  if self.pingInet and self.inteIp then
    self.inetPingSrv = hs.network.ping.echoRequest(self.inteIp)
    self.inetPingSrv:setCallback(function(echoRequestObject, msg, ...)
      self:icmpPingToHistory(self.inetIcmpHistory, msg, ...)
    end)
    self.inetPingSrv:start()
  end
end


function App:restartRouterPing()
  if self.routerPingSrv then
    self.routerPingSrv:stop()
    self.routerPingSrv:setCallback(nil)
    self.routerPingSrv = nil
  end
  if self.pingRouter and self.routerIp then
    self.routerPingSrv = hs.network.ping.echoRequest(self.routerIp)
    self.routerPingSrv:setCallback(function(echoRequestObject, msg, ...)
      self:icmpPingToHistory(self.routerIcmpHistory, msg, ...)
    end)
    self.routerPingSrv:start()
  end
end


function App:netGraphFromIcmpHistory(history)
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
      if (self.heartbeatCounter + i) % 2 == 0 then
        table.insert(graph, {val = 0.2, color = grey})
      else
        table.insert(graph, {val = 0.4, color = grey})
      end
    end
    table.insert(graph, graphItem)
  end
  return graph
end


function App:cpuGraphFromLoadHistory(history)
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


function App:onHeartbeat()

  self.heartbeatCounter = self.heartbeatCounter + 1

  -- 0.5% CPU
  if self.inetPingSrv and self.inetPingSrv:isRunning() then
    self.inetPingSrv:sendPayload()
  end
  if self.routerPingSrv and self.routerPingSrv:isRunning() then
    self.routerPingSrv:sendPayload()
  end

  ----------------------------------------------------------------------------
  -- 0.1% CPU
  -- variable.language.self.lua
  local curCpuUsage = hs.host.cpuUsageTicks()
  local lastCpuActive = self.lastCpuUsage.overall.active
  local activeDiff = curCpuUsage.overall.active - lastCpuActive
  local lastCpuIdle = self.lastCpuUsage.overall.idle
  local idleDiff = curCpuUsage.overall.idle - lastCpuIdle
  self.lastCpuUsage = curCpuUsage
  local cpuLoad = activeDiff / (activeDiff + idleDiff)
  table.insert(self.cpuLoadHistory, cpuLoad)
  if #self.cpuLoadHistory > self.maxCpuLoadHistory then
    table.remove(self.cpuLoadHistory, 1)
  end

  -- Updating too often yields high CPU usage
  if self.heartbeatCounter % self.heartbeatsPerSec ~= 0 then
    return
  end

  local heartbeatsToWait = self.heartbeatsInBigTimeout
  local isBigTimeout = self.heartbeatCounter % heartbeatsToWait == 0
  isBigTimeout = self.heartbeatCounter == 0 or isBigTimeout
  local curTime = hs.timer.absoluteTime() / 1000000000;
  local oneLess = (self.heartbeatsPerSec - 1) * self.heartbeatInterval
  local oneMore = (self.heartbeatsPerSec + 1) * self.heartbeatInterval
  local tooEarly = self.heartbeatTime + oneLess
  local tooLate = self.heartbeatTime + oneMore
  local isOneSecondPassed = false
  -- Around one second passed? (no sleep)
  if curTime >= tooEarly and curTime <= tooLate then
    isOneSecondPassed = true
  end
  self.heartbeatTime = curTime

  local routerGraph = self:netGraphFromIcmpHistory(self.routerIcmpHistory)
  local inetGraph = self:netGraphFromIcmpHistory(self.inetIcmpHistory)
  local cpuGraph = self:cpuGraphFromLoadHistory(self.cpuLoadHistory)

  if not self.telegramDockItem
     or not self.mailDockItem
     or not self.slackDockItem
     or not self.discordDockItem then
    -- Do not check too often, CPU expensive
    if isBigTimeout then
      for _, item in ipairs(self.dockItems) do
        if item.AXTitle == "Telegram" then
          self.telegramDockItem = item
        end
        if item.AXTitle == "Mail" then
          self.mailDockItem = item
        end
        if item.AXTitle == "Slack" then
          self.slackDockItem = item
        end
        if item.AXTitle == "Discord" then
          self.discordDockItem = item
        end
      end
    end
  end

  if not self.ipv4IfaceName then
    local ipv4, _ = hs.network.primaryInterfaces()
    if ipv4 then
      self.ipv4IfaceName = ipv4
    end
  end

  if self.ipv4IfaceName then
    local details = hs.network.interfaceDetails(self.ipv4IfaceName)
    if details then
      local ipv4IfaceDetails = details.IPv4
      if ipv4IfaceDetails then
        local curIp = ipv4IfaceDetails.Addresses[1]
        if self.lastIp ~= curIp then
          self.lastIp = curIp
          -- Mark for recalculation
          self.routerIp = nil
        end
      else
        self.lastIp = nil
      end
    else
      self.lastIp = nil
    end
  else
    self.lastIp = nil
  end

  if not self.lastIp and self.routerIp then
    self.routerIp = nil
    self.routerIcmpHistory = {}
    self:restartRouterPing()
  end

  local needNewRouterIp = self.lastIp and not self.routerIp
  -- Router Ip can change without local IP being chenged on VPN connect
  if needNewRouterIp or isBigTimeout then
    function onRouteToolExit(exitCode, stdOut, _)
      if exitCode ~= 0 or not stdOut then
        self.routerIp = nil
        self.routerIcmpHistory = {}
        return self:restartRouterPing()
      end
      local pattern = "gateway: ([^%s]+)"
      self.routerIp = stdOut:match(pattern)
      if not self.routerIp then
        self.routerIcmpHistory = {}
        return self:restartRouterPing()
      end
      return self:restartRouterPing()
    end

    local args = {"get", "default"}
    self.routerIpTask = hs.task.new("/sbin/route", onRouteToolExit, args)
    self.routerIpTask:start()
  end

  local notifications = {}
  if self.telegramDockItem and self.telegramDockItem.AXStatusLabel then
    table.insert(notifications, "T")
  end
  if self.mailDockItem and self.mailDockItem.AXStatusLabel then
    table.insert(notifications, "E")
  end
  if self.slackDockItem and self.slackDockItem.AXStatusLabel then
    table.insert(notifications, "S")
  end
  if self.discordDockItem and self.discordDockItem.AXStatusLabel then
    -- "•" indicates channel messages, counter indicates privats and mentions
    if self.discordDockItem.AXStatusLabel ~= "•" then
      table.insert(notifications, "D")
    end
  end

  self.menuItem:clear()

  if #notifications > 0 then
    -- Flash notification icons
    if self.heartbeatCounter % 10 == 0 then
      self.menuItem:addText(table.concat(notifications, " "))
    else
      self.menuItem:addText((" "):rep(#notifications * 2 - 1))
    end
    self.menuItem:addSpacer(10)
  end

  local battery = hs.battery.percentage()
  if not self.lastBattery then self.lastBattery = battery end

  -- 100 => 99 discharge takes too much time, assume "fully charged".
  if self.lastBattery == 100 then
    self.batteryDecHistory = {}
  -- "Battery care" stops charing on 80 percent, ignore 80 => 79 "discharge".
  elseif self.lastBattery == 80 then
    -- Do nothing
  else
    if battery > self.lastBattery then
      -- Charge detected, clear history
      self.batteryDecHistory = {}
      self.secondsSinceBatteryDec = 0
    elseif battery == self.lastBattery then
      if isOneSecondPassed then
        self.secondsSinceBatteryDec = self.secondsSinceBatteryDec + 1
      end
    else
      -- Not a discharge jump: overnight stay etc?
      if battery == self.lastBattery - 1 then
        self.batteryDecHistory[self.lastBattery] = self.secondsSinceBatteryDec
      end
      self.secondsSinceBatteryDec = 0
    end
  end
  self.lastBattery = battery

  local recordCount = 0
  local totalTime = 0
  for _, seconds in pairs(self.batteryDecHistory) do
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

  self.menuItem:addText("wifi")
  self.menuItem:addSpacer(4)
  self.menuItem:addGraph(routerGraph, self.maxIcmpHistory)
  self.menuItem:addSpacer(4)
  self.menuItem:addText("inet")
  self.menuItem:addSpacer(4)
  self.menuItem:addGraph(inetGraph, self.maxIcmpHistory)
  self.menuItem:addSpacer(4)
  self.menuItem:addText("cpu")
  self.menuItem:addSpacer(4)
  self.menuItem:addGraph(cpuGraph, self.maxCpuLoadHistory)
  self.menuItem:addSpacer(4)
  self.menuItem:addText("bat")
  self.menuItem:addSpacer(4)
  self.menuItem:addText(("%.0f"):format(battery) .. timeLeft)
  self.menuItem:update()
end


function App:startHeartbeat()
  self.heartbeatTimer = hs.timer.doEvery(self.heartbeatInterval, function()
    self:onHeartbeat()
  end)
end


function App:createMenu()

  self.menuItem:addSubmenuItem("Load passwords", function()
    local msg = "Enter master password"
    local secure = true
    local _, masterPass = hs.dialog.textPrompt(msg, "", "", "", "", secure)
    if masterPass == "" then
      return
    end
    -- TODO: correctly get home dir
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

  self.menuItem:addSubmenuCheckbox(
    "Ping router",
    self.pingRouter,
    function(checked)
      self.pingRouter = checked
      hs.settings.set("pingRouter", self.pingRouter)
      self:restartRouterPing()
    end
  )

  self.menuItem:addSubmenuCheckbox(
    "Ping internet",
    self.pingInet,
    function(checked)
      self.pingInet = checked
      hs.settings.set("pingInet", self.pingInet)
      self:restartInetPing()
    end
  )

  self.menuItem:addSubmenuSeparator()


  self.menuItem:addSubmenuItem("Shorten URL", function()
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
end


app = App:new()
app:registerHotkeys()
app:registerMouse()
app:loadSettings()
app:createMenu()
app:restartInetPing()
app:startHeartbeat()
