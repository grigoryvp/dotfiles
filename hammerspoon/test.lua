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
      applicationElement = function(app) return {nil} end,
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
