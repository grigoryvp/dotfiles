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


# Synchronous so that concurrent fetches can't interleave read and write.
def update_cache(host: str, paths: list[str]) -> None:
    try:
        projects = json.loads(CACHE_PATH.read_text())["projects"]
    except FileNotFoundError:
        projects = []
    projects = [p for p in projects if p["host"] != host]
    projects += [{"host": host, "path": path} for path in paths]
    projects.sort(key=lambda p: p["path"])
    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    # Readers must never see a partially written file.
    tmp_path = CACHE_PATH.with_suffix(".tmp")
    tmp_path.write_text(json.dumps({"projects": projects}, indent=2))
    os.replace(tmp_path, CACHE_PATH)
    print(f"{host}: {len(paths)} projects")


async def run_cli(*args: str) -> str | None:
    proc = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await proc.communicate()
    if proc.returncode != 0:
        print(f"{Path(args[0]).name} failed: {stderr.decode().strip()}")
        return None
    return stdout.decode()


async def fetch_github(gh: str) -> None:
    # --jq flattens pages: plain --paginate prints one JSON array per page.
    output = await run_cli(
        gh,
        "api",
        "user/repos?affiliation=owner,collaborator,organization_member&per_page=100",
        "--paginate",
        "--jq",
        ".[].full_name",
    )
    if output is not None:
        update_cache("github.com", output.split())


async def fetch_gitlab(glab: str) -> None:
    # Unlike gh, glab merges pages into a single JSON array.
    output = await run_cli(
        glab,
        "api",
        "projects?membership=true&simple=true&per_page=100",
        "--paginate",
    )
    if output is not None:
        paths = [p["path_with_namespace"] for p in json.loads(output)]
        update_cache("gitlab.com", paths)


REFRESH_INTERVAL_SEC = 10 * 60


async def refresh_projects(gh: str | None, glab: str | None) -> None:
    while True:
        fetches = []
        if gh is not None:
            fetches.append(fetch_github(gh))
        if glab is not None:
            fetches.append(fetch_gitlab(glab))
        # An exception in one fetch must not stop the refresh loop.
        for result in await asyncio.gather(*fetches, return_exceptions=True):
            if isinstance(result, Exception):
                print(f"fetch failed: {result!r}")
        await asyncio.sleep(REFRESH_INTERVAL_SEC)


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
    run_in_background(refresh_projects(gh, glab))

    async def send_debug(text: str):
        window = app.current_terminal_window
        if window is None or window.current_tab is None:
            return
        session = window.current_tab.current_session
        if session is not None:
            await session.async_send_text(text)

    @iterm2.RPC
    async def gm_new():
        # urlopen() blocks and would stall the API connection.
        run_in_background(asyncio.to_thread(call_hammerspoon, "gm_new"))

    # Called by hammerspoon/gm.lua with "<host>/<path>" of the picked project.
    @iterm2.RPC
    async def gm_new_done(project: str):
        run_in_background(send_debug(project))

    await gm_new.async_register(connection)
    await gm_new_done.async_register(connection)


iterm2.run_forever(main)
