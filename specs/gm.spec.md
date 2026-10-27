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
  iTerm2, the iTerm script and Hammerspoon are running, project cache age
  (file mtime) and project count per host.

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

Stub behavior today: the chooser lists projects from the cache (path as
text, host as subtext, Hammerspoon's default filtering), and `gm_new_done()`
types `debug` into the current session with `async_send_text()`.

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
- **CLI lookup**: the iTerm script resolves `gh` and `glab` with
  `shutil.which()`, falling back to `/opt/homebrew/bin` since GUI-launched
  iTerm may lack Homebrew in `PATH`, and prints both paths to the Script
  Console on start.
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
  github.com and gitlab.com through the `gh` and `glab` CLIs into a JSON
  cache. The CLIs own authentication and pagination, so GM needs no config
  or tokens; more hosts later are a `--hostname` parameter plus a host list.
  The UI reads the cache and shows it instantly; a refresh runs in the
  background. `gm:showNew()` re-reads the cache on every show (~10ms for
  100 projects); a missing cache shows a single "No projects" row.
- **Cache location**: `~/.cache/grigoryvp-gm/projects.json`. iTerm gives
  scripts no data directory, and the cache is written by the iTerm script
  but read by Hammerspoon and the Wox plugin, so it lives outside all three.
  The prefix avoids clashes with other tools named `gm`. Each part keeps the
  path in a constant that names the other users.
- **Cache format**: `{"projects": [{"host": "github.com", "path":
  "owner/repo"}, ...]}`, sorted by path, written atomically (temp file +
  `os.replace()`) so readers never see a partial file. Each fetch replaces
  only its host's entries; the read-modify-write has no `await` inside, so
  concurrent fetches don't lose each other's entries.
- **Fetch** (done): on script start and then every 10 minutes, both CLIs
  run concurrently via `asyncio.create_subprocess_exec()`. A non-zero exit
  prints stderr to the Script Console and leaves the host's entries as is;
  an exception is printed too and doesn't stop the refresh loop.
  - GitHub: `gh api
    'user/repos?affiliation=owner,collaborator,organization_member&per_page=100'
    --paginate --jq '.[].full_name'`. `--jq` is needed because plain
    `--paginate` prints one JSON array per page, which is not valid JSON as
    a whole.
  - GitLab: `glab api 'projects?membership=true&simple=true&per_page=100'
    --paginate`, taking `path_with_namespace`. glab merges pages into a
    single array itself.
- **`gm new`**: fuzzy-pick a project, enter a branch. Clone into `~/git` on
  first use, `git fetch`, then create a worktree in `~/Documents`: track the
  remote branch if it exists, otherwise branch off the fresh default branch.
  If the branch already has a worktree, switch to its tab instead (git allows
  one worktree per branch).
- **Tabs**: one named tab per worktree. The tab <-> worktree link is the tab
  variable `user.worktree` holding the worktree path, not the title: shells
  and users rewrite titles, and titles of different projects can collide. A
  tab variable rather than a session one, so splits share it. If several
  tabs match, the first one is used and the rest are left alone.
- **Dependencies**: detect the stack by lockfiles (`uv.lock` -> `uv sync`,
  `pnpm-lock.yaml` -> `pnpm i`, `package-lock.json` -> `npm ci`, ...), with an
  optional per-repo override; run the install in the new tab.
- **`gm rm`**: refuse without confirmation when the worktree has uncommitted
  changes or unpushed commits; then `git worktree remove` and close the tab.
- **Source of truth** for existing worktrees is `git worktree list` across the
  clones in `~/git`; GM keeps no separate state.

## Implementation plan

Each step adds one small piece and ends with a manual check. Delete a step
once it's done and its decisions are reflected above; delete the section
when it's empty.

1. **Pass the selection back.** `gm_new_done(project)` receives the selected
   project id, escaped for the `invoke API expression` string; dismissing
   sends nothing. Check: the typed debug text is the project id; Esc types
   nothing.
2. **Branch input.** After a project is picked, a second chooser takes the
   branch name from its query text. Check: debug text is
   `<project> <branch>`; a pasted branch name works.
3. **Clone.** If the project is not in `~/git/<host>/<path>`, clone it.
   Check: first run clones, second run skips cloning.
4. **Worktree.** `git fetch`, then `git worktree add` in
   `~/Documents/<repo>-<branch>`: track the remote branch if it exists,
   otherwise branch off the fresh default branch. Check: `git worktree list`
   shows it, for both an existing and a new branch.
5. **Tab.** Open a tab in the worktree directory, name it after the
   worktree and set its `user.worktree`. Replace the debug text. Check: the
   tab opens in the right directory with the right title; `user.worktree`
   survives an iTerm restart.
6. **Existing tab.** If a tab's `user.worktree` already holds the worktree
   path, reuse it instead of opening another one. Check: remove the worktree
   manually, keep its tab, run `gm new` with the same branch: still one
   tab.
7. **Existing worktree.** If the branch already has a worktree, focus its
   tab, opening one if it was closed. Check: `gm new` with the same branch
   twice gives one worktree and one tab.
8. **Dependencies.** Detect the stack by lockfiles and run the install
   command in the new tab. Check: a `uv` project gets `uv sync`, a project
   without lockfiles gets nothing.
9. **`gm go`.** A chooser lists worktrees from `git worktree list` across
   `~/git`; selecting one focuses or opens its tab. Check: works for a tab
   that is open and for one that was closed.
10. **`gm go` splits.** A newly opened tab gets the standard split layout.
    Check: the layout matches the one from shift-cmd-d.
11. **`gm rm`.** A chooser lists worktrees; removal checks for uncommitted
    changes and unpushed commits and asks for confirmation if any, then
    runs `git worktree remove` and closes the tab. Check: a clean worktree is
    removed at once, a dirty one only after confirmation.
12. **Error reporting.** Failures in background work show an `hs.alert`
    besides the Script Console. Check: a fetch with a broken CLI path shows
    an alert.
