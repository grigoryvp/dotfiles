-- Two "ears" at the sides of the notch, see specs/notch.spec.md. Left: the
-- ping to the router and the time of the iTerm status line progress. Right:
-- the status kind icon and the ping to the internet.
notch = {
  _kind = nil,
  _startSec = nil,
  -- {screen, left, right, height} for each screen with a notch
  _notches = {},
  -- {left, right} canvas pairs, one for each notch
  _ears = {},
  -- Sides narrowed to a strip, since the active app's menus reach there
  _narrow = {left = false, right = false},
  -- The "_narrow" of each app by bundle ID: menus change with the app only
  _narrowByApp = {},
  -- Number of ping graph columns
  _graphLen = 0,
  _earWidth = 0,
  _timer = nil,
  _screenWatcher = nil,
  _appWatcher = nil,
}

-- An ear extends this far under the notch: its inner corners are hidden
-- there, so it merges with the notch.
local underNotch = 10
-- Matches the notch's own bottom corners
local cornerRadius = 8
-- Keeps the notch shape while the app menus need the room
local narrowWidth = cornerRadius
-- Fits ">1m" in the font below
local textWidth = 24
-- Keeps the graph off the rounded corner
local outerPad = 6
local gap = 4
local graphHeight = 20
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


-- X of the text and of the graph in an ear canvas. The text is next to the
-- notch: there is no status most of the time, and the empty part then
-- looks like the notch itself.
function notch:_layout(isLeft)
  local graphWidth = self._earWidth - outerPad - textWidth - gap * 2
  if isLeft then
    return outerPad + graphWidth + gap, outerPad
  end
  return underNotch + gap, underNotch + gap + textWidth + gap
end


-- Elements: 1 is the background, 2 the text, the rest the graph
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
  local textX = self:_layout(isLeft)
  canvas:appendElements({
    type = "text",
    text = "",
    frame = {x = textX, y = 8, w = textWidth, h = frame.h},
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
  local leftWidth = self._narrow.left and narrowWidth or self._earWidth
  local rightWidth = self._narrow.right and narrowWidth or self._earWidth
  for _, area in ipairs(self._notches) do
    local y = area.screen:fullFrame().y
    table.insert(self._ears, {
      left = self:_newEar({
        x = area.left - leftWidth,
        y = y,
        w = leftWidth + underNotch,
        h = area.height,
      }, true),
      right = self:_newEar({
        x = area.right - underNotch,
        y = y,
        w = rightWidth + underNotch,
        h = area.height,
      }, false),
    })
  end
end


-- Which ears the menu bar items of the app overlap. The app menus fill the
-- menu bar from the left, and macOS moves those that don't fit to the right
-- of the notch, but doesn't know about the ears.
function notch:_menuOverlap(app)
  local result = {left = false, right = false}
  local appElement = hs.axuielement.applicationElement(app)
  local menuBar = appElement and appElement:attributeValue("AXMenuBar")
  if not menuBar then return result end
  for _, item in ipairs(menuBar:attributeValue("AXChildren") or {}) do
    local f = item:attributeValue("AXFrame")
    for _, area in ipairs(self._notches) do
      local top = area.screen:fullFrame().y
      if f and f.y < top + area.height then
        local right = f.x + f.w
        if f.x < area.left and right > area.left - self._earWidth then
          result.left = true
        end
        if right > area.right and f.x < area.right + self._earWidth then
          result.right = true
        end
      end
    end
  end
  return result
end


-- Checked on app activation instead of polling: an app rarely changes its
-- menus while active, and the result is cached by app.
function notch:_checkMenus(app)
  if not app then return end
  local bundleID = app:bundleID()
  local narrow = bundleID and self._narrowByApp[bundleID]
  if not narrow then
    narrow = self:_menuOverlap(app)
    if bundleID then
      self._narrowByApp[bundleID] = narrow
    end
  end
  local same = narrow.left == self._narrow.left
    and narrow.right == self._narrow.right
  if same then return end
  self._narrow = narrow
  self:_deleteEars()
  self:_render()
end


-- The status icon, its time and the seconds until they change, nil if they
-- don't; nothing while idle
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
  local icon, time, wait = self:_texts()
  if #self._ears == 0 then
    self:_createEars()
  end
  -- Idle ears stay, empty, as do narrowed ones
  if self._narrow.left then time = nil end
  if self._narrow.right then icon = nil end
  for _, pair in ipairs(self._ears) do
    pair.left[2].text = styled(time or "")
    pair.right[2].text = styled(icon or "")
  end
  if wait then
    self._timer = hs.timer.doAfter(wait, function()
      self:_render()
    end)
  end
end


local function setGraph(canvas, graphData, x, graphLen)
  while #canvas > 2 do
    canvas[#canvas] = nil
  end
  local y = (canvas:frame().h - graphHeight) / 2
  local elements = menuitem.graphElements(
    graphData, graphLen, x, y, graphHeight)
  canvas:appendElements(elements)
end


-- Called on every heartbeat with menuitem graphs
function notch:setGraphs(routerGraph, inetGraph)
  local _, leftGraphX = self:_layout(true)
  local _, rightGraphX = self:_layout(false)
  for _, pair in ipairs(self._ears) do
    if not self._narrow.left then
      setGraph(pair.left, routerGraph, leftGraphX, self._graphLen)
    end
    if not self._narrow.right then
      setGraph(pair.right, inetGraph, rightGraphX, self._graphLen)
    end
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


-- "graphLen" is the number of ping graph columns
function notch:start(graphLen)
  self._graphLen = graphLen
  local graphWidth = graphLen * 2 + 2
  self._earWidth = outerPad + textWidth + gap + graphWidth + gap
  self:_findNotches()
  self:_render()
  self:_checkMenus(hs.application.frontmostApplication())
  self._screenWatcher = hs.screen.watcher.new(function()
    self:_deleteEars()
    self:_findNotches()
    -- The overlaps depend on the notch position
    self._narrowByApp = {}
    self:_render()
    self:_checkMenus(hs.application.frontmostApplication())
  end)
  self._screenWatcher:start()
  self._appWatcher = hs.application.watcher.new(function(_, event, app)
    if event == hs.application.watcher.activated then
      self:_checkMenus(app)
    end
  end)
  self._appWatcher:start()
end
