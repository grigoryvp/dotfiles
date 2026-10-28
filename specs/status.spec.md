# iTerm Status Bar

A one-line log in the title of every iTerm window, so that after giving a
command (e.g. `gm merge` from Wox) the user can watch its progress and see
whether it failed: `⌛ git push test-project (12s)`, `⚠️ git push failed:
503 (2m ago)`, `✅ gm merge test-project (5m ago)`.

Status: planned, nothing is implemented yet.

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
- **Title**: `<emoji> <text> (<time>)`, where the emoji is ⌛, ✅ or ⚠️ by
  kind, and the time is the elapsed time of a progress entry (`12s`, `5m`,
  `2h`), so a step that hangs or a command that crashed shows a growing
  number, or the age of a final one (`5m ago`).
- **Expiry**: an entry older than 1 hour is dropped, and the title is reset
  with `Window.async_set_title("")` to iTerm's default (the current tab's
  title).
- **Rendering**: once a second and right after `status_add()`, every window
  in `app.terminal_windows` gets the title with `Window.async_set_title()`,
  which also covers windows opened since the last tick. It is the same
  override as Window > Edit Window Title, so terminal escape sequences (e.g.
  Claude Code's session title) don't replace it, while pane titles and tab
  statuses keep working. The title is an interpolated string, so `\` in the
  text is escaped as `\\`. A manual Edit Window Title is overwritten.
- **Start**: titles of all windows are reset, since an override may survive
  in a restored window from a previous run.

## Users

- **GM** (planned): writes entries only for commands the user gave (`gm
  new`, `gm create`, `gm go`, `gm rm`, `gm merge`, `gm refresh`): a
  progress entry per step (clone, fetch, worktree, merge, push, remove) and
  a final success or error. The periodic project
  refresh doesn't write: offline it would show ⚠️ all the time. Errors keep
  going to `gm.log` too.
