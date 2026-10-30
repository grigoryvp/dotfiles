# Git Manager (GM)

Housekeeping for many parallel tasks: one git worktree and one iTerm tab per
task. Repositories are cloned once into `~/git`, each task gets a worktree in
`~/Documents`, a named iTerm tab and its runtime dependencies installed.

Status: `gm new`, `gm create`, `gm go`, `gm rm`, `gm merge` and `gm
refresh` work end to end. Everything marked *planned* is not implemented yet.

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

- `gm new` (done): picks a project and a branch, creates a worktree and a
  tab, and installs dependencies there.
- `gm create <name>` (done): creates a private GitHub repo and continues
  as `gm new` with branch `new`.
- `gm rm` (done): removes a worktree and closes its tab.
- `gm merge` (done): merges a worktree's branch into the default one,
  pushes it, then removes the worktree as `gm rm` does.
- `gm go` (done): focuses a worktree's tab, creating it and its splits if
  missing.
- `gm refresh` (done): fetches the project list now instead of waiting
  for the periodic refresh.
- `gm status` (done): debug info: query fields, plugin Python, whether
  iTerm2, the iTerm script and Hammerspoon are running, project cache age
  (file mtime), project count per host and the last 5 logged errors.

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
Hammerspoon: App:startHttpServer() -> gm:showNew() -> project hs.chooser
  ... user selects a project or dismisses ...
Hammerspoon: completion callback -> gm:_showBranch() -> branch hs.chooser
  ... user types or pastes a branch and presses Enter, or dismisses ...
Hammerspoon: completion callback -> hs.task osascript
  -> invoke API expression
       "gm_new_done(project: \"<host>/<path>\", branch: \"<branch>\")"
iTerm script: RPC gm_new_done(project, branch) -> clone, worktree, tab
```

`gm create` takes the name in Wox itself, so there is no Hammerspoon UI:

```
Wox (gm create <name>, Enter)
  -> osascript: invoke API expression "gm_create(name: \"<name>\")"
iTerm script: RPC gm_create(name) -> gh repo create, then as gm_new_done()
```

`gm go` follows the same chain with `gm_go()`, except that the iTerm script
first collects the worktrees and passes them in the HTTP request, since the
UI never touches git:

```
iTerm script: RPC gm_go() -> worktrees of all clones in ~/git
  -> HTTP POST localhost:2020 {"command": "gm_go", "worktrees": [{"path":
       ..., "project": "<host>/<path>", "branch": ...}, ...]}
Hammerspoon: gm:showGo(worktrees) -> hs.chooser
  -> invoke API expression "gm_go_done(worktree: \"<path>\")"
iTerm script: RPC gm_go_done(worktree) -> focus or open its tab
```

`gm rm` is the same with `gm_rm()` and `gm_rm_done(worktree)`, plus a
confirmation round trip when the worktree has unsaved work:

```
iTerm script: RPC gm_rm_done(worktree) -> unsaved work found
  -> HTTP POST localhost:2020 {"command": "gm_rm_confirm", "worktree": ...,
       "reasons": "2 uncommitted changes, 1 unpushed commits"}
Hammerspoon: gm:showRmConfirm() -> hs.chooser
  -> invoke API expression "gm_rm_force(worktree: \"<path>\")"
iTerm script: RPC gm_rm_force(worktree) -> remove with --force, close tab
```

`gm merge` is the same with `gm_merge()` and `gm_merge_done(worktree)`; the
request also carries `"active": "<path>"`, the worktree of iTerm's active
tab, if any. A failure is shown instead of a confirmation:

```
iTerm script: RPC gm_merge_done(worktree) -> not merged
  -> HTTP POST localhost:2020 {"command": "gm_merge_failed", "worktree": ...,
       "reason": "2 uncommitted changes"}
Hammerspoon: gm:showMergeFailed() -> hs.chooser with a single row
```

Behavior today: the chooser lists projects from the cache (path as
text, host as subtext colored per host, since the same path can exist on
both hosts, Hammerspoon's default filtering); selecting one opens
the branch chooser, whose only row mirrors the query with surrounding
whitespace trimmed (none for an empty query, so Enter does nothing). Selecting
that row calls `gm_new_done()`, which clones the project if needed and
creates the worktree and its tab (see **Clone**, **Worktree** and **Tabs**
below). Dismissing either chooser or a failure does nothing.

### Transports

- **Wox / Hammerspoon -> iTerm**: AppleScript `invoke API expression`
  (`iTerm2.sdef`). Needs no Python API cookie and no extra process. macOS asks
  once for Automation permission per calling app (Wox, Hammerspoon).
  Hammerspoon passes the expression to osascript in `argv`, so only the
  iTerm expression's string literals need escaping (`\` and `"`; a
  backslash also starts `\(...)` interpolation there).
