App = {}
function App:new()
  local inst = setmetatable({
  }, {__index = self})
  inst.menuItem = menuitem:new()
  inst.MENU_LIGHTS_ON = 2
  inst.MENU_LIGHTS_OFF = 3
  inst.lastLightsCount = 0
  inst.lastCpuUsage = hs.host.cpuUsageTicks()
  inst.cpuLoadHistory = {}
  -- Cpu history is smaller to preserve space since only constant load is
  -- of interest
  inst.maxCpuLoadHistory = 10
  inst.routerIcmpHistory = {}
  inst.inetIcmpHistory = {}
  -- Interval, in seconds, to send pings, check cpu load etc.
  inst.heartbeatInterval = 0.2
  inst.heartbeatsPerSec = 5
  inst.heartbeatsInBigTimeout = inst.heartbeatsPerSec * 10
  inst.heartbeatsInMedTimeout = inst.heartbeatsPerSec * 1
  -- Increased on first loop, start with 0 to kick off all % checks
  inst.heartbeatCounter = -1
  inst.heartbeatTime = hs.timer.absoluteTime() / 1000000000
  inst.maxIcmpHistory = 20
  inst.lastBattery = nil
  inst.secondsSinceBatteryDec = 0
  inst.keepBrightness = false
  -- Keys are the charge amount the decrease is from, values are number
  -- of seconds it took for battery to discharge from that value. Ex, if
  -- key 90 contains value of 1000 that means that it took 1000 seconds for
  -- a battery to discharge from 90 to 89 percents.
  inst.batteryDecHistory = {}
  inst.telegramDockItem = nil
  inst.mailDockItem = nil
  inst.slackDockItem = nil
  inst.discordDockItem = nil
  inst.whatsappDockItem = nil
  inst.vkToken = nil
  -- Can't get if not connected to the network.
  inst.ipv4IfaceName = nil
  inst.lastIp = nil
  inst.inetIp = "1.1.1.1"
  inst.routerIp = nil
  inst.pingRouterInt = false
  inst.pingRouterExt = false
  inst.pingInetInt = false
  inst.pingInetExt = false
  inst.karabinerState = {}
  return inst
end


function App:loadSettings()
  self.pingRouterInt = hs.settings.get("pingRouterInt")
  self.pingRouterExt = hs.settings.get("pingRouterExt")
  self.pingInetInt = hs.settings.get("pingInetInt")
  self.pingInetExt = hs.settings.get("pingInetExt")
  self.showBatteryTime = hs.settings.get("showBatteryTime")
  self.keepBrightness = hs.settings.get("keepBrightness")
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
      -- interested only for notifications.
      if isSeparatorFound then
        if currentNumber == number then
          item:doAXPress()
          return
        end
        currentNumber = currentNumber + 1
      else
        local title = item.AXTitle
        -- Renamed in macOS 13
        if title == "System Preferences" or title == "System Settings" then
          isSeparatorFound = true
        end
      end
    end
  end
  if not isSeparatorFound then
    print("Separator (settings app) not found in the dock")
  end
end


function App:startHttpServer()
  self.httpServer = hs.httpserver.new()
  self.httpServer:setInterface("localhost")
  self.httpServer:setPort("2020")
  self.httpServer:setCallback(function(request, path, headers, body)
    if body == "" then
      return "json body not found", 400, {}
    end
    local json = hs.json.decode(body)
    if json.command == "switch_app" then

      if json.app_index then
        local appIndex = tonumber(json.app_index)
        if not appIndex then
          return "switch_app without app_index", 400, {}
        end
        if appIndex < 0 or appIndex > 9 then
          return "switch_app.app_index not in 0..9 range", 400, {}
        end
        self:clickDockItem(appIndex + 1)
        return "", 200, {}
      elseif json.app_id then
        if not self.slackDockItem then
          return "slack not found in dock", 400, {}
        end
        self.slackDockItem:doAXPress()
        return "", 200, {}
      else
        return "app not specified", 400, {}
      end

    elseif json.command == "switch_web_profile" then

      local profileIndex = tonumber(json.profile_index)
      if not profileIndex then
        return "switch_web_profile without profile_index", 400, {}
      end
      if profileIndex < 0 or profileIndex > 9 then
        return "switch_web_profile.profile_index not in 0..9 range", 400, {}
      end

      waitSec = 2
      browser = hs.application.open("Google Chrome", waitSec)
      if not browser then
        return "failed to activate chrome", 400, {}
      end

      menu = browser:getMenuItems()
      for _, topLevel in ipairs(menu) do
        if topLevel.AXTitle == "Profiles" then
          for pos, item in ipairs(topLevel.AXChildren[1]) do
            if pos == profileIndex + 1 then
              browser:selectMenuItem({"Profiles", item.AXTitle})
              return "", 200, {}
            end
          end
        end
      end
      return "profile with index " .. profileIndex .. " not found", 400, {}

    elseif json.command == "show_char_picker" then
      self:showCharPicker()
      return "", 200, {}
    elseif json.command == "shorten_url" then
      self:shortenUrlInClipboard()
      return "", 200, {}
    else
      return "unknown command", 400, {}
    end
  end)
  self.httpServer:start()
