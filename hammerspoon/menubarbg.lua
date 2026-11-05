-- A strip of solid color under the transparent menu bar: macOS has no
-- setting for the menu bar background color. "Show menu bar background"
-- must be off: its material blurs the wallpaper only and hides the strip.
-- macOS picks the menu bar look from the wallpaper alone, so over a dark
-- one it dims the strip for its white text: white shows as light gray.
menubarbg = {
  -- Measured to show as #152535 after macOS shading, like VSCode panels
  _color = {hex = "#101C28"},
  _canvases = {},
  _frames = {},
  _screenWatcher = nil,
  _timer = nil,
}

-- While a window of these apps is close to the menu bar, macOS draws an
-- opaque menu bar background over the strip, black with a black wallpaper.
-- Windows of other apps may touch the menu bar. 30 pt is the breakpoint
-- found by trying: with a smaller gap the menu bar turns black.
local gapApps = {ChatGPT = true, Claude = true}
local gap = 30


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
      -- The "desktop" level is below the wallpaper. One above "desktopIcon"
      -- is a Window Server window under the menu bar, once seen ordered
      -- over the strip. Regular windows can't overlap the menu bar, so the
      -- strip covers nothing.
      canvas:level(hs.canvas.windowLevels.desktopIcon + 2)
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


-- The frame with its top moved down to the gap, keeping the bottom in place.
-- Applied by our window hotkeys only: the apps still place their windows
-- under the menu bar on launch.
function menubarbg:frameWithGap(wnd, frame)
  if not gapApps[wnd:application():name()] then return frame end
  local topLeft = hs.geometry.point(frame.x, frame.y)
  for _, screen in ipairs(hs.screen.allScreens()) do
    local full = screen:fullFrame()
    local menuBottom = screen:frame().y
    if topLeft:inside(full) and menuBottom > full.y then
      local minY = menuBottom + gap
      if frame.y < minY then
        local h = frame.y + frame.h - minY
        return {x = frame.x, y = minY, w = frame.w, h = h}
      end
    end
  end
  return frame
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
