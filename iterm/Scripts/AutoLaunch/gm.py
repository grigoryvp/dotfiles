#!/usr/bin/env python3
# Git Manager (GM): one git worktree and iTerm tab per task.
#
# Parts:
# - Project list: periodically fetches repos from configured GitLab/GitHub
#   hosts into a JSON cache that the Hammerspoon UI reads.
# - RPC entry points: called by hammerspoon/gm.lua via AppleScript
#   `invoke API expression`, so the UI never talks to git directly.
# - Worktrees: clones into ~/git on first use, creates worktrees in
#   ~/Documents, removes them after checking for unpushed work.
# - Tabs: opens a named tab per worktree, runs the stack's dependency
#   install there, and closes it when the worktree is removed.
import iterm2


async def main(connection):
    pass


iterm2.run_forever(main)
