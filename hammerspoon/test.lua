function curDirToModuleSearchPath()
  local srcFile = debug.getinfo(1).source:match("@?(.*)")
  local srcDir = srcFile:match("(.+[/\\])") or "./"
  package.path = package.path .. ";" .. srcDir .. "?.lua"
end


HsMenubar = {}
function HsMenubar:new()
  return setmetatable({
  }, {__index = self})
end


function HsMenubar:setIcon(image, isMonocolorTemplate)
end


function HsMenubar:setMenu(submenu)
end


HsEchoRequest = {}
function HsEchoRequest:new(addr)
  return setmetatable({
    _addr = addr,
    _isRunning = false,
  }, {__index = self})
end


function HsEchoRequest:setCallback(handler)
  if handler then
    handler(self, "didStart", "1.1.1.1")
  end
end


function HsEchoRequest:start()
  self._isRunning = true
end


function HsEchoRequest:stop()
  self._isRunning = false
end


function HsEchoRequest:isRunning()
  return self._isRunning
end


function HsEchoRequest:sendPayload()
end


HsEvent = {}
function HsEvent:new()
  return setmetatable({
  }, {__index = self})
end


function HsEvent:getProperty(name)
  if name == hs.eventtap.event.properties.mouseEventDeltaX then
    return 1
  elseif name == hs.eventtap.event.properties.mouseEventDeltaY then
    return 1
  elseif name == hs.eventtap.event.properties.mouseEventButtonNumber then
    return 5
  else
    assert(false)
  end
end


HsEventtap = {}
function HsEventtap:new(event, handler)
  handler(HsEvent:new())
  return setmetatable({
  }, {__index = self})
end


function HsEventtap:start()
end


function HsEventtap:stop()
end


HsAppSubelement = {}
function HsAppSubelement:new(attributes)
  local object = {}
  for k, v in pairs(attributes) do
    object[k] = v
  end
  return setmetatable(object, {__index = self})
end


function HsAppSubelement:doAXPress()
end


HsAppElement = {}
function HsAppElement:new()
  return setmetatable({
    AXChildren = {{
      AXChildren = {
        HsAppSubelement:new({
          AXRoleDescription = "application dock item",
          AXTitle = "System Preferences",
        }),
        HsAppSubelement:new({
          AXRoleDescription = "application dock item",
        }),
      }
    }},
  }, {__index = self})
end


HsApplication = {}
function HsApplication:new()
  return setmetatable({
  }, {__index = self})
end


function HsApplication:bundleID()
  return "com.apple.Safari"
end


function HsApplication:findMenuItem(name)
  return {}
end


function HsApplication:selectMenuItem(name)
end


HsWindow = {}
function HsWindow:new(screen)
  return setmetatable({
    _screen = screen
  }, {__index = self})
end


function HsWindow:frame()
  return {x = 0, y = 0, w = 100, h = 100}
end


function HsWindow:setFrame(frame, duration) end


function HsWindow:application()
  return HsApplication:new()
end


function HsWindow:screen()
  return self._screen
end


HsScreen = {}
function HsScreen:new()
  return setmetatable({
  }, {__index = self})
end


function HsScreen:frame()
  return {x = 0, y = 0, w = 100, h = 100}
end


HsTask = {}
function HsTask:new()
  return setmetatable({
  }, {__index = self})
end


function HsTask:start()
end


HsCanvas = {}
function HsCanvas:new(props)
  return setmetatable({
  }, {
    _props = props,
    __index = self,
    __len = function()
      return 0
    end,
  })
end


function HsCanvas:insertElement(props, element)
end


function HsCanvas:size(props)
end


function HsCanvas:imageFromCanvas()
end


Hs = {}
function Hs:new()
  local screen = HsScreen:new()
  return setmetatable({
    console = {
      clearConsole = function() end,
    },
    canvas = {
      new = function(props)
        return HsCanvas:new(props)
      end,
    },
    menubar = {
      new = function()
        return HsMenubar:new()
      end,
    },
    host = {
      cpuUsageTicks = function()
        return {
          overall = {
            active = 0,
            idle = 100,
          },
        }
      end,
    },
    timer = {
      absoluteTime = function()
        return 0
      end,
      doEvery = function(interval, handler) end,
    },
    axuielement = {
      applicationElement = function(app)
        return HsAppElement:new()
      end,
    },
    hotkey = {
      bind = function(modifiers, hotkey, handler)
        handler()
      end,
    },
    network = {
      ping = {
        echoRequest = function(addr)
          return HsEchoRequest:new(addr)
        end,
      },
      primaryInterfaces = function()
        return nil, nil
      end,
    },
    eventtap = {
      event  = {
        types = {
          otherMouseDragged = 1,
        },
        properties = {
          mouseEventDeltaX = 0,
          mouseEventDeltaY = 1,
          mouseEventButtonNumber = 2,
        },
        newScrollEvent = function(event, props, type) end,
      },
      new = function(event, handler)
        return HsEventtap:new(event, handler)
      end,
    },
    window = {
      frontmostWindow = function()
        return HsWindow:new(screen)
      end,
    },
    pasteboard = {
      readString = function()
        return ""
      end,
      setContents = function(content) end,
    },
    mouse = {
      absolutePosition = function(position) end,
    },
    task = {
      new = function(app, callback, args)
        return HsTask:new()
      end,
    },
    battery = {
      percentage = function()
        return 100
      end
    },
    styledtext = {
      new = function(text, props) end
    },
    settings = {
      get = function(name) end,
      set = function(name, val) end,
    }
  }, {__index = self})
end


function Hs:application(name)
  return nil
end


curDirToModuleSearchPath()
hs = Hs:new()
require "main"

assert(
  table.concat(app:ipStrToList("192.168.0.1")) ==
  table.concat({192, 168, 0, 1}))

app:clickDockItem(1)
app:registerHotkeys()
app:registerMouse()
history = {}
app:icmpPingToHistory(history, "didStart")
app:icmpPingToHistory(history, "didFail", "error")
app:icmpPingToHistory(history, "sendPacket", nil, 1)
assert(#history == 1)
app:icmpPingToHistory(history, "receivedPacket", nil, 1)
app:icmpPingToHistory(history, "receivedUnexpectedPacket", nil)
app:restartInetPing()
app:restartRouterPing()
app:netGraphFromIcmpHistory(history)
app:cpuGraphFromLoadHistory({1, 2, 3})
app:onHeartbeat()
