-- See ./.vscode/settings.json for linter configuration

function onReadlinkExit(exitCode, stdOut, _)
  if exitCode ~= 0 or not stdOut then
    return print("ERROR: init.lua is not a link within ~/.hammerspoon")
  end
  local srcDir = stdOut:match("(.+/)") or "./"
  -- init.lua is linked, rest of the files are in the original dir
  package.path = package.path .. ";" .. srcDir .. "?.lua"
  require "main"

  app = App:new()
  app:registerHotkeys()
  app:registerMouse()
  app:loadSettings()
  app:createMenu()
  app:restartInetPingInt()
  app:restartInetPingExt()
  app:startHeartbeat()
  app:startHttpServer()
end

srcFile = debug.getinfo(1).source:match("@?(.*)")
task = hs.task.new("/usr/bin/readlink", onReadlinkExit, {srcFile})
task:start()
