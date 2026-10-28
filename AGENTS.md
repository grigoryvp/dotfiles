# Sub-projects

If a sub-project is implemented according to a spec then keep spec in sync
with the project code and keep it as short as possible: only key decisions
that are not observable from code.

For iTerm plugins we write Python 3.12 code.

## Git Manager

Provides fast switching between worktrees. Implemented according to
`specs/gm.spec.md` as 3 separate plugins. The core is iTerm2 plugin
`iterm/Scripts/AutoLaunch/gm.py` (since git manager relies on iTerm2
tabs), Wox plugin `wox/plugins/single-file/gm.py` for command access and
hammerspoon code `hammerspoon/gm.lua` for UI.

## iTerm Status Bar

Provides a single "status bar" which is displayed as a window title. Used
by other iTerm-based projects to write logs to. Implemented according to
`specs/status.spec.md` as `iterm/Scripts/AutoLaunch/status.py` plugin.
