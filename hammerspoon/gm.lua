-- Git Manager UI, shown on requests from iterm/Scripts/AutoLaunch/gm.py

gm = {
  _newChooser = nil,
  _branchChooser = nil,
  _goChooser = nil,
  _rmChooser = nil,
  _rmConfirmChooser = nil,
  -- "<host>/<path>" picked in _newChooser, waiting for a branch
  _newProject = nil
}


-- Calls an RPC registered by iterm/Scripts/AutoLaunch/gm.py. A task, since
-- osascript would block the main thread on the first automation prompt.
-- The expression goes in argv, so it needs no AppleScript escaping.
function gm:_invokeIterm(expression)
  local task = hs.task.new("/usr/bin/osascript", function(exitCode, _, stdErr)
    if exitCode ~= 0 then
      print("ERROR: gm " .. expression .. ": " .. stdErr)
    end
  end, {
    "-e", "on run argv",
    "-e", 'tell application id "com.googlecode.iterm2" to ' ..
      "invoke API expression (item 1 of argv)",
    "-e", "end run",
    expression
  })
  task:start()
end


-- String literal for an iTerm expression, where a backslash also starts
-- \(...) interpolation
function gm:_itermString(value)
  return '"' .. value:gsub('[\\"]', "\\%0") .. '"'
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
    table.insert(choices, {
      text = project.path,
      subText = project.host,
      id = project.host .. "/" .. project.path
    })
  end
  return choices
end


function gm:showNew()
  -- Choosers are never freed, see App:showSymbolPicker
  if not self._newChooser then
    -- Called once with the row on selection, and with nil on dismissal,
    -- up to twice per hide
    self._newChooser = hs.chooser.new(function(choice)
      if choice and choice.id then
        self:_showBranch(choice.id)
      end
    end)
  end
  -- Re-read on each show since the iTerm script refreshes the cache
  self._newChooser:choices(self:_projectChoices())
  self._newChooser:query("")
  self._newChooser:show()
end


-- The branch is free text, so the only row mirrors the query for Enter to
-- select
function gm:_branchChoices(query)
  local branch = query:match("^%s*(.-)%s*$")
  if branch == "" then
    return {}
  end
  return {{text = branch, subText = "Branch for " .. self._newProject}}
end


function gm:_showBranch(project)
  if not self._branchChooser then
    self._branchChooser = hs.chooser.new(function(choice)
      if choice then
        self:_invokeIterm(
          "gm_new_done(project: " .. self:_itermString(self._newProject) ..
          ", branch: " .. self:_itermString(choice.text) .. ")"
        )
      end
    end)
    -- Fires on typing, pasting and show(), but not on query()
    self._branchChooser:queryChangedCallback(function(query)
      self._branchChooser:choices(self:_branchChoices(query))
    end)
  end
  self._newProject = project
  self._branchChooser:placeholderText("Branch for " .. project)
  self._branchChooser:query("")
  self._branchChooser:choices({})
  self._branchChooser:show()
end


-- Worktrees come from iterm/Scripts/AutoLaunch/gm.py as
-- {path = ..., project = "<host>/<path>", branch = ... or nil if detached}
function gm:_worktreeChoices(worktrees)
  local choices = {}
  for _, worktree in ipairs(worktrees) do
    table.insert(choices, {
      -- Same as the tab title
      text = worktree.path:match("[^/]+$"),
      subText = worktree.project .. " @ " .. (worktree.branch or "detached"),
      path = worktree.path
    })
  end
  if #choices == 0 then
    choices = {{text = "No worktrees", subText = "Create one with gm new"}}
  end
  return choices
end


function gm:showGo(worktrees)
  if not self._goChooser then
    self._goChooser = hs.chooser.new(function(choice)
      if choice and choice.path then
        self:_invokeIterm(
          "gm_go_done(worktree: " .. self:_itermString(choice.path) .. ")"
        )
      end
    end)
    self._goChooser:searchSubText(true)
  end
  self._goChooser:choices(self:_worktreeChoices(worktrees))
  self._goChooser:query("")
  self._goChooser:show()
end


function gm:showRm(worktrees)
  if not self._rmChooser then
    self._rmChooser = hs.chooser.new(function(choice)
      if choice and choice.path then
        self:_invokeIterm(
          "gm_rm_done(worktree: " .. self:_itermString(choice.path) .. ")"
        )
      end
    end)
    self._rmChooser:searchSubText(true)
    self._rmChooser:placeholderText("Worktree to remove")
  end
  self._rmChooser:choices(self:_worktreeChoices(worktrees))
  self._rmChooser:query("")
  self._rmChooser:show()
end


-- Shown by iterm/Scripts/AutoLaunch/gm.py when the picked worktree has
-- unsaved work; reasons describes it
function gm:showRmConfirm(worktree, reasons)
  if not self._rmConfirmChooser then
    self._rmConfirmChooser = hs.chooser.new(function(choice)
      if choice and choice.path then
        self:_invokeIterm(
          "gm_rm_force(worktree: " .. self:_itermString(choice.path) .. ")"
        )
      end
    end)
  end
  local name = worktree:match("[^/]+$")
  self._rmConfirmChooser:placeholderText(name .. ": " .. reasons)
  -- Keep goes first, so a reflexive Enter removes nothing
  self._rmConfirmChooser:choices({
    {text = "Keep " .. name, subText = reasons},
    {
      text = "Remove " .. name .. " anyway",
      subText = "Loses " .. reasons,
      path = worktree
    }
  })
  self._rmConfirmChooser:query("")
  self._rmConfirmChooser:show()
end
