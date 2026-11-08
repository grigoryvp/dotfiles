-- Usage of the AI subscriptions in the menu bar: a logo and two bars for
-- each, the 5-hour window on the left and the weekly one on the right. See
-- specs/usage.spec.md.
usage = {
  _item = nil,
  _canvas = nil,
  -- Logo images by provider name
  _logos = {},
  -- The last fetch of each provider by name: {result, fetchedAt, err,
  -- backoff, nextAt}
  _states = {},
  _timers = {},
  _inflight = {},
  _renderKey = nil,
  _width = nil,
  _renderTimer = nil,
  _wakeWatcher = nil,
  -- Providers with an agent working now, by name
  _busy = {},
  _sessionsWatcher = nil,
  _lastRefresh = 0,
}

-- Same as the CPU graph of menuitem.lua
local menuHeight = 24
local barWidth = 4
-- Between logos and bars, and to the icons of the neighbor items
local gap = 8
-- macOS pads an item icon on each side, the neighbor icons are then twice
-- as far
local itemPadding = 8
-- Values older than this many poll intervals are drawn gray
local staleIntervals = 3
local maxBackoffSec = 60 * 60
local taskTimeoutSec = 20
local wakeDebounceSec = 60
local codexTailBytes = 64 * 1024
local grayColor = {hex = "#808080"}
-- FOREGROUND of iterm/Scripts/AutoLaunch/settings.py
local busyColor = {hex = "#E6AC73"}
local claudeSessionsDir = os.getenv("HOME") .. "/.claude/sessions"

local function decode(text)
  if type(text) ~= "string" or text == "" then return nil end
  local ok, data = pcall(hs.json.decode, text)
  if ok and type(data) == "table" then return data end
  return nil
end