- **iTerm -> Hammerspoon**: the existing JSON-over-HTTP server on
  `localhost:2020` in `hammerspoon/main.lua`, also used by Karabiner. GM adds
  `gm_*` commands to its dispatch.

## Constraints and gotchas

- **iTerm RPCs must return immediately.** iTerm suspends an AppleScript
  `invoke API expression` until the RPC returns and queues every other
  AppleEvent meanwhile. An RPC that calls the iTerm API before returning
  never returns, and iTerm stops answering AppleScript until the script is
  killed. RPCs therefore only schedule work with `run_in_background()`.
  Downside: nobody awaits that work, so its errors have to be reported
  separately (see **Error reporting**).
- **Blocking calls** (`urllib`) run in `asyncio.to_thread()` so they don't
  stall the API connection.
- **`hs.chooser` objects are never freed**, so each chooser is created once and
  reused (same as `App:showSymbolPicker`).
- **`hs.chooser` callbacks**: `hideCallback` fires on every hide, sometimes
  twice. GM uses the completion callback instead: it gets the row once on
  selection and `nil` on dismissal (twice on Esc), so `nil` is ignored.
  `queryChangedCallback` fires on typing, pasting and `show()`, but not on
  `query()`, so the branch chooser resets its rows explicitly before
  `show()`.
- **`hs.chooser:show()` right after `select()` in the same run loop turn**
  crashed Hammerspoon once in a test (AppKit layout exception in
  `-[HSChooser resizeWindow]`). Real use shows and selects from separate
  events, so GM does nothing about it; tests should space steps with
  `hs.timer.doAfter` and keep the timers referenced, or they get collected.
  Also, `hs -c` with non-ASCII text in the command hung the CLI in a test;
  build such strings with `string.char()`.
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

## Design

- **Project list**: the iTerm script periodically fetches repositories from
  github.com and gitlab.com through the `gh` and `glab` CLIs into a JSON
  cache. The CLIs own authentication and pagination, so GM needs no config
  or tokens; more hosts later are a `--hostname` parameter plus a host list.
  The UI reads the cache and shows it instantly; a refresh runs in the
  background. `gm:showNew()` re-reads the cache on every show (~10ms for
  100 projects); a missing cache shows a single "No projects" row.
- **Cache location**: `~/.cache/grigoryvp-gm/projects.json`, with the error
  log (see **Error reporting**) next to it. iTerm gives scripts no data
  directory, and the cache is written by the iTerm script but read by
  Hammerspoon and the Wox plugin, so it lives outside all three.
  The prefix avoids clashes with other tools named `gm`. Each part keeps the
  path in a constant that names the other users.
- **Cache format**: `{"projects": [{"host": "github.com", "path":
  "owner/repo"}, ...]}`, sorted by path, written atomically (temp file +
  `os.replace()`) so readers never see a partial file. Each fetch replaces
  only its host's entries; the read-modify-write has no `await` inside, so
  concurrent fetches don't lose each other's entries.
- **Fetch** (done): on script start, then every 10 minutes and on `gm
  refresh` (RPC `gm_refresh()`, no UI), both CLIs run concurrently via
  `asyncio.create_subprocess_exec()`. A non-zero exit prints stderr to the
  Script Console and leaves the host's entries as is; an exception is
  printed too and doesn't stop the refresh loop.
  - Authentication: a CLI without a token for its host isn't called and its
    entries stay as is; that's not an error, only a line in the Script
    Console. The check is local, `gh auth token --hostname github.com`
    (non-zero exit without a token) and `glab config get token --host
    gitlab.com` (empty output without a token): `auth status` calls the API
    and offline reports a valid token as invalid. An expired or revoked
    token passes the check and fails the fetch as above.
  - `gm refresh` writes its success with the outcome per host, e.g. `gm
    REFRESH: github.com 99 projects, gitlab.com not authenticated`; a host
    whose CLI isn't found shows `no CLI`.
  - GitHub: `gh api
    'user/repos?affiliation=owner,collaborator,organization_member&per_page=100'
    --paginate --jq '.[].full_name'`. `--jq` is needed because plain
    `--paginate` prints one JSON array per page, which is not valid JSON as
    a whole.
  - GitLab: `glab api 'projects?membership=true&simple=true&per_page=100'
    --paginate`, taking `path_with_namespace`. glab merges pages into a
    single array itself.
- **Clone** (done): into `~/git/<host>/<path>` unless that directory
  exists, with `gh repo clone` or `glab repo clone`, so the protocol and
  credentials come from the CLI's own config (gh: https, glab: ssh here). A
  failure prints the CLI's stderr to the Script Console. A clone is only a
  cache to make worktrees from: no command lists it, opens a tab in it or
  removes it.
