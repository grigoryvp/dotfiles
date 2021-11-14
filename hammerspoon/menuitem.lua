menuitem = {}
-- Virtual pixels, fills retune by scaling to 48. One pixel less is not
-- a complete fit, while one pixel more cuts top and bottom parts.
local menuHeight = 24
-- Font height that approximately resembles default menubar font
local fontHeight = 13
-- Offset, in virtual pixels, from menubar top. Given menuHeight and
-- fontHeight this provides font position that resembles default one.
local fontTopOffset = 3


function menuitem:new()
  local inst = {
    _widgets = {},
    _submenu = {},
    _canvas = hs.canvas.new({x = 0, y = 0, w = 1, h = menuHeight}),
    _item = hs.menubar.new()
  }
  self.__index = self
  return setmetatable(inst, self)
end


function menuitem:clear()
  self._widgets = {}
  while #self._canvas > 0 do
    self._canvas[#self._canvas] = nil
  end
end


function menuitem:update()
  local curOffset = 0
  local totalWidth = 0
  for _, widget in ipairs(self._widgets) do

    if widget.type == "spacer" then
      curOffset = curOffset + widget.width
      totalWidth = totalWidth + widget.width

    elseif widget.type == "text" then
      -- Approximation for a known fixed-width font with known height
      local width = #widget.text * 8
      self._canvas:insertElement({
        type = "text",
        frame = {
          x = curOffset,
          y = fontTopOffset,
          w = width,
          h = menuHeight
        },
        text = hs.styledtext.new(widget.text, {
          font = {name = "Courier", size = fontHeight},
          color = {red = 1, green = 1, blue = 1}
        })
      })
      curOffset = curOffset + width
      totalWidth = totalWidth + width

    elseif widget.type == "graph" then
      local width = widget.max_len * 2 + 2
      self._canvas:insertElement({
        type = "rectangle",
        frame = {
          x = curOffset,
          y = 0,
          w = width,
          h = menuHeight
        },
        strokeColor = {red = 1, green = 1, blue = 1},
        action = "stroke"
      })
      for i = 1, #widget.graph_data do
        local item = widget.graph_data[i]
        local height = item.val * (menuHeight - 2)
        if height < 2 then height = 2 end
        if height > menuHeight - 2 then height = menuHeight - 2 end
        self._canvas:insertElement({
          type = "rectangle",
          frame = {
            x = curOffset + 1 + (i - 1) * 2,
            y = menuHeight - 1 - height,
            w = 2,
            h = height
          },
          fillColor = item.color,
          action = "fill"
        })
      end
      curOffset = curOffset + width
      totalWidth = totalWidth + width
    end
  end

  self._canvas:size({w = totalWidth, h = menuHeight})
  local isMonocolorTemplate = false
  self._item:setIcon(self._canvas:imageFromCanvas(), isMonocolorTemplate)
end


function menuitem:addText(text)
  table.insert(self._widgets, {type = "text", text = text})
end


function menuitem:addGraph(graph_data, max_len)
  table.insert(self._widgets, {
    type = "graph",
    graph_data = graph_data,
    max_len = max_len})
end


function menuitem:addSpacer(width)
  table.insert(self._widgets, {type = "spacer", width = width})
end


function menuitem:addSubmenuItem(title, fn)
  table.insert(self._submenu, {title = title, fn = fn})
  self._item:setMenu(self._submenu)
end


function menuitem:addSubmenuSeparator()
  table.insert(self._submenu, {title = "-"})
  self._item:setMenu(self._submenu)
end


function menuitem:addSubmenuCheckbox(title, checked, handler)
  table.insert(self._submenu, {
    title = title,
    checked=checked,
    fn = function(modifiers, item)
      item.checked = not item.checked
      handler(item.checked)
    end,
  })
  self._item:setMenu(self._submenu)
end
