-- TODO: change ICMP to TCP since ICMP works while TCP may fail with
--       the "no buffer space available" error.
-- See ./.vscode/settings.json for linter configuration

-- "hs" cli tool for remote communication
require "hs.ipc"

-- Doesn't seem to work
hs.window.animationDuration = 0

function onReadlinkExit(exitCode, stdOut, _)
  if exitCode ~= 0 or not stdOut then
    return print("ERROR: init.lua is not a link within ~/.hammerspoon")
  end
  local srcDir = stdOut:match("(.+/)") or "./"
  -- init.lua is linked, rest of the files are in the original dir
  package.path = package.path .. ";" .. srcDir .. "?.lua"

  require "helpers"
  require "netstat"
  require "elgato"
  require "menuitem"
  require "main"

  app = App:new()
  app:setSrcDir(srcDir)
  app:registerMouse()
  app:loadSettings()
  app:loadSymbols()
  app:createMenu()
  app:restartInetPingInt()
  app:restartInetPingExt()
  app:startHeartbeat()
  app:startHttpServer()
  app:startApplicationWatcher()
end

srcFile = debug.getinfo(1).source:match("@?(.*)")
task = hs.task.new("/usr/bin/readlink", onReadlinkExit, {srcFile})
task:start()