- **Worktree** (done): the branch name is checked with `git check-ref-format
  --branch` (which also rejects a leading `-`). Then `git worktree prune`
  drops entries whose directory was deleted by hand, and if `git worktree
  list --porcelain` shows the branch checked out in a worktree other than
  the clone, that path is used as is, without a fetch.
  Otherwise `git fetch` runs with
  the host's CLI as the only credential helper (`-c credential.helper=` plus
  `-c 'credential.helper=!<cli> auth git-credential'`), the way `gh repo
  clone` does: plain git doesn't see the CLI's credentials for https remotes,
  and gh doesn't register itself as git's helper. A failed fetch aborts.
  Then `git switch --detach` in the clone frees whatever branch it holds
  (a fresh clone holds the default one), since git checks out a branch in
  one worktree only; the clone's files stay as they are. The
  worktree goes to `~/Documents/<repo>--<branch>` with `/` in the branch
  replaced by `-`:
  - a local branch is checked out as is;
  - otherwise `origin/<branch>` is tracked with `--track -b`;
  - otherwise a new branch starts from `origin/HEAD` with `--no-track`, since
    by default it would track the default branch and `git push` would target
    it.

  The new path is returned resolved, in the same form `git worktree list`
  gives, since tabs are matched by the exact string. An existing directory
  that isn't a worktree of this branch makes `git worktree add` fail; that
  is printed to the Script Console.
- **`gm new`**: fuzzy-pick a project, enter a branch. Clone into `~/git` on
  first use, `git fetch`, then create a worktree in `~/Documents`: track the
  remote branch if it exists, otherwise branch off the fresh default branch.
  If the branch already has a worktree, switch to its tab instead (git allows
  one worktree per branch).
