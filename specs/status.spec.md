# iTerm Status Bar

A one-line log in the title of every iTerm window, so that after giving a
command (e.g. `gm merge` from Wox) the user can watch its progress and see
whether it failed: `⌛ git push test-project (12s)`, `⚠️ git push failed:
503`, `✅ gm MERGE test-project`.

Status: done, used by GM.

## Components

`iterm/Scripts/AutoLaunch/status.py` is both a script and a module, like
`split.py`:

- **Run by iTerm** (`__name__ == "__main__"`): owns the state and the window
  titles, registers the `status_add()` RPC.
- **Imported** by other iTerm scripts (`gm.py` first): `init()` and
  `add_log()`, a client that calls that RPC.

Why one owner: each AutoLaunch script is a separate process, so if
`add_log()` set titles itself, every importing script would draw them from
its own state and overwrite the others.

Why only iTerm scripts write: the workflow logic lives in them. Wox shows
its own errors, Hammerspoon only forwards picks to iTerm and has its own
log.

## API

`init(connection)` is called once from the importing script's `main()`
and keeps its `iterm2.Connection` in the module, so that `await
add_log(kind, text)` works from any function without passing the
connection down (most GM steps are module-level functions that don't have
it). Before `init()`, `add_log()` only prints the entry to the Script
Console.

`add_log(kind, text)`:

- `kind`: `progress`, `success` or `error`.
- `text`: short and self-contained, with a project or worktree name rather
  than a path, since the title bar is narrow.

It calls `status_add(kind: ..., text: ...)` through
`iterm2.async_invoke_function()` with the arguments encoded by
`iterm2.util.invocation_string()`, which escapes `\` and `"` (an unescaped
`\(` would start interpolation). If `status.py` isn't running or the call
fails, the error is printed to the Script Console and swallowed: a missing
status must not break the workflow.

## Behavior

- **State**: only the latest entry and its time, in memory; a restart of
  `status.py` loses it, which is fine for a status line. Commands are quick
  and not run in parallel, so a newer entry simply replaces the older one,
  whatever command wrote it.
- **`status_add()`** only updates the state and wakes the render loop, so
  the RPC returns at once (see "iTerm RPCs must return immediately" in
  `specs/gm.spec.md`).
- **Title**: `<emoji> <text>`, where the emoji is ⌛, ✅ or ⚠️ by kind. A
  progress entry also gets its elapsed time, `(12s)`, so a step that
  hangs or a command that crashed shows a growing number. Steps take less
  than a minute, so after one it stops ticking and shows `(>1m)` until the
  next entry. A final entry has no time.
- **Expiry**: a success or error entry after 10 minutes; a progress entry
  never, so a hang stays visible.
- **Idle**: with no entry or after expiry the title is `iTerm2 status
  plugin on Python <sys.version>`, which shows that `status.py` runs and on
  what. iTerm's default window title isn't needed: the user works in a
  single window with tabs and never edits the window title.
- **Rendering**: to save battery the title is set only when it changes: on
  start, on `status_add()`, every second during a progress entry's first
  minute, and on expiry. The render loop sleeps until the earliest of
  these; a new entry cuts the sleep short and sets a new one. Every window
  in `app.terminal_windows` gets the title with `Window.async_set_title()`,
  so a window opened while idle gets it with the next entry. It is the same
  override as Window > Edit Window Title, so terminal escape sequences
  (e.g. Claude Code's session title) don't replace it, while pane titles
  and tab statuses keep working. The title is an interpolated string, so `\` in the
  text is escaped as `\\`.

## Users

- **GM**: see **Status line** in `specs/gm.spec.md`.
