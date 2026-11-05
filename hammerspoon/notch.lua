-- The iTerm status line kind and progress time in two "ears" at the sides
-- of the notch, see specs/notch.spec.md
notch = {
  _kind = nil,
  _startSec = nil,
  -- {screen, left, right, height} for each screen with a notch
  _notches = {},
  -- {left, right} canvas pairs, one for each notch
  _ears = {},
  _timer = nil,
  _screenWatcher = nil,
}

local earWidth = 28
-- An ear extends this far under the notch: its inner corners are hidden
-- there, so it merges with the notch.
local underNotch = 10
-- Matches the notch's own bottom corners
local cornerRadius = 8
local icons = {progress = "⌛", success = "✅", error = "⚠️"}
-- Same timings as the window title, see specs/status.spec.md
local progressTickSec = 60
local resultExpirySec = 10 * 60

-- Hammerspoon has no API for the notch: the menu bar areas at its sides
-- are only in NSScreen.
local notchesScript = [[
ObjC.import("AppKit");
const result = [];
const screens = $.NSScreen.screens;
for (let i = 0; i < screens.count; i++) {
  const screen = screens.objectAtIndex(i);
  const left = screen.auxiliaryTopLeftArea;
  const right = screen.auxiliaryTopRightArea;
  if (left.size.width > 0 && right.size.width > 0) {
    result.push({
      x: screen.frame.origin.x,
      left: left.origin.x + left.size.width,
      right: right.origin.x,
      height: left.size.height,
    });
  }
}
JSON.stringify(result);
]]


function notch:_findNotches()
  self._notches = {}
  local ok, json = hs.osascript.javascript(notchesScript)
  if not ok then
    print("ERROR: failed to get the notch geometry")
    return
  end
  for _, area in ipairs(hs.json.decode(json)) do
    for _, screen in ipairs(hs.screen.allScreens()) do
      -- NSScreen and hs.screen share the x axis, but not the y one
      if screen:fullFrame().x == area.x then
        table.insert(self._notches, {
          screen = screen,
          left = area.left,
          right = area.right,
          height = area.height,
        })
      end
    end
  end
end


function notch:_openConsole()
  local iterm = hs.application.get("iTerm2")
  if not iterm then return end
  iterm:activate()
  iterm:selectMenuItem({"Scripts", "Manage", "Console"})
end


function notch:_newEar(frame, isLeft)
  local canvas = hs.canvas.new(frame)
  -- macOS moves a window of a lower level down out of the menu bar
  canvas:level(hs.canvas.windowLevels.mainMenu + 1)
  -- Fullscreen spaces are left out: those hide the menu bar
  canvas:behavior({"canJoinAllSpaces", "stationary"})
  -- Sticks out of the canvas at the top and on the notch side, so only the
  -- outer bottom corner is rounded
  canvas:appendElements({
    type = "rectangle",
    action = "fill",
    fillColor = {red = 0, green = 0, blue = 0},
    roundedRectRadii = {xRadius = cornerRadius, yRadius = cornerRadius},
    frame = {
      x = isLeft and 0 or -cornerRadius,
      y = -cornerRadius,
      w = frame.w + cornerRadius,
      h = frame.h + cornerRadius,
    },
  })
  canvas:appendElements({
    type = "text",
    text = "",
    frame = {
      x = isLeft and 0 or underNotch,
      y = 8,
      w = earWidth,
      h = frame.h,
    },
  })
  canvas:canvasMouseEvents(true)
  canvas:mouseCallback(function(_, message)
    if message == "mouseDown" then
      self:_openConsole()
    end
  end)
  canvas:show()
  return canvas
end


function notch:_deleteEars()
  for _, pair in ipairs(self._ears) do
    pair.left:delete()
    pair.right:delete()
  end
  self._ears = {}
end


function notch:_createEars()
  for _, area in ipairs(self._notches) do
    local y = area.screen:fullFrame().y
    local w = earWidth + underNotch
    table.insert(self._ears, {
      left = self:_newEar({
        x = area.left - earWidth,
        y = y,
        w = w,
        h = area.height,
      }, true),
      right = self:_newEar({
        x = area.right - underNotch,
        y = y,
        w = w,
        h = area.height,
      }, false),
    })
  end
end


-- The left and right ear texts and the seconds until they change, nil if
-- they don't; nothing while idle
function notch:_texts()
  if not self._kind then return nil end
  local age = hs.timer.secondsSinceEpoch() - self._startSec
  if self._kind == "progress" then
    if age < progressTickSec then
      return icons.progress, tostring(math.floor(age)), 1 - age % 1
    end
    -- Stays until the next status
    return icons.progress, ">1m", nil
  end
  if age < resultExpirySec then
    return icons[self._kind], "", resultExpirySec - age
  end
  self._kind = nil
  return nil
end


local function styled(text)
  return hs.styledtext.new(text, {
    font = {name = "Menlo", size = 12},
    color = {white = 1},
    paragraphStyle = {alignment = "center"},
  })
end


-- Sleeps until the texts change instead of ticking, to save battery
function notch:_render()
  if self._timer then
    self._timer:stop()
    self._timer = nil
  end
  local left, right, wait = self:_texts()
  if not left then
    self:_deleteEars()
    return
  end
  if #self._ears == 0 then
    self:_createEars()
  end
  for _, pair in ipairs(self._ears) do
    pair.left[2].text = styled(left)
    pair.right[2].text = styled(right)
  end
  if wait then
    self._timer = hs.timer.doAfter(wait, function()
      self:_render()
    end)
  end
end


-- "kind" is one of status.py kinds: progress, success or error
function notch:setStatus(kind)
  if not icons[kind] then
    return false
  end
  self._kind = kind
  self._startSec = hs.timer.secondsSinceEpoch()
  self:_render()
  return true
end


function notch:start()
  self:_findNotches()
  self._screenWatcher = hs.screen.watcher.new(function()
    self:_deleteEars()
    self:_findNotches()
    self:_render()
  end)
  self._screenWatcher:start()
end
