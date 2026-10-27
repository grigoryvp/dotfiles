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
import os
import shutil
import urllib.request
from pathlib import Path

import iterm2

# Started by App:startHttpServer() in hammerspoon/main.lua.
HAMMERSPOON_URL = "http://localhost:2020"

# iTerm launched from the Dock may lack Homebrew in PATH.
HOMEBREW_BIN = "/opt/homebrew/bin"


def find_cli(name: str) -> str | None:
    return shutil.which(name) or shutil.which(name, path=HOMEBREW_BIN)


# Written here, read by hammerspoon/gm.lua and wox/plugins/single-file/gm.py.
CACHE_PATH = Path.home() / ".cache" / "grigoryvp-gm" / "projects.json"


def write_cache(projects: list[dict]) -> None:
    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    # Readers must never see a partially written file.
    tmp_path = CACHE_PATH.with_suffix(".tmp")
    tmp_path.write_text(json.dumps({"projects": projects}, indent=2))
    os.replace(tmp_path, CACHE_PATH)


async def fetch_github(gh: str) -> None:
    # --jq flattens pages: plain --paginate prints one JSON array per page.
    proc = await asyncio.create_subprocess_exec(
        gh,
        "api",
        "user/repos?affiliation=owner,collaborator,organization_member&per_page=100",
        "--paginate",
        "--jq",
        ".[].full_name",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await proc.communicate()
    if proc.returncode != 0:
        print(f"gh failed: {stderr.decode().strip()}")
        return
    projects = [
        {"host": "github.com", "path": path} for path in sorted(stdout.decode().split())
    ]
    write_cache(projects)
    print(f"github.com: {len(projects)} projects")


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
    gh = find_cli("gh")
    glab = find_cli("glab")
    print(f"gh: {gh}, glab: {glab}")
    if gh is not None:
        run_in_background(fetch_github(gh))

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
