# Git Manager (GM)

Housekeeping for many parallel tasks: one git worktree and one iTerm tab per
task. Repositories are cloned once into `~/git`, each task gets a worktree in
`~/Documents`, a named iTerm tab and its runtime dependencies installed.

Status: the Wox -> iTerm -> Hammerspoon -> iTerm call chain works end to end
with stub UI. Everything marked *planned* is not implemented yet.

## Components

- **Wox plugin** (`wox/plugins/single-file/gm.py`): entry point, `gm`
  keyword and commands.
- **iTerm script** (`iterm/Scripts/AutoLaunch/gm.py`): all logic (git,
  worktrees, tabs) and the RPC functions.
- **Hammerspoon module** (`hammerspoon/gm.lua`): native UI (`hs.chooser`).

The UI layer never touches git, and the Wox plugin only forwards commands.
All logic lives in the iTerm script so it can manage tabs through the iTerm
Python API.

Why this split: Wox gives a launcher with commands without memorizing
hotkeys; Hammerspoon is always running, so its native windows open in well
under 0.5s with no extra resident process; the iTerm script is the only place
with first-class access to tabs and sessions.

## Commands

- `gm new` (stub): picks a project and a branch, creates a worktree and a
  tab.
- `gm rm` (planned): removes a worktree and closes its tab.
- `gm go` (planned): focuses a worktree's tab, creating it and its splits if
  missing.
- `gm status` (done): debug info: query fields, plugin Python, whether
  iTerm2 and Hammerspoon are running.

`gm` with no command lists the commands; selecting one changes the query to
`gm <command> `. Wox also suggests commands itself from the `Commands`
metadata, and its Indicator plugin finds GM by keyword, name or command.

## Call chain

```
Wox (gm new, Enter)
  -> osascript: tell application id "com.googlecode.iterm2"
       to invoke API expression "gm_new()"
iTerm script: RPC gm_new()
  -> HTTP POST localhost:2020 {"command": "gm_new"}
Hammerspoon: App:startHttpServer() -> gm:showNew() -> hs.chooser
  ... user selects or dismisses ...
Hammerspoon: hideCallback -> hs.task osascript
  -> invoke API expression "gm_new_done()"
iTerm script: RPC gm_new_done() -> acts on the current session
```

Stub behavior today: the chooser has one row, and `gm_new_done()` types
`debug` into the current session with `async_send_text()`.

### Transports

- **Wox / Hammerspoon -> iTerm**: AppleScript `invoke API expression`
  (`iTerm2.sdef`). Needs no Python API cookie and no extra process. macOS asks
  once for Automation permission per calling app (Wox, Hammerspoon).
- **iTerm -> Hammerspoon**: the existing JSON-over-HTTP server on
  `localhost:2020` in `hammerspoon/main.lua`, also used by Karabiner. GM adds
  `gm_*` commands to its dispatch.

## Constraints and gotchas

- **iTerm RPCs must return immediately.** iTerm suspends an AppleScript
  `invoke API expression` until the RPC returns and queues every other
  AppleEvent meanwhile. An RPC that calls the iTerm API before returning
  never returns, and iTerm stops answering AppleScript until the script is
  killed. RPCs therefore only schedule work with `run_in_background()`.
  Downside: errors in that work show up only in iTerm's Script Console.
- **Blocking calls** (`urllib`) run in `asyncio.to_thread()` so they don't
  stall the API connection.
- **`hs.chooser` objects are never freed**, so each chooser is created once and
  reused (same as `App:showSymbolPicker`).
- **`hs.chooser` `hideCallback` fires twice per hide**; GM acts only on the
  first call after `show()`.
- **Hammerspoon -> iTerm uses `hs.task`**, not `hs.osascript`, so a pending
  Automation prompt doesn't block Hammerspoon's main thread.
- **Reloading**: Wox reloads the plugin ~0.5s after the file is saved; iTerm
  needs the script restarted from its Scripts menu; Hammerspoon needs
  `hs.reload()`.

## Installation

- `~/.wox/wox-user` is a symlink to `~/dotfiles/wox`, set up by
  `configure_macos.sh` and `configure_win.ps1`. Git tracks only
  `wox/plugins/single-file/`; settings, database and notes stay local.
- iTerm's `Scripts/AutoLaunch` is a symlink to
  `~/dotfiles/iterm/Scripts/AutoLaunch`, so `gm.py` starts with iTerm.
- `hammerspoon/init.lua` requires `gm` with the other modules.
- The Wox plugin is single-file SDK type and needs Wox 2.4.2+.

## Planned design

- **Project list**: the iTerm script periodically fetches repositories from
  GitLab and GitHub hosts listed in a config into a JSON cache. The
  UI reads the cache and shows it instantly; a refresh runs in the background.
- **`gm new`**: fuzzy-pick a project, enter a branch. Clone into `~/git` on
  first use, `git fetch`, then create a worktree in `~/Documents`: track the
  remote branch if it exists, otherwise branch off the fresh default branch.
  If the branch already has a worktree, switch to its tab instead (git allows
  one worktree per branch).
- **Tabs**: one named tab per worktree. The tab <-> worktree link is a session
  user variable (e.g. `user.worktree`), so it survives an iTerm restart.
- **Dependencies**: detect the stack by lockfiles (`uv.lock` -> `uv sync`,
  `pnpm-lock.yaml` -> `pnpm i`, `package-lock.json` -> `npm ci`, ...), with an
  optional per-repo override; run the install in the new tab.
- **`gm rm`**: refuse without confirmation when the worktree has uncommitted
  changes or unpushed commits; then `git worktree remove` and close the tab.
- **Source of truth** for existing worktrees is `git worktree list` across the
  clones in `~/git`; GM keeps no separate state.