- **Tabs**: one named tab per worktree. The tab <-> worktree link is the tab
  variable `user.worktree` holding the worktree path, not the title: shells
  and users rewrite titles, and titles of different projects can collide. A
  tab variable rather than a session one, so splits share it. If several
  tabs match, the first one is reused and the rest are left alone; `gm rm`
  closes them all.
  Opening (done): a new tab in the current window, or a new window if there
  is none, with the profile's initial directory overridden to the worktree.
  `Tab.async_set_title()` sets the worktree directory name as the title
  (an interpolated string, but repo and branch names can't contain `\`),
  then the window and iTerm are activated with `ignoring_other_apps`, since
  Wox or Hammerspoon is frontmost at that point.
  Splits (done): every tab GM opens, for `gm new` and `gm go` alike, gets
  the shift-cmd-d layout: a bottom pane of 10 rows. The layout lives in
  `split_with_bottom_pane()` in `iterm/Scripts/AutoLaunch/split.py`, which
  `gm.py` imports (the AutoLaunch dir is on `sys.path`) rather than calling
  its RPC, so GM doesn't depend on that script running. The bottom pane gets
  the same initial directory as the tab, since the profile's "recycle" mode
  would depend on the top shell having started. The install command goes to
  the top pane, which is then focused.
  Reuse (done): before opening, all tabs of all windows are searched for
  `user.worktree`; a match is selected with `Tab.async_activate()` instead,
  keeping its title. GM sends nothing to a reused tab, so if the worktree was
  removed and recreated, its shell still sits in the removed directory until
  `cd`.
- **Dependencies** (done, except the override): detect the stack by
  lockfiles in the worktree root (`uv.lock` -> `uv sync`, `poetry.lock` ->
  `poetry install`, `pnpm-lock.yaml` -> `pnpm i`, `package-lock.json` -> `npm
  ci`, `yarn.lock` -> `yarn install`, `bun.lock` -> `bun install`); all
  matches run, joined with `&&`. *Planned*: an optional per-repo override.
  The command is typed with `async_send_text()` once the tab, its split and
  its title are set up; if the shell hasn't started by then, it reads the
  command as typeahead. It is typed
  without a newline: the user reviews it and presses Enter. It is typed only
  in a tab GM just opened for a worktree it just created: an existing
  worktree presumably has its dependencies, and GM never types into a tab
  that may be running something.
- **`gm create`** (done): the name must match
  `[A-Za-z0-9_.][A-Za-z0-9_.-]*` (characters GitHub keeps, no leading `-`
  that gh would take for an option), checked by both the Wox plugin and the
  iTerm script; it also needs no escaping in the iTerm expression. `gh repo
  create <name> --private --add-readme` creates it under the gh user; the
  README gives it a default branch to start from. Without a TTY gh prints
  only the repo URL, whose last two parts are `<owner>/<name>`. Then a
  GitHub fetch for the project list runs in the background, and the rest is
  `gm new` with branch `new`: clone, worktree `~/Documents/<name>--new` off
  `origin/HEAD`, tab. A failure is reported as everywhere else.
- **`gm go`** (done): the chooser lists the worktrees in `~/Documents`,
  i.e. the linked worktrees of all clones in `~/git` (`git worktree list
  --porcelain` minus its first entry, the clone itself), collected
  concurrently; a detached worktree has no `branch`. The chooser row is the
  directory name (same as the tab title) with `<host>/<path> @ <branch>` as
  subtext, and filtering searches the subtext too. Selecting a row focuses
  or opens the tab as `gm new` does, but never types an install command. No
  worktrees show a single "No worktrees" row.
- **`gm rm`** (done): the chooser lists worktrees as `gm go` does. The
  picked path comes back over RPC, so it is removed only if it is a linked
  worktree of a clone in `~/git`. Unsaved work is `git status --porcelain` lines
  (uncommitted and untracked; ignored files like `node_modules` don't count)
  and `git rev-list --count HEAD --not --remotes` (commits on no
  remote-tracking branch, as of the last fetch, so a new branch without own
  commits is clean). Without unsaved work the worktree is removed at once;
  with it, a confirmation chooser opens with "Keep" as the first row, so a
  reflexive Enter removes nothing, and "Remove anyway" runs `git worktree
  remove --force`. The local branch stays, so unpushed commits survive and a
  later `gm new` with that branch checks it out again. After removal all
  its tabs are closed with `Tab.async_close()` without force: iTerm still
  asks if something runs there.
- **`gm merge`** (done): the chooser lists worktrees as `gm go` does, with
  the active tab's worktree moved to the first row, which the chooser
  selects. The picked worktree is refused if it is detached or has
  uncommitted changes (counted as in `gm rm`; unpushed commits are what gets
  merged). Then, in the clone, `git fetch` with the CLI's credentials as in
  **Worktree**, `git switch --detach origin/<default>`, `git merge -m "Merge
  branch '<branch>'"` (detached HEAD would make git's own message say "into
  HEAD") and `git push origin HEAD:refs/heads/<default>`. The clone is
  used because it is detached and otherwise unused, while the local default
  branch may be checked out in some worktree; the local default branch is
  left behind. A failed merge is aborted with `git merge --abort`. Any
  refusal or failure opens a chooser with the reason, details are in `gm
  status`. After the push the worktree has no unsaved work, so `gm rm` logic
  removes it without a confirmation and closes its tabs.
- **Source of truth** for existing worktrees is `git worktree list` across the
  clones in `~/git`; GM keeps no separate state. Every listing, for `gm new`,
  `gm go`, `gm rm` and `gm merge` alike, runs `git worktree prune` first, so worktrees
  whose directory was deleted by hand don't show up.
- **Status line** (done): the user's commands write to the window title
  through `status.py` (`specs/status.spec.md`): progress before steps that
  can take long or fail on the network (clone, fetch, push, `gh repo
  create`, `gm refresh`), the command on success and `<command>:
  <message>` on the first failure. Every command, including future ones,
  must write its success, so the title confirms that it ran. The command
  is written with its name in caps, e.g. `gm RM pycon25`, to stand out in
  the title. The periodic refresh writes nothing, offline it would show an
  error all the time. RPCs start commands with `run_command()`, which sets
  a `ContextVar` the command's tasks and their done callback copy, so
  `report()` marks the running command failed and shows its message with
  no error plumbing through the steps; later failures are usually
  consequences and aren't shown. A merge refusal isn't reported and goes to
  the status line explicitly. Success comes from the step that ends the
  command, so `gm merge` succeeds in the removal it ends with, and `gm rm`
  waiting for a confirmation shows nothing.
- **Error reporting** (done): every failure described above as printed to
  the Script Console goes through `report()` in the iTerm script, which
  prints the message and appends it to `~/.cache/grigoryvp-gm/gm.log` as
  `<date> <time> <message>`, one entry per line (multi-line stderr, or stdout
  if stderr is empty, since git merge prints conflicts there, is joined
  with ` | `), so readers can take the last lines. `gm status` shows the
  last 5 entries, newest first. `run_in_background()` reports unhandled
  exceptions of its tasks too, with the traceback in the console only.
  Hammerspoon's own failures to call iTerm (`osascript` exit code) go to the
  same file via `gm:_logError()`. Not alerts: a periodic fetch fails every
  10 minutes while offline. Over 1 MB the iTerm script renames the log to
  `gm.log.1`, keeping one previous file.
