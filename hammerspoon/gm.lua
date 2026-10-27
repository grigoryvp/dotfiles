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


-- Written by iterm/Scripts/AutoLaunch/gm.py, read here and by
-- wox/plugins/single-file/gm.py
gm.CACHE_PATH = os.getenv("HOME") .. "/.cache/grigoryvp-gm/projects.json"


function gm:_projectChoices()
  local cache = hs.json.read(self.CACHE_PATH)
  if not cache then
    return {{text = "No projects", subText = "Missing " .. self.CACHE_PATH}}
  end
  local choices = {}
  for _, project in ipairs(cache.projects) do
    table.insert(choices, {text = project.path, subText = project.host})
  end
  return choices
end


function gm:showNew()
  -- Choosers are never freed, see App:showSymbolPicker
  if not self._newChooser then
    self._newChooser = hs.chooser.new(function() end)
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
  -- Re-read on each show since the iTerm script refreshes the cache
  self._newChooser:choices(self:_projectChoices())
  self._newChooser:query("")
  self._newShown = true
  self._newChooser:show()
end
