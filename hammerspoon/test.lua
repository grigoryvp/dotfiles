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
function HsEchoRequest:new()
  return setmetatable({
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


Hs = {}
function Hs:new()
  return setmetatable({
    console = {
      clearConsole = function() end,
    },
    canvas = {
      new = function() end,
    },
    menubar = {
      new = function() return HsMenubar:new() end,
    },
    host = {
      cpuUsageTicks = function() return 0 end,
    },
    timer = {
      absoluteTime = function() return 0 end,
      doEvery = function(interval, handler) end,
    },
    axuielement = {
      applicationElement = function(app) return {
        HsAppElement:new(),
      } end,
    },
    hotkey = {
      bind = function(modifiers, hotkey, handler) end,
    },
    network = {
      ping = {
        echoRequest = function(addr) return HsEchoRequest:new(addr) end,
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
      new = function(event, handler) return HsEventtap:new(event, handler) end
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
