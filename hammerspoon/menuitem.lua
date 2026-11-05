menuitem = {}
-- Virtual pixels, fills retune by scaling to 48. One pixel less is not
-- a complete fit, while one pixel more cuts top and bottom parts.
local menuHeight = 24
-- Font height that approximately resembles default menubar font
local fontHeight = 13
-- Offset, in virtual pixels, from menubar top. Given menuHeight and
-- fontHeight this provides font position that resembles default one.
local fontTopOffset = 3
--- Maximum number of text objects cached
local maxCacheSize = 100
-- Same font as the drawn text. Without a color macOS picks the one it uses
-- for the menu bar, which follows the wallpaper and not the system theme.
local titleFont = {name = "Courier", size = fontHeight}


-- Elements of a ping or load graph with its top left corner at x, y, and
-- its width. The notch ears draw graphs too.
function menuitem.graphElements(graph_data, max_len, x, y, height)
  local width = max_len * 2 + 2
  local elements = {
    {
      type = "rectangle",
      frame = {x = x, y = y, w = width, h = height},
      fillColor = {red = 0, green = 0, blue = 0},
      action = "fill"
    },
    {
      type = "rectangle",
      frame = {x = x, y = y, w = width, h = height},
      strokeColor = {red = 0.5, green = 0.5, blue = 0.5},
      action = "stroke"
    },
  }
  for i = 1, #graph_data do
    local item = graph_data[i]
    local barHeight = item.val * (height - 2)
    if barHeight < 2 then barHeight = 2 end
    if barHeight > height - 2 then barHeight = height - 2 end
    table.insert(elements, {
      type = "rectangle",
      frame = {
        x = x + 1 + (i - 1) * 2,
        y = y + height - 1 - barHeight,
        w = 2,
        h = barHeight
      },
      fillColor = item.color,
      action = "fill"
    })
  end
  return elements, width
end


-- Changes the graph elements of the canvas in place, and only those that
-- changed: recreating them every second took a fifth of our CPU time.
-- "drawn" keeps what each element shows by index, the number of elements
-- in "count", and in "base" the number of the other elements before the
-- graph.
function menuitem.updateGraph(canvas, drawn, graph_data, max_len, x, y,
                              height)
  local elements = menuitem.graphElements(graph_data, max_len, x, y, height)
  for i, element in ipairs(elements) do
    local index = drawn.base + i
    local f = element.frame
    local color = element.fillColor or element.strokeColor
    local key = string.format("%g %g %g %g %s %s %s %s",
      f.x, f.y, f.w, f.h, color.red, color.green, color.blue, color.alpha)
    if index > drawn.count then
      canvas:appendElements(element)
      drawn.count = index
    elseif drawn[index] ~= key then
      canvas[index].frame = f
      canvas[index].fillColor = element.fillColor
    end
    drawn[index] = key
  end
  -- The history is shorter right after a start
  while drawn.count > drawn.base + #elements do
    canvas[drawn.count] = nil
    drawn[drawn.count] = nil
    drawn.count = drawn.count - 1
  end
end


function menuitem:new()
  local inst = {
    _widgets = {},
    _submenu = {},
    _canvas = hs.canvas.new({x = 0, y = 0, w = 1, h = menuHeight}),
    _item = hs.menubar.new(),
    -- Created after "_item" to be placed on its left. Its icon is a
    -- transparent placeholder: the graph is drawn over it by
    -- "_graphCanvas", whose bars change in place, while a new icon every
    -- second took half of our CPU time.
    _graphItem = hs.menubar.new(),
    _graph = nil,
    _graphCanvas = nil,
    -- See menuitem.updateGraph()
    _graphDrawn = {base = 0, count = 0},
    -- Created after "_graphItem" to be placed on its left
    _prefixItem = hs.menubar.new(),
    _prefix = nil,
    _shownPrefix = nil,
    _suffix = nil,
    _shownSuffix = nil,
    -- What the icon shows, so it is redrawn only on a change
    _iconKey = nil,
    _cache = {
      text = {
        objects = {},
        sizes = {}
      }
    }
  }
  self.__index = self
  -- An item with an empty title still takes space. Hidden and shown back,
  -- the item keeps its place.
  inst._prefixItem:removeFromMenuBar()
  inst._item:imagePosition(hs.menubar.imagePositions.imageLeft)
  return setmetatable(inst, self)
