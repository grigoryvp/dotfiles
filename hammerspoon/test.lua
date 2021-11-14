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
    addr = addr,
  }, {__index = self})
end


function HsEchoRequest:setCallback(handler)
end


function HsEchoRequest:start()
end


HsEventtap = {}
function HsEventtap:new(event, handler)
  return setmetatable({
  }, {__index = self})
end


function HsEventtap:start()
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
    [1] = HsAppSubelement:new({
      AXRoleDescription = "application dock item",
      AXTitle = "System Preferences",
    }),
    [2] = HsAppSubelement:new({
      AXRoleDescription = "application dock item",
    }),
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


function HsApplication:findMenuItem()
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


Hs = {}
function Hs:new()
  local screen = HsScreen:new()
  return setmetatable({
    console = {
      clearConsole = function() end,
    },
    canvas = {
      new = function() end,
    },
    menubar = {
      new = function()
        return HsMenubar:new()
      end,
    },
    host = {
      cpuUsageTicks = function()
        return 0
      end,
    },
    timer = {
      absoluteTime = function()
        return 0
      end,
      doEvery = function(interval, handler) end,
    },
    axuielement = {
      applicationElement = function(app) return {
        HsAppElement:new(),
      } end,
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
    },
    eventtap = {
      event  = {
        types = {
          otherMouseDragged = 1,
        },
        properties = {
          mouseEventDeltaX = 0,
          mouseEventDeltaY = 0,
        },
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