end


function App:_setWndFrame(wnd, frame)
  if not wnd then return end

  local app = hs.axuielement.applicationElement(wnd:application())
  local wasEnhanced = app.AXEnhancedUserInterface
  app.AXEnhancedUserInterface = false

  wnd:setTopLeft(frame.x, frame.y)
  hs.timer.usleep(0.1 * 1000 * 1000)
  local duration = 0
  wnd:setFrame(frame, duration)

  app.AXEnhancedUserInterface = wasEnhanced
end


function App:_moveWndToScreen(wnd, screen)
  ---@type table
  local wndFrame = wnd:frame()
  ---@type table
  local srcFrame = wnd:screen():frame()
  ---@type table
  local dstFrame = screen:frame()

  local dx = (math.abs(srcFrame.x - wndFrame.x)) / srcFrame.w
  local dy = (math.abs(srcFrame.y - wndFrame.y)) / srcFrame.h
  local dw = wndFrame.w / srcFrame.w
  local dh = wndFrame.h / srcFrame.h

  dstFrame.x = dstFrame.x + dstFrame.w * dx
  dstFrame.y = dstFrame.y + dstFrame.h * dy
  dstFrame.w = dstFrame.w * dw
  dstFrame.h = dstFrame.h * dh

  self:_setWndFrame(wnd, dstFrame)
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

    local oldClipboard = hs.pasteboard.uniquePasteboard()
    hs.pasteboard.writeAllData(oldClipboard, hs.pasteboard.readAllData(nil))

    hs.pasteboard.setContents(hs.pasteboard.readString())
    -- command-v may not work due to focus issues
    app:selectMenuItem("Paste")

    hs.timer.doAfter(0.01, function()
      -- If not delayed in will replace the clipboard content BEFORE
      -- it's pasted
      hs.pasteboard.writeAllData(nil, hs.pasteboard.readAllData(oldClipboard))
      hs.pasteboard.deletePasteboard(oldClipboard)
    end)
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

  -- move window screen down
  hs.hotkey.bind("⌘⌥", "j", function()
    local wnd = hs.window.frontmostWindow()
    if not wnd then return end
    ---@type table
    self:_moveWndToScreen(wnd, hs.screen.primaryScreen())
  end)

  -- move window screen up
  hs.hotkey.bind("⌘⌥", "k", function()
    local wnd = hs.window.frontmostWindow()
    if not wnd then return end
    ---@type table
    local primaryScreen = hs.screen.primaryScreen()
    local nonprimaryScreen = primaryScreen
    for _, curScreen in ipairs(hs.screen.allScreens()) do
      if curScreen ~= primaryScreen then
        nonprimaryScreen = curScreen
        break
      end
    end
    self:_moveWndToScreen(wnd, nonprimaryScreen)
  end)

  hs.hotkey.bind("⌘⇧", "space", function()
    local wnd = hs.window.frontmostWindow()
    if not wnd then return end
    ---@type table
    local screenFrame = wnd:screen():frame()
    self:_setWndFrame(wnd, screenFrame)
  end)

  hs.hotkey.bind("⌘⇧", "m", function()
    local wnd = hs.window.frontmostWindow()
    if not wnd then return end
    local frame = wnd:frame()
    ---@type table
    local screenFrame = wnd:screen():frame()

    frame.x = screenFrame.x
    frame.y = screenFrame.y
    frame.w = screenFrame.w / 2
    frame.h = screenFrame.h
    self:_setWndFrame(wnd, frame)
  end)

  hs.hotkey.bind("⌘⇧", ",", function()
    local wnd = hs.window.frontmostWindow()
    if not wnd then return end
    local frame = wnd:frame()
    ---@type table
    local screenFrame = wnd:screen():frame()

    frame.x = screenFrame.x + screenFrame.w / 2
    frame.y = screenFrame.y
    frame.w = screenFrame.w / 2
    frame.h = screenFrame.h
    self:_setWndFrame(wnd, frame)
  end)

  hs.hotkey.bind("⌘⇧", ".", function()
    local wnd = hs.window.frontmostWindow()
    if not wnd then return end
    local frame = wnd:frame()
    ---@type table
    local screenFrame = wnd:screen():frame()

    frame.x = screenFrame.x
    frame.y = screenFrame.y
    frame.w = screenFrame.w
    frame.h = screenFrame.h / 2
    self:_setWndFrame(wnd, frame)
  end)

  hs.hotkey.bind("⌘⇧", "/", function()
    local wnd = hs.window.frontmostWindow()
    if not wnd then return end
    local frame = wnd:frame()
    ---@type table
    local screenFrame = wnd:screen():frame()

    frame.x = screenFrame.x
    frame.y = screenFrame.y + screenFrame.h / 2
    frame.w = screenFrame.w
    frame.h = screenFrame.h / 2
    self:_setWndFrame(wnd, frame)
  end)

  hs.hotkey.bind("⌘⇧", "u", function()
    local wnd = hs.window.frontmostWindow()
    if not wnd then return end
    local frame = wnd:frame()
    ---@type table
    local screenFrame = wnd:screen():frame()

    frame.x = screenFrame.x
    frame.y = screenFrame.y
    frame.w = screenFrame.w / 2
    frame.h = screenFrame.h / 2
    self:_setWndFrame(wnd, frame)
  end)

  hs.hotkey.bind("⌘⇧", "i", function()
    local wnd = hs.window.frontmostWindow()
    if not wnd then return end
    local frame = wnd:frame()
    ---@type table
    local screenFrame = wnd:screen():frame()

    frame.x = screenFrame.x + screenFrame.w / 2
    frame.y = screenFrame.y
    frame.w = screenFrame.w / 2
    frame.h = screenFrame.h / 2
    self:_setWndFrame(wnd, frame)
  end)

  hs.hotkey.bind("⌘⇧", "o", function()
    local wnd = hs.window.frontmostWindow()
    if not wnd then return end
    local frame = wnd:frame()
    ---@type table
    local screenFrame = wnd:screen():frame()

    frame.x = screenFrame.x
    frame.y = screenFrame.y + screenFrame.h / 2
    frame.w = screenFrame.w / 2
    frame.h = screenFrame.h / 2
    self:_setWndFrame(wnd, frame)
  end)

  hs.hotkey.bind("⌘⇧", "p", function()
    local wnd = hs.window.frontmostWindow()
    if not wnd then return end
    local frame = wnd:frame()
    ---@type table
    local screenFrame = wnd:screen():frame()

    frame.x = screenFrame.x + screenFrame.w / 2
    frame.y = screenFrame.y + screenFrame.h / 2
    frame.w = screenFrame.w / 2
    frame.h = screenFrame.h / 2
    self:_setWndFrame(wnd, frame)
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
    return true --suppress mouse click
  end)
  self.otherMouseDownServer:start()

  local event = {hs.eventtap.event.types.otherMouseUp}
  self.otherMouseUpServer = hs.eventtap.new(event, function(e)
    local prop = hs.eventtap.event.properties['mouseEventButtonNumber']
    local btn = e:getProperty(prop)
    local mouseButton6 = 5
    if btn ~= mouseButton6 then return end
    self.mouseDragServer:stop()
    return true --suppress mouse click
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
    timeSec = hs.timer.absoluteTime() / 1000000000
    table.insert(history, {seq = seq, timeSend = timeSec})
    if #history > self.maxIcmpHistory then
      table.remove(history, 1)
    end
  elseif msg == "receivedPacket" then
    local icmp, seq = ...
    for _, item in ipairs(history) do
      if item.seq == seq then
        timeSec = hs.timer.absoluteTime() / 1000000000
        item.timeRecv = timeSec
        break
      end
    end
  elseif msg == "receivedUnexpectedPacket" then
    local icmp = ...
    print("received unexpected icmp ")
  end
end


function App:stdOutPingToHistory(history, stdOut)

  local timeRecvSec = hs.timer.absoluteTime() / 1000000000
  local addToHistory = function(item)
    table.insert(history, item)
    if #history > self.maxIcmpHistory then
      table.remove(history, 1)
    end
  end

  -- Request timeout for icmp_seq 460
  local pattern = "Request timeout"
  if stdOut:match(pattern) then
    return addToHistory({error = true})
  end

  -- 64 bytes from 1.1.1.1: icmp_seq=11029 ttl=52 time=34.453 ms
  local pattern = "time=([0-9\\.]+) ms"
  delayStr = stdOut:match(pattern)
  if not delayStr then
    return addToHistory({error = true})
  end

  local timeSendSec = timeRecvSec - tonumber(delayStr) / 1000
  addToHistory({timeRecv = timeRecvSec, timeSend = timeSendSec})
end


function App:restartInetPingInt()
  if self.inetPingIntSrv then
    self.inetPingIntSrv:stop()
    self.inetPingIntSrv:setCallback(nil)
    self.inetPingIntSrv = nil
  end
  if self.pingInetInt and self.inetIp then
    self.inetPingIntSrv = hs.network.ping.echoRequest(self.inetIp)
    self.inetPingIntSrv:setCallback(function(echoRequestObject, msg, ...)
      self:icmpPingToHistory(self.inetIcmpHistory, msg, ...)
    end)
    self.inetPingIntSrv:start()
  end
end


function App:restartInetPingExt()
  if self.inetPingExtSrv then
    self.inetPingExtSrv:terminate()
    self.inetPingExtSrv:setStreamingCallback(nil)
    self.inetPingExtSrv = nil
  end
  if self.pingInetExt and self.inetIp then
    local app = "/sbin/ping"
    local args = {"-i", "0.2", self.inetIp}
    local streamingCallback = function(task, stdOut, stdErr)
      self:stdOutPingToHistory(self.inetIcmpHistory, stdOut)
      return true
    end
    self.inetPingExtSrv = hs.task.new(app, nil, streamingCallback, args)
    self.inetPingExtSrv:start()
  end
end


function App:restartRouterPingInt()
  if self.routerPingIntSrv then
    self.routerPingIntSrv:stop()
    self.routerPingIntSrv:setCallback(nil)
    self.routerPingIntSrv = nil
  end
  if self.pingRouterInt and self.routerIp then
    self.routerPingIntSrv = hs.network.ping.echoRequest(self.routerIp)
    self.routerPingIntSrv:setCallback(function(echoRequestObject, msg, ...)
      self:icmpPingToHistory(self.routerIcmpHistory, msg, ...)
    end)
    self.routerPingIntSrv:start()
  end
end


function App:restartRouterPingExt()
  if self.routerPingExtSrv then
    self.routerPingExtSrv:terminate()
    self.routerPingExtSrv:setStreamingCallback(nil)
    self.routerPingExtSrv = nil
  end
  if self.pingRouterExt and self.routerIp then
    local app = "/sbin/ping"
    local args = {"-i", "0.2", self.routerIp}
    local streamingCallback = function(task, stdOut, stdErr)
      self:stdOutPingToHistory(self.routerIcmpHistory, stdOut)
      return true
    end
    self.routerPingExtSrv = hs.task.new(app, nil, streamingCallback, args)
    self.routerPingExtSrv:start()
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


function App:getDockItems()
  -- Use exact name since there are "Dock Extra" etc.
  self.dock = hs.application.find("^Dock$")
  local dockElement = hs.axuielement.applicationElement(self.dock)
  -- Re-read dock items for clicking them
  self.dockItems = dockElement.AXChildren[1].AXChildren
end


function App:getKarabinerState()
  local dir = "/Library/Application Support/org.pqrs/tmp/"
  local path = dir .. "karabiner_grabber_manipulator_environment.json"
  self.karabinerState = hs.json.read(path)
end


function App:onHeartbeat()

  self.heartbeatCounter = self.heartbeatCounter + 1

  -- 0.5% CPU
  if self.pingInetInt then
    if self.inetPingIntSrv and self.inetPingIntSrv:isRunning() then
      self.inetPingIntSrv:sendPayload()
    end
  end
  if self.pingRouterInt then
    if self.routerPingIntSrv and self.routerPingIntSrv:isRunning() then
      self.routerPingIntSrv:sendPayload()
    end
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
  local isBigTimeout = (self.heartbeatCounter % heartbeatsToWait) == 0
  isBigTimeout = self.heartbeatCounter == 0 or isBigTimeout

  heartbeatsToWait = self.heartbeatsInMedTimeout
  local isMedTimeout = (self.heartbeatCounter % heartbeatsToWait) == 0
  isMedTimeout = self.heartbeatCounter == 0 or isMedTimeout

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

  if isBigTimeout then
    -- Update info about elgato KeyLights
    elgato:update()
    -- Get new dock items to click on them with meta-N hotkeys
    self:getDockItems()
    if self.keepBrightness then
      -- Prevent auto-brightness
      hs.brightness.set(50)
    end

    local lightsCount = elgato:lightsCount()
    if lightsCount ~= self.lastLightsCount then
      self.lastLightsCount = lightsCount
      local title = "Turn on lights (" .. lightsCount .. ")"
      self.menuItem:setSubmenuItemTitle(self.MENU_LIGHTS_ON, title)
      local title = "Turn off lights (" .. lightsCount .. ")"
      self.menuItem:setSubmenuItemTitle(self.MENU_LIGHTS_OFF, title)
    end
  end

  if isMedTimeout then
    self:getKarabinerState()
  end

  if not self.telegramDockItem
     or not self.mailDockItem
     or not self.slackDockItem
     or not self.discordDockItem
     or not self.whatsappDockItem then
    -- Do not check too often, CPU expensive
    if isBigTimeout then
      for _, item in ipairs(self.dockItems) do
        if item.AXTitle == "Telegram" then
          self.telegramDockItem = item
        end
        if item.AXTitle == "Mimestream" then
          self.mailDockItem = item
        end
        if item.AXTitle == "Slack" then
          self.slackDockItem = item
        end
        if item.AXTitle == "Discord" then
          self.discordDockItem = item
        end
        if item.AXTitle == "WhatsApp" then
          self.whatsappDockItem = item
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
    self:restartRouterPingInt()
    self:restartRouterPingExt()
  end

  local needNewRouterIp = self.lastIp and not self.routerIp
  -- Router Ip can change without local IP being changed on VPN connect
  if (needNewRouterIp or isBigTimeout) and not netstat:isRunning() then
    netstat:get(function(res)
      if not res then
        self.routerIp = nil
        self.routerIcmpHistory = {}
        self:restartRouterPingInt()
        self:restartRouterPingExt()
      elseif self.routerIp ~= res.gateway then
        self.routerIp = res.gateway
        self.routerIcmpHistory = {}
        self:restartRouterPingInt()
        self:restartRouterPingExt()
      end
    end)
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
    -- "•" indicates channel messages, counter indicates privates and mentions
    if self.discordDockItem.AXStatusLabel ~= "•" then
      table.insert(notifications, "D")
    end
  end
  if self.whatsappDockItem and self.whatsappDockItem.AXStatusLabel then
    table.insert(notifications, "W")
  end

  self.menuItem:clear()

  if #notifications > 0 then
    -- Flash notification icons
    if self.heartbeatCounter % 10 == 0 then
      self.menuItem:addText(table.concat(notifications, " "))
    else
      self.menuItem:addText((" "):rep(#notifications * 2 - 1))
    end
    self.menuItem:addSpacer(8)
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

  local batteryText = ("%.0f"):format(battery)
  if self.showBatteryTime then
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
    batteryText = batteryText .. timeLeft
  end

  local indicator = {}
  if self.karabinerState and self.karabinerState["variables"] then
    if self.karabinerState["variables"]["_m1"] == 1 then
      table.insert(indicator, {
        color = {red = 0.0, green = 1.0, blue = 0.0}
      })
    end
    if self.karabinerState["variables"]["_m2"] == 1 then
      table.insert(indicator, {
        color = {red = 1.0, green = 1.0, blue = 0.0}
      })
    end
    if self.karabinerState["variables"]["_m3"] == 1 then
      table.insert(indicator, {
        color = {red = 0.0, green = 1.0, blue = 1.0}
      })
    end
  end

  self.menuItem:addIndicator(indicator)
  self.menuItem:addSpacer(4)
  self.menuItem:addText("🛜")
  self.menuItem:addSpacer(4)
  self.menuItem:addGraph(routerGraph, self.maxIcmpHistory)
  self.menuItem:addSpacer(4)
  self.menuItem:addText("🌐")
  self.menuItem:addSpacer(4)
  self.menuItem:addGraph(inetGraph, self.maxIcmpHistory)
  self.menuItem:addSpacer(4)
  self.menuItem:addText("💎")
  self.menuItem:addSpacer(4)
  self.menuItem:addGraph(cpuGraph, self.maxCpuLoadHistory)
  self.menuItem:addSpacer(4)
  if hs.battery.isCharging() or hs.battery.isCharged() then
    self.menuItem:addText("🔋")
  else
    self.menuItem:addText("🪫")
  end
  self.menuItem:addSpacer(4)
  -- Fixed width font size for 3 characters so "1" and "100" take same space
  self.menuItem:addTextWithWidth(batteryText, 3 * 8)
  self.menuItem:update()
end


function App:startHeartbeat()
  self.heartbeatTimer = hs.timer.doEvery(self.heartbeatInterval, function()
    self:onHeartbeat()
  end)
end


function App:_shortenUrl(targetUrl)
  if not self.vkToken then
    return hs.alert.show("Passwords not loaded")
  end

  local url = "https://api.vk.com/method/utils.getShortLink"
  url = url .. "?" .. "url=" .. hs.http.encodeForQuery(targetUrl)
  url = url .. "&" .. "private=1"
  url = url .. "&" .. "access_token=" .. hs.http.encodeForQuery(self.vkToken)
  url = url .. "&" .. "v=5.199"
  hs.http.asyncGet(url, nil, function(status, response, _)
    if status ~= 200 and status ~= 201 then
      return hs.alert.show("Failed")
    end
    local response = hs.json.decode(response)
    if not response.response then
      if response.error then
        dir(response.error)
      else
        dir(response)
      end
      return hs.alert.show("Failed")
    else
      hs.pasteboard.setContents(response.response.short_url)
      return hs.alert.show("Success")
    end
  end)
end


function App:shortenUrlInClipboard()
  local clipboard = hs.pasteboard.readString()
  if not clipboard:match("^https?://") then
    return hs.alert.show("No URL in clipboard")
  end
  if clipboard:match("^https?://vk.cc") then
    return hs.alert.show("Short URL in clipboard")
  end
  self:_shortenUrl(clipboard)
end


function App:shortenAndTrimUrlInClipboard()
  local clipboard = hs.pasteboard.readString()
  if not clipboard:match("^https?://") then
    return hs.alert.show("No URL in clipboard")
  end
  if clipboard:match("^https?://vk.cc") then
    return hs.alert.show("Short URL in clipboard")
  end
  -- Remove query string before shortening.
  local queryPos = clipboard:find("?")
  if queryPos then
    clipboard = clipboard:sub(1, queryPos - 1)
  end
  self:_shortenUrl(clipboard)
end


function App:createMenu()

  self.menuItem:addSubmenuItem("Reload", function()
    hs:reload()
  end)

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
    local args = {
      "show", "-s", db, "vk.gvp-url-shortener", "--attributes", "notes"
    }
    local onTaskExit = function(exitCode, stdOut, _)
      if exitCode ~= 0 then
        return hs.alert.show("Error executing keepassxc")
      end
      self.vkToken = stdOut
      hs.alert.show("Loaded")
    end
    local task = hs.task.new(app, onTaskExit, args)
    task:setInput(masterPass)

    -- Do not trust GC
    masterPass = ""
    task:start()
  end)

  self.menuItem:addSubmenuCheckbox(
    "Ping router (internal)",
    self.pingRouterInt,
    function(checked)
      self.pingRouterInt = checked
      self.routerIcmpHistory = {}
      hs.settings.set("pingRouterInt", self.pingRouterInt)
      self:restartRouterPingInt()
    end
  )

  self.menuItem:addSubmenuCheckbox(
    "Ping router (external)",
    self.pingRouterExt,
    function(checked)
      self.pingRouterExt = checked
      self.routerIcmpHistory = {}
      hs.settings.set("pingRouterExt", self.pingRouterExt)
      self:restartRouterPingExt()
    end
  )

  self.menuItem:addSubmenuCheckbox(
    "Ping internet (internal)",
    self.pingInetInt,
    function(checked)
      self.pingInetInt = checked
      self.inetIcmpHistory = {}
      hs.settings.set("pingInetInt", self.pingInetInt)
      self:restartInetPingInt()
    end
  )

  self.menuItem:addSubmenuCheckbox(
    "Ping internet (external)",
    self.pingInetExt,
    function(checked)
      self.pingInetExt = checked
      self.inetIcmpHistory = {}
      hs.settings.set("pingInetExt", self.pingInetExt)
      self:restartInetPingExt()
    end
  )

  self.menuItem:addSubmenuCheckbox(
    "Show battery time",
    self.showBatteryTime,
    function(checked)
      self.showBatteryTime = checked
      hs.settings.set("showBatteryTime", self.showBatteryTime)
    end
  )

  self.menuItem:addSubmenuCheckbox(
    "Keep brightness",
    self.keepBrightness,
    function(checked)
      self.keepBrightness = checked
      hs.settings.set("keepBrightness", self.keepBrightness)
    end
  )

  self.menuItem:addSubmenuSeparator()


  self.menuItem:addSubmenuItem("Shorten URL", function()
    self:shortenUrlInClipboard()
  end)

  self.menuItem:addSubmenuItem("Shorten & trim URL", function()
    self:shortenAndTrimUrlInClipboard()
  end)

  self.menuItem:addSubmenuItem("Flatten text", function()
    local str = hs.pasteboard.readString()
    str = str:gsub("^%s*", "")
    str = str:gsub("%s*$", "")
    -- Remove ansi hyphenation
    str = str:gsub("(%w)-%s*\n%s*(%w)", "%1%2")
    -- [] will not work for non-ansi characters like unicode hyphen
    str = str:gsub("(%w)\u{2010}%s*\n%s*(%w)", "%1%2")
    str = str:gsub("\n", " ")
    str = str:gsub("%s+", " ") -- Collapse two+ spaces into one
    hs.pasteboard.setContents(str)
  end)

  self.menuItem:addSubmenuItem("Turn on lights", function()
    elgato:switch(true)
  end, self.MENU_LIGHTS_ON)

  local name = "Turn off lights"
  self.menuItem:addSubmenuItem(name, function()
    elgato:switch(false)
  end, self.MENU_LIGHTS_OFF)
end

function App:showCharPicker()
  local oldLayout = hs.keycodes.currentLayout()
  hs.keycodes.setLayout("ABC")
  local chooser = hs.chooser.new(function(choice)
    if not choice then
      focusLastFocused()
      return
    end
    focusLastFocused()
  
    local oldClipboard = hs.pasteboard.uniquePasteboard()
    hs.pasteboard.writeAllData(oldClipboard, hs.pasteboard.readAllData(nil))

    hs.pasteboard.setContents(choice["emoji"])
    hs.eventtap.keyStroke({"cmd"}, "v")

    hs.pasteboard.writeAllData(nil, hs.pasteboard.readAllData(oldClipboard))
    hs.pasteboard.deletePasteboard(oldClipboard)
    hs.keycodes.setLayout(oldLayout)
  end)

  chooser:choices({
    -- Emoji
    {["text"] = "😊 smile", ["emoji"] = "😊"},
    {["text"] = "😜 crazy", ["emoji"] = "😜"},
    {["text"] = "😇 halo", ["emoji"] = "😇"},
    {["text"] = "😳 eyes", ["emoji"] = "😳"},
    {["text"] = "🤔 think", ["emoji"] = "🤔"},
    {["text"] = "😂 lol", ["emoji"] = "😂"},
    {["text"] = "😥 sad", ["emoji"] = "😥"},
    {["text"] = "😘 kiss", ["emoji"] = "😘"},
    {["text"] = "😍 love", ["emoji"] = "😍"},
    {["text"] = "❤️ heart", ["emoji"] = "❤️"},
    {["text"] = "🔥 fire", ["emoji"] = "🔥"},
    {["text"] = "🙏 hands", ["emoji"] = "🙏"},
    {["text"] = "🤝 shake", ["emoji"] = "🤝"},
    {["text"] = "👉 point", ["emoji"] = "👉"},
    {["text"] = "👍 yes", ["emoji"] = "👍"},
    {["text"] = "👎 no", ["emoji"] = "👎"},
    {["text"] = "👌 ok", ["emoji"] = "👌"},
    {["text"] = "👋 wave", ["emoji"] = "👋"},
    {["text"] = "🚕 car", ["emoji"] = "🚕"},
    {["text"] = "✈️ airplane", ["emoji"] = "✈️"},
    {["text"] = "€ euro", ["emoji"] = "€"},
    -- Keyboard
    {["text"] = "⌘ command", ["emoji"] = "⌘"},
    {["text"] = "⇧ shift", ["emoji"] = "⇧"},
    {["text"] = "⌥ alt", ["emoji"] = "⌥"},
    {["text"] = "↩ return", ["emoji"] = "↩"},
    {["text"] = "← left", ["emoji"] = "←"},
    {["text"] = "→ right", ["emoji"] = "→"},
    {["text"] = "↑ up", ["emoji"] = "↑"},
    {["text"] = "↓ down", ["emoji"] = "↓"},
    -- Languages
    {["text"] = "🇷🇺 Russian", ["emoji"] = "🇷🇺"},
    {["text"] = "🇬🇧 English", ["emoji"] = "🇬🇧"},
    {["text"] = "🇳🇱 Dutch", ["emoji"] = "🇳🇱"},
    -- Tags
    {["text"] = "侵 mark", ["emoji"] = "侵"},
    {["text"] = "教 speaker", ["emoji"] = "教"},
    {["text"] = "技 skilled", ["emoji"] = "技"},
    {["text"] = "力 influencer", ["emoji"] = "力"},
    {["text"] = "大 boss", ["emoji"] = "大"},
    {["text"] = "死 dead", ["emoji"] = "死"},
    -- Relations
    {["text"] = "郎 son", ["emoji"] = "郎"},
    {["text"] = "娘 daughter", ["emoji"] = "娘"},
    {["text"] = "相 partner", ["emoji"] = "相"},
    {["text"] = "友 friend", ["emoji"] = "友"},
    {["text"] = "僚 colleague", ["emoji"] = "僚"},
    -- Job or company suffixes
    {["text"] = "元 ex", ["emoji"] = "元"},
    {["text"] = "政 head", ["emoji"] = "政"},
    {["text"] = "主 organizer", ["emoji"] = "主"},
    {["text"] = "委 committee", ["emoji"] = "委"},
    {["text"] = "音 podcast", ["emoji"] = "音"},
    -- Language learning
    {["text"] = "去 past", ["emoji"] = "去"},
    {["text"] = "完 perfect", ["emoji"] = "完"},
    {["text"] = "多 plural", ["emoji"] = "多"},
    -- Utility tags
    {["text"] = "会 meet", ["emoji"] = "会"},
    {["text"] = "✉️ mail", ["emoji"] = "✉️"},
    {["text"] = "業 LFE", ["emoji"] = "業"},
    {["text"] = "員 LFW", ["emoji"] = "員"},
  })

  chooser:show()
end