end


function menuitem:_setMenu()
  self._item:setMenu(self._submenu)
  self._graphItem:setMenu(self._submenu)
  self._prefixItem:setMenu(self._submenu)
end


function menuitem:clear()
  self._widgets = {}
  self._prefix = nil
  self._suffix = nil
end


-- Widgets drawn the same way give the same key; graphs and indicators
-- change too often to compare
function menuitem:_widgetsKey()
  local parts = {}
  for _, widget in ipairs(self._widgets) do
    if widget.type == "graph" or widget.type == "indicator" then
      return nil
    end
    table.insert(parts, widget.type .. " " .. (widget.text or "") .. " "
      .. widget.width)
  end
  return table.concat(parts, "\n")
end


function menuitem:update()
  local key = self:_widgetsKey()
  if not key or key ~= self._iconKey then
    self:_updateIcon()
    self._iconKey = key
  end
  if self._suffix ~= self._shownSuffix then
    local title = hs.styledtext.new(self._suffix or "", {font = titleFont})
    self._item:setTitle(title)
    self._shownSuffix = self._suffix
  end
  self:_updatePrefix()
  self:_updateGraph()
end


function menuitem:_updateIcon()
  while #self._canvas > 0 do
    self._canvas[#self._canvas] = nil
  end
  local curOffset = 0
  local totalWidth = 0
  for _, widget in ipairs(self._widgets) do

    if widget.type == "spacer" then
      curOffset = curOffset + widget.width
      totalWidth = totalWidth + widget.width

    elseif widget.type == "text" then
      self._canvas:insertElement({
        type = "text",
        frame = {
          x = curOffset,
          y = fontTopOffset,
          w = widget.width,
          h = menuHeight
        },
        text = widget.object
      })
      curOffset = curOffset + widget.width
      totalWidth = totalWidth + widget.width

    elseif widget.type == "graph" then
      local elements, width = menuitem.graphElements(
        widget.graph_data, widget.max_len, curOffset, 0, menuHeight)
      for _, element in ipairs(elements) do
        self._canvas:insertElement(element)
      end
      curOffset = curOffset + width
      totalWidth = totalWidth + width
    elseif widget.type == "indicator" then
      local width = 8
      self._canvas:insertElement({
        type = "rectangle",
        frame = {
          x = curOffset,
          y = 0,
          w = width,
          h = menuHeight
        },
        fillColor = {red = 0, green = 0, blue = 0},
        action = "fill"
      })
      self._canvas:insertElement({
        type = "rectangle",
        frame = {
          x = curOffset,
          y = 0,
          w = width,
          h = menuHeight
        },
        strokeColor = {red = 0.5, green = 0.5, blue = 0.5},
        action = "stroke"
      })
      yOffset = 0
      for _, indicator in ipairs(widget.info) do
        self._canvas:insertElement({
          type = "rectangle",
          frame = {
            x = curOffset + 2,
            y = yOffset + 2,
            w = 4,
            h = 3
          },
          fillColor = indicator.color,
          action = "fill"
        })
        yOffset = yOffset + 3 + 2
      end
      curOffset = curOffset + width
      totalWidth = totalWidth + width
    end
  end

  self._canvas:size({w = totalWidth, h = menuHeight})
  local isMonocolorTemplate = false
  self._item:setIcon(self._canvas:imageFromCanvas(), isMonocolorTemplate)
end


-- Keeps the graph over its placeholder, which moves as other items in the
-- menu bar appear and go
function menuitem:_updateGraph()
  if not self._graph then return end
  local frame = self._graphItem:frame()
  if not frame or frame.w == 0 then return end
  local width = self._graph.max_len * 2 + 2
  local x = frame.x + (frame.w - width) / 2
  local y = frame.y + (frame.h - menuHeight) / 2
  if not self._graphCanvas then
    self._graphCanvas = hs.canvas.new({
      x = x,
      y = y,
      w = width,
      h = menuHeight,
    })
    -- macOS moves a window of a lower level down out of the menu bar
    self._graphCanvas:level(hs.canvas.windowLevels.mainMenu + 1)
    self._graphCanvas:behavior({"canJoinAllSpaces", "stationary"})
    -- Without a mouse callback clicks go through to the item
    self._graphCanvas:show()
  else
    local cur = self._graphCanvas:frame()
    if cur.x ~= x or cur.y ~= y then
      self._graphCanvas:topLeft({x = x, y = y})
    end
  end
  menuitem.updateGraph(self._graphCanvas, self._graphDrawn,
    self._graph.data, self._graph.max_len, 0, 0, menuHeight)
end


function menuitem:_updatePrefix()
  if self._prefix == self._shownPrefix then
    return
  end
  if not self._prefix then
    self._prefixItem:removeFromMenuBar()
  else
    if not self._shownPrefix then
      self._prefixItem:returnToMenuBar()
    end
    local title = hs.styledtext.new(self._prefix, {font = titleFont})
    self._prefixItem:setTitle(title)
  end
  self._shownPrefix = self._prefix
end


-- Text is drawn by macOS in its menu bar text color, unlike widgets that are
-- drawn into an image. Prefix is shown as a separate item on the left, since
-- an item has a single title.
function menuitem:setPrefix(text)
  self._prefix = text
end


function menuitem:setSuffix(text)
  self._suffix = text
end


function menuitem:addText(text)
  self:addTextWithWidth(text, nil)
end


function menuitem:addTextWithWidth(text, width)
  styledText = self._cache.text.objects[text]
  if not styledText then
    if count(self._cache.text.objects) > maxCacheSize then
      self._cache.text.objects = {}
    end
    styledText = hs.styledtext.new(text, {
      font = {name = "Courier", size = fontHeight},
      color = {red = 1, green = 1, blue = 1}
    })
    self._cache.text.objects[text] = styledText
  end

  size = self._cache.text.sizes[text]
  if not size then
    if count(self._cache.text.sizes) > maxCacheSize then
      self._cache.text.sizes = {}
    end
    size = hs.drawing.getTextDrawingSize(styledText)
    self._cache.text.sizes[text] = size
  end

  if not width then
    width = math.ceil(size.w)
  end

  table.insert(self._widgets, {
    type = "text",
    text = text,
    object = styledText,
    width = width
  })
end


-- The graph in its own item, left of the widgets, see "_graphItem"
function menuitem:setGraph(graph_data, max_len)
  if not self._graph or self._graph.max_len ~= max_len then
    local placeholder = hs.canvas.new({
      x = 0,
      y = 0,
      w = max_len * 2 + 2,
      h = menuHeight,
    })
    self._graphItem:setIcon(placeholder:imageFromCanvas(), false)
    placeholder:delete()
  end
  self._graph = {data = graph_data, max_len = max_len}
end


function menuitem:addGraph(graph_data, max_len)
  table.insert(self._widgets, {
    type = "graph",
    graph_data = graph_data,
    max_len = max_len})
end


function menuitem:addIndicator(indicator)
  table.insert(self._widgets, {
    type = "indicator",
    info = indicator})
end


function menuitem:addSpacer(width)
  table.insert(self._widgets, {type = "spacer", width = width})
end


function menuitem:addSubmenuItem(title, fn, id)
  table.insert(self._submenu, {title = title, fn = fn, id = id})
  self:_setMenu()
end


function menuitem:setSubmenuItemTitle(id, title)
  for _, submenu in pairs(self._submenu) do
    if submenu.id == id then
      submenu.title = title
      break
    end
  end
  self:_setMenu()
end


function menuitem:setSubmenuItemEnabled(id, isEnabled)
  for _, submenu in pairs(self._submenu) do
    if submenu.id == id then
      submenu.disabled = not isEnabled
      break
    end
  end
  self:_setMenu()
end


function menuitem:addSubmenuSeparator()
  table.insert(self._submenu, {title = "-"})
  self:_setMenu()
end


function menuitem:addSubmenuCheckbox(title, checked, handler)
  table.insert(self._submenu, {
    title = title,
    checked=checked,
    fn = function(modifiers, item)
      item.checked = not item.checked
      self:_setMenu()
      handler(item.checked)
    end,
  })
  self:_setMenu()
end
