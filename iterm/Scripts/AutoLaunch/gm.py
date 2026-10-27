#!/usr/bin/env python3
# Git Manager (GM): one git worktree and iTerm tab per task.
#
# Parts:
# - Project list: periodically fetches repos from configured GitLab/GitHub
#   hosts into a JSON cache that the Hammerspoon UI reads.
# - RPC entry points: called by the Wox plugin (wox/plugins/single-file/gm.py)
#   via AppleScript `invoke API expression`; they show UI through the
#   Hammerspoon HTTP server (hammerspoon/gm.lua).
# - Worktrees: clones into ~/git on first use, creates worktrees in
#   ~/Documents, removes them after checking for unpushed work.
# - Tabs: opens a named tab per worktree, runs the stack's dependency
#   install there, and closes it when the worktree is removed.
import asyncio
import json
import urllib.request

import iterm2

# Started by App:startHttpServer() in hammerspoon/main.lua.
HAMMERSPOON_URL = "http://localhost:2020"


def call_hammerspoon(command: str) -> None:
    body = json.dumps({"command": command}).encode()
    urllib.request.urlopen(HAMMERSPOON_URL, data=body, timeout=5).close()


# iTerm suspends an AppleScript `invoke API expression` until the called RPC
# returns, queueing all other AppleEvents, and an RPC that calls the iTerm API
# meanwhile never returns. So RPCs only schedule their work.
_background: set[asyncio.Task] = set()


def run_in_background(coro) -> None:
    task = asyncio.create_task(coro)
    _background.add(task)
    task.add_done_callback(_background.discard)


async def main(connection):
    app = await iterm2.async_get_app(connection)

    async def send_debug():
        window = app.current_terminal_window
        if window is None or window.current_tab is None:
            return
        session = window.current_tab.current_session
        if session is not None:
            await session.async_send_text("debug")

    @iterm2.RPC
    async def gm_new():
        # urlopen() blocks and would stall the API connection.
        run_in_background(asyncio.to_thread(call_hammerspoon, "gm_new"))

    # Called by hammerspoon/gm.lua when the picker closes.
    @iterm2.RPC
    async def gm_new_done():
        run_in_background(send_debug())

    await gm_new.async_register(connection)
    await gm_new_done.async_register(connection)


iterm2.run_forever(main)
