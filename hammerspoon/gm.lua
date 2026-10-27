-- Git Manager UI, shown on requests from iterm/Scripts/AutoLaunch/gm.py

gm = {
  _newChooser = nil,
  _newShown = false
}


-- Calls an RPC registered by iterm/Scripts/AutoLaunch/gm.py. A task, since
-- osascript would block the main thread on the first automation prompt.
function gm:_invokeIterm(expression)
  local script = 'tell application id "com.googlecode.iterm2" to ' ..
    'invoke API expression "' .. expression .. '"'
  local task = hs.task.new("/usr/bin/osascript", function(exitCode, _, stdErr)
    if exitCode ~= 0 then
      print("ERROR: gm " .. expression .. ": " .. stdErr)
    end
  end, {"-e", script})
  task:start()
end


-- Stub for the project picker that only proves the Wox -> iTerm ->
-- Hammerspoon -> iTerm chain works
function gm:showNew()
  -- Choosers are never freed, see App:showSymbolPicker
  if not self._newChooser then
    self._newChooser = hs.chooser.new(function() end)
    self._newChooser:choices({
      {text = "gm new", subText = "Wox -> iTerm -> Hammerspoon chain works"}
    })
    -- Called on selection, cancel and programmatic hide alike, and twice
    -- per hide, so only the first call after show() counts
    self._newChooser:hideCallback(function()
      if not self._newShown then
        return
      end
      self._newShown = false
      self:_invokeIterm("gm_new_done()")
    end)
  end
  self._newShown = true
  self._newChooser:show()
end
