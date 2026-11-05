-- A strip of solid color under the transparent menu bar: macOS has no
-- setting for the menu bar background color. "Show menu bar background"
-- must be off: its material blurs the wallpaper only and hides the strip.
-- macOS picks the menu bar look from the wallpaper alone, so over a dark
-- one it dims the strip for its white text: white shows as light gray.
menubarbg = {
  _color = {red = 1.0, green = 1.0, blue = 1.0},
  _canvases = {},
  _frames = {},
  _screenWatcher = nil,
  _timer = nil,
}


function menubarbg:_redraw()
  for _, canvas in ipairs(self._canvases) do
    canvas:delete()
  end
  self._canvases = {}
  self._frames = {}
  for _, screen in ipairs(hs.screen.allScreens()) do
    local full = screen:fullFrame()
    -- Zero while the menu bar is set to hide automatically
    local height = screen:frame().y - full.y
    if height > 0 then
      local frame = {x = full.x, y = full.y, w = full.w, h = height}
      local canvas = hs.canvas.new(frame)
      -- The "desktop" level is below the wallpaper. Regular windows can't
      -- overlap the menu bar, so the strip covers nothing.
      canvas:level(hs.canvas.windowLevels.desktopIcon + 1)
      -- Without "canJoinAllSpaces" the strip stays on the first space;
      -- fullscreen spaces are left out since those hide the menu bar.
      canvas:behavior({"canJoinAllSpaces", "stationary"})
      canvas:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = self._color,
      })
      canvas:show()
      table.insert(self._canvases, canvas)
      table.insert(self._frames, frame)
    end
  end
end


-- Once the strip was seen moved down to the middle of the screen by
-- something outside of this code, so its position is checked periodically
function menubarbg:_restoreFrames()
  for i, canvas in ipairs(self._canvases) do
    local cur = canvas:frame()
    local want = self._frames[i]
    if cur.x ~= want.x or cur.y ~= want.y then
      canvas:topLeft({x = want.x, y = want.y})
    end
  end
end


function menubarbg:start()
  self:_redraw()
  self._screenWatcher = hs.screen.watcher.new(function()
    self:_redraw()
  end)
  self._screenWatcher:start()
  self._timer = hs.timer.doEvery(5, function()
    self:_restoreFrames()
  end)
end
