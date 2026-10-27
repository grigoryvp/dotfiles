# Sub-projects

## Git Manager

Provides fast switching between worktrees. Implemented according to
`specs/gm.spec.md` as 3 separate plugins. The core is iTerm2 plugin
`iterm/Scripts/AutoLaunch/gm.py` (since git manager relies on iTerm2
tabs), Wox plugin `wox/plugins/single-file/gm.py` for command access and
hammerspoon code `hammerspoon/gm.lua` for UI.

Keep spec in sync with the code and keep it as short as possible: only key
decisions that are not observable from code.