local function readJson(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("a")
  file:close()
  return decode(text)
end


-- Days since the epoch of a date in the proleptic Gregorian calendar
local function daysFromCivil(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = y // 400
  local yoe = y - era * 400
  local mp = m > 2 and m - 3 or m + 9
  local doy = (153 * mp + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end


-- Seconds since the epoch of an ISO 8601 time: os.time() would take it as
-- a local one
local function isoTime(text)
  if type(text) ~= "string" then return nil end
  local y, mo, d, h, mi, s, zone = text:match(
    "^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)%.?%d*(.*)$")
  if not y then return nil end
  local time = daysFromCivil(tonumber(y), tonumber(mo), tonumber(d)) * 86400
    + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(s)
  local sign, oh, om = zone:match("^([+-])(%d%d):?(%d%d)$")
  if sign then
    local offset = (tonumber(oh) * 60 + tonumber(om)) * 60
    time = sign == "+" and time - offset or time + offset
  end
  return time
end


local function window(percent, resetsAt)
  if type(percent) ~= "number" then return nil end
  return {percent = percent, resetsAt = resetsAt}
end


local function retryAfter(headers)
  for name, value in pairs(headers or {}) do
    if name:lower() == "retry-after" then return tonumber(value) or 0 end
  end
  return 0
end


-- Calls back with the exit code and the output, killing a hung command
local function run(path, args, callback)
  local watchdog = nil
  local task = hs.task.new(path, function(code, out)
    if watchdog then watchdog:stop() end
    callback(code, out)
  end, args)
  if not task or not task:start() then
    return callback(-1, "")
  end
  watchdog = hs.timer.doAfter(taskTimeoutSec, function()
    if task:isRunning() then task:terminate() end
  end)
end


-- Passes a parsed 200 response to "parse", anything else to "done" as an
-- error. 429 also gives the delay to back off.
local function onHttp(done, parse)
  return function(status, body, headers)
    if status == 429 then
      return done(nil, "HTTP 429", retryAfter(headers))
    elseif status < 0 then
      return done(nil, "no connection")
    elseif status ~= 200 then
      return done(nil, "HTTP " .. status)
    end
    local data = decode(body)
    if not data then return done(nil, "bad response") end
    parse(data)
  end
end


local function parseClaude(data)
  local result = {extra = {}}
  for _, limit in ipairs(type(data.limits) == "table" and data.limits or {}) do
    local w = window(limit.percent, isoTime(limit.resets_at))
    if w and limit.kind == "session" then
      result.five = w
    elseif w and limit.kind == "weekly_all" then
      result.week = w
    elseif w and limit.kind == "weekly_scoped" then
      local scope = type(limit.scope) == "table" and limit.scope or {}
      local model = type(scope.model) == "table" and scope.model or {}
      w.label = "week " .. (model.display_name or "model")
      table.insert(result.extra, w)
    end
  end
  -- The older fields, in case "limits" goes away
  for key, field in pairs({five = "five_hour", week = "seven_day"}) do
    local old = data[field]
    if not result[key] and type(old) == "table" then
      result[key] = window(old.utilization, isoTime(old.resets_at))
    end
  end
  return result
end


-- Same endpoint as the /usage command of Claude Code, with its token
local function fetchClaude(done)
  local args = {"find-generic-password", "-s", "Claude Code-credentials",
    "-w"}
  run("/usr/bin/security", args, function(code, out)
    local creds = code == 0 and decode(out)
    local oauth = creds and creds.claudeAiOauth
    if type(oauth) ~= "table" or not oauth.accessToken then
      return done(nil, "no credentials")
    end
    -- Only Claude Code refreshes the token: the refresh token is single-use,
    -- so a refresh here would log Claude Code out
    if type(oauth.expiresAt) == "number"
        and oauth.expiresAt / 1000 < os.time() then
      return done(nil, "token expired, run Claude Code")
    end
    local headers = {
      Authorization = "Bearer " .. oauth.accessToken,
      ["anthropic-beta"] = "oauth-2025-04-20",
      Accept = "application/json",
    }
    hs.http.asyncGet("https://api.anthropic.com/api/oauth/usage", headers,
      onHttp(done, function(data) done(parseClaude(data)) end))
  end)
end


-- Claude Code keeps a status file for each running session, named by its PID
local function busyClaudePids()
  local pids = {}
  if hs.fs.attributes(claudeSessionsDir, "mode") ~= "directory" then
    return pids
  end
  for file in hs.fs.dir(claudeSessionsDir) do
    local pid = file:match("^(%d+)%.json$")
    local data = pid and readJson(claudeSessionsDir .. "/" .. file)
    if data and data.status == "busy" then table.insert(pids, pid) end
  end
  return pids
end


-- The newest session log of Codex, from today or yesterday
local function newestCodexRollout()
  local newest, newestTime = nil, nil
  for _, daysAgo in ipairs({0, 1}) do
    local dir = os.getenv("HOME") .. "/.codex/sessions/"
      .. os.date("%Y/%m/%d", os.time() - daysAgo * 86400)
    if hs.fs.attributes(dir, "mode") == "directory" then
      for file in hs.fs.dir(dir) do
        if file:match("^rollout%-.*%.jsonl$") then
          local path = dir .. "/" .. file
          local time = hs.fs.attributes(path, "modification")
          if time and (not newestTime or time > newestTime) then
            newest, newestTime = path, time
          end
        end
      end
    end
  end
  return newest, newestTime
end


-- Codex logs the limits after each turn, so they are as old as the last
-- turn
local function codexFromRollout()
  local path, time = newestCodexRollout()
  local file = path and io.open(path, "r")
  if not file then return nil end
  local size = file:seek("end")
  file:seek("set", math.max(0, size - codexTailBytes))
  local tail = file:read("a")
  file:close()
  local line = nil
  for text in tail:gmatch("[^\n]+") do
    if text:find('"rate_limits"', 1, true) then line = text end
  end
  local data = decode(line)
  local payload = data and type(data.payload) == "table" and data.payload
  local limits = payload and type(payload.rate_limits) == "table"
    and payload.rate_limits
  if not limits then return nil end
  local function get(name)
    local w = type(limits[name]) == "table" and limits[name] or {}
    return window(w.used_percent, w.resets_at)
  end
  return {five = get("primary"), week = get("secondary"), fetchedAt = time,
    extra = {}}
end


-- Same endpoint as the /status command of Codex, with its token. Falls back
-- to the session log.
local function fetchCodex(done)
  local fail = function(_, err, delay)
    local result = codexFromRollout()
    done(result, result and err .. ", from the session log" or err, delay)
  end
  local auth = readJson(os.getenv("HOME") .. "/.codex/auth.json")
  local tokens = auth and type(auth.tokens) == "table" and auth.tokens
  if not tokens or not tokens.access_token then
    return fail(nil, "no credentials")
  end
  local headers = {
    Authorization = "Bearer " .. tokens.access_token,
    ["ChatGPT-Account-Id"] = tokens.account_id,
    ["User-Agent"] = "hammerspoon",
  }
  hs.http.asyncGet("https://chatgpt.com/backend-api/wham/usage", headers,
    onHttp(fail, function(data)
      local limit = type(data.rate_limit) == "table" and data.rate_limit or {}
      local function get(name)
        local w = type(limit[name]) == "table" and limit[name] or {}
        return window(w.used_percent, w.reset_at)
      end
      done({five = get("primary_window"), week = get("secondary_window"),
        extra = {}})
    end))
end


local function agyPath()
  for _, path in ipairs({"/opt/homebrew/bin/agy", "/usr/local/bin/agy"}) do
    if hs.fs.attributes(path, "mode") then return path end
  end
  return nil
end


local function worse(a, b)
  if not a then return b end
  if not b then return a end
  return b.percent > a.percent and b or a
end


-- Quotas are per group of models: each bar shows the worst group, the menu
-- shows all of them
local function parseAntigravity(data)
  local command = type(data.command) == "table" and data.command or {}
  local commandData = type(command.data) == "table" and command.data or {}
  local groups = type(commandData.groups) == "table" and commandData.groups
    or {}
  -- The groups in the menu already show what the bars do
  local result = {extra = {}, extraOnly = true}
  for _, group in ipairs(groups) do
    local buckets = type(group.buckets) == "table" and group.buckets or {}
    for _, bucket in ipairs(buckets) do
      if type(bucket.remaining_fraction) == "number" then
        local w = window(
          math.max(0, (1 - bucket.remaining_fraction) * 100),
          isoTime(bucket.reset_time))
        w.label = (group.name or "?") .. " " .. (bucket.window or "?")
        table.insert(result.extra, w)
        if bucket.window == "weekly" then
          result.week = worse(result.week, w)
        else
          result.five = worse(result.five, w)
        end
      end
    end
  end
  return result
end


-- The print mode of the CLI answers /usage without an agent turn and exits:
-- unlike the IDE language server, nothing is left running
local function fetchAntigravity(done)
  local path = agyPath()
  if not path then return done(nil, "agy not found") end
  local args = {"-p", "/usage", "--output-format", "json", "--log-file",
    "/dev/null"}
  run(path, args, function(code, out)
    local data = decode(out)
    if code ~= 0 or not data or data.status ~= "SUCCESS" then
      return done(nil, "agy failed, exit code " .. code)
    end
    done(parseAntigravity(data))
  end)
end


local providers = {
  {
    name = "claude",
    title = "Claude",
    logo = {file = "usage-claude.svg", w = 18, h = 12},
    interval = 10 * 60,
    url = "https://claude.ai/settings/usage",
    fetch = fetchClaude,
  },
  {
    name = "codex",
    title = "Codex",
    logo = {file = "usage-openai.svg", w = 16, h = 16},
    interval = 5 * 60,
    url = "https://chatgpt.com/codex/settings/usage",
    fetch = fetchCodex,
  },
  {
    name = "antigravity",
    title = "Antigravity",
    logo = {file = "usage-gemini.svg", w = 16, h = 16},
    interval = 15 * 60,
    fetch = fetchAntigravity,
  },
}


local function percentAt(w, now)
  if not w then return nil end
  if w.resetsAt and w.resetsAt <= now then return 0 end
  return w.percent
end


local function barColor(percent)
  if percent < 30 then
    return {hex = "#32D74B"}
  elseif percent < 80 then
    return {hex = "#FF9F0A"}
  end
  return {hex = "#FF453A"}
end


function usage:_isStale(provider, now)
  local state = self._states[provider.name]
  return not state or not state.fetchedAt
    or now - state.fetchedAt > staleIntervals * provider.interval
end


-- What the bars of a provider show: {percent, color} for each window
function usage:_bars(provider, now)
  local state = self._states[provider.name]
  local result = state and state.result or {}
  local stale = self:_isStale(provider, now)
  local windows = {result.five, result.week}
  local bars = {}
  for i = 1, 2 do
    local percent = percentAt(windows[i], now)
    if percent then
      percent = math.floor(percent + 0.5)
      bars[i] = {
        percent = percent,
        color = stale and grayColor or barColor(percent),
      }
    end
  end
  return bars, stale
end


function usage:_elements(now)
  local elements = {}
  local x = 0
  for i, provider in ipairs(providers) do
    if i > 1 then x = x + gap end
    local bars, stale = self:_bars(provider, now)
    local logo = provider.logo
    if self._logos[provider.name] then
      local logoFrame = {x = x, y = (menuHeight - logo.h) / 2, w = logo.w,
        h = logo.h}
      table.insert(elements, {
        type = "image",
        image = self._logos[provider.name],
        frame = logoFrame,
        imageAlpha = stale and 0.4 or 1,
        imageScaling = "scaleProportionally",
      })
      if self._busy[provider.name] then
        -- Colors only the pixels of the logo, keeping their alpha
        table.insert(elements, {
          type = "rectangle",
          frame = logoFrame,
          fillColor = busyColor,
          compositeRule = "sourceAtop",
          action = "fill",
        })
      end
    end
    x = x + logo.w + gap
    local frame = {x = x, y = 0, w = barWidth * 2 + 3, h = menuHeight}
    table.insert(elements, {
      type = "rectangle",
      frame = frame,
      fillColor = {red = 0, green = 0, blue = 0},
      action = "fill",
    })
    table.insert(elements, {
      type = "rectangle",
      frame = frame,
      strokeColor = grayColor,
      action = "stroke",
    })
    -- Divides the 5-hour bar from the weekly one
    table.insert(elements, {
      type = "rectangle",
      frame = {x = x + 1 + barWidth, y = 0, w = 1, h = menuHeight},
      fillColor = {hex = "#404040"},
      action = "fill",
    })
    for j = 1, 2 do
      local bar = bars[j]
      if bar then
        local height = math.min(menuHeight - 2,
          math.max(2, bar.percent / 100 * (menuHeight - 2)))
        table.insert(elements, {
          type = "rectangle",
          frame = {
            x = x + 1 + (j - 1) * (barWidth + 1),
            y = menuHeight - 1 - height,
            w = barWidth,
            h = height,
          },
          fillColor = bar.color,
          action = "fill",
        })
      end
    end
    x = x + frame.w
  end
  return elements, x
end


-- Redraws the icon only when it changes: the values change every few
-- minutes, while this runs every minute to gray out old values
function usage:_render()
  local now = os.time()
  local parts = {}
  for _, provider in ipairs(providers) do
    local bars, stale = self:_bars(provider, now)
    for i = 1, 2 do
      local bar = bars[i]
      table.insert(parts, bar and bar.percent .. bar.color.hex or "-")
    end
    table.insert(parts, tostring(stale))
    table.insert(parts, tostring(self._busy[provider.name]))
  end
  local key = table.concat(parts, " ")
  if key == self._renderKey then return end
  self._renderKey = key
  local elements, width = self:_elements(now)
  self._canvas:replaceElements(elements)
  if width ~= self._width then
    self._width = width
    -- Narrower than the drawing by the item padding, so the canvas covers
    -- it and the neighbors are only their own padding away
    local placeholder = hs.canvas.new({
      x = 0,
      y = 0,
      w = width - itemPadding * 2,
      h = menuHeight,
    })
    self._item:setIcon(placeholder:imageFromCanvas(), false)
    placeholder:delete()
    self:place()
  end
end


-- Keeps the canvas over the item, which moves as other items in the menu
-- bar appear and go. Called by the menu update of main.lua every second:
-- a timer of its own costs more CPU.
function usage:place()
  if not self._width then return end
  local frame = menuitem.itemFrame(self._item)
  if not frame or frame.w == 0 then
    self._canvas:hide()
    return
  end
  local x = frame.x + (frame.w - self._width) / 2
  local y = frame.y + (frame.h - menuHeight) / 2
  local cur = self._canvas:frame()
  if cur.x ~= x or cur.y ~= y or cur.w ~= self._width then
    self._canvas:frame({x = x, y = y, w = self._width, h = menuHeight})
  end
  menuitem.showUnlessFullscreen(self._canvas)
end


local function formatDuration(sec)
  if sec >= 86400 then
    return ("%dd%dh"):format(sec // 86400, sec % 86400 // 3600)
  elseif sec >= 3600 then
    return ("%dh%02dm"):format(sec // 3600, sec % 3600 // 60)
  end
  return ("%dm"):format(sec // 60)
end


local function formatWindow(label, w, now)
  local percent = percentAt(w, now)
  local text = ("%s %d%%"):format(label, math.floor(percent + 0.5))
  if w.resetsAt and w.resetsAt > now then
    local format = w.resetsAt - now < 86400 and "%H:%M" or "%a %H:%M"
    text = text .. ", resets " .. os.date(format, w.resetsAt)
      .. " (in " .. formatDuration(w.resetsAt - now) .. ")"
  end
  return text
end


function usage:_menu()
  local now = os.time()
  local menu = {}
  for _, provider in ipairs(providers) do
    local state = self._states[provider.name] or {}
    local result = state.result or {}
    table.insert(menu, {
      title = provider.title,
      fn = provider.url and function() hs.urlevent.openURL(provider.url) end,
      disabled = not provider.url,
    })
    local lines = {}
    if result.five and not result.extraOnly then
      table.insert(lines, formatWindow("5h", result.five, now))
    end
    if result.week and not result.extraOnly then
      table.insert(lines, formatWindow("week", result.week, now))
    end
    for _, w in ipairs(result.extra or {}) do
      table.insert(lines, formatWindow(w.label, w, now))
    end
    if state.fetchedAt then
      table.insert(lines, ("updated %s ago"):format(
        formatDuration(math.max(0, now - state.fetchedAt))))
    end
    if state.err then
      local err = state.err
      if state.backoff and state.nextAt then
        err = err .. ", retry at " .. os.date("%H:%M", state.nextAt)
      end
      table.insert(lines, err)
    end
    if not state.fetchedAt and not state.err then
      table.insert(lines, "loading")
    end
    for _, line in ipairs(lines) do
      table.insert(menu, {title = line, indent = 1, disabled = true})
    end
    table.insert(menu, {title = "-"})
  end
  table.insert(menu, {title = "Refresh now", fn = function()
    self:refresh()
  end})
  return menu
end


function usage:_schedule(provider, delay)
  if self._timers[provider.name] then
    self._timers[provider.name]:stop()
  end
  self._states[provider.name].nextAt = os.time() + delay
  self._timers[provider.name] = hs.timer.doAfter(delay, function()
    self:_poll(provider)
  end)
end


-- "done" gets the result, or an error, or both when the result is a
-- fallback, and the delay to back off after a rate limit
function usage:_poll(provider)
  if self._inflight[provider.name] then return end
  self._inflight[provider.name] = true
  provider.fetch(function(result, err, backoff)
    self._inflight[provider.name] = false
    local state = self._states[provider.name] or {}
    self._states[provider.name] = state
    state.err = err
    local fetchedAt = result and (result.fetchedAt or os.time())
    -- A fallback may be older than what is shown
    if fetchedAt and fetchedAt >= (state.fetchedAt or 0) then
      state.result = result
      state.fetchedAt = fetchedAt
    end
    local delay = provider.interval
    if backoff then
      state.backoff = math.min(maxBackoffSec,
        math.max(backoff, (state.backoff or provider.interval / 2) * 2))
      delay = state.backoff
    else
      state.backoff = nil
    end
    if err then
      print("usage: " .. provider.name .. ": " .. err)
    end
    self:_schedule(provider, delay)
    self:_render()
  end)
end


function usage:refresh()
  self._lastRefresh = os.time()
  for _, provider in ipairs(providers) do
    if self._timers[provider.name] then
      self._timers[provider.name]:stop()
    end
    self:_poll(provider)
  end
end


-- The file of a crashed session stays "busy", so the process is checked too
function usage:_checkClaudeBusy()
  local pids = busyClaudePids()
  if #pids == 0 then
    self._busy.claude = false
    return self:_render()
  end
  local args = {"-p", table.concat(pids, ","), "-o", "pid="}
  run("/bin/ps", args, function(code)
    self._busy.claude = code == 0
    self:_render()
  end)
end


-- Separate from usage:start(), so menuitem.lua creates the item where it
-- is placed
function usage:createItem()
  -- See GraphItem.new() of menuitem.lua for the name
  self._item = hs.menubar.new(true, "usage")
end


function usage:start(srcDir)
  for _, provider in ipairs(providers) do
    self._logos[provider.name] = hs.image.imageFromPath(
      srcDir .. provider.logo.file)
  end
  -- Drawn over the item like the CPU graph of menuitem.lua, since an item
  -- icon can't cover its padding
  self._canvas = hs.canvas.new({x = 0, y = 0, w = 1, h = menuHeight})
  self._canvas:level(hs.canvas.windowLevels.mainMenu + 1)
  self._canvas:behavior({"canJoinAllSpaces", "stationary"})
  self._item:setMenu(function() return self:_menu() end)
  self:_render()
  self._renderTimer = hs.timer.doEvery(60, function()
    self:_checkClaudeBusy()
  end)
  -- The real path, since ~/.claude is a symlink to the dotfiles
  local sessionsDir = hs.fs.pathToAbsolute(claudeSessionsDir)
  if sessionsDir then
    self._sessionsWatcher = hs.pathwatcher.new(sessionsDir, function()
      self:_checkClaudeBusy()
    end)
    self._sessionsWatcher:start()
  end
  self._wakeWatcher = hs.caffeinate.watcher.new(function(event)
    local events = hs.caffeinate.watcher
    if (event == events.systemDidWake or event == events.screensDidUnlock)
        and os.time() - self._lastRefresh >= wakeDebounceSec then
      self:refresh()
    end
  end)
  self._wakeWatcher:start()
  self:_checkClaudeBusy()
  self:refresh()
end
