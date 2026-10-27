# {
#   "Id": "cf221439-ea01-4bb3-8ef8-9b341b2a7d9a",
#   "Name": "Git Manager",
#   "Author": "Grigory Petrov",
#   "Version": "0.1.0",
#   "MinWoxVersion": "2.4.2",
#   "Runtime": "Python",
#   "Description": "One git worktree and iTerm tab per task",
#   "Icon": "emoji:🌳",
#   "TriggerKeywords": ["gm"],
#   "SupportedOS": ["Macos"],
#   "Commands": [
#     {"Command": "new", "Description": "Create a worktree and its iTerm tab"},
#     {"Command": "rm", "Description": "Remove a worktree and its iTerm tab"},
#     {"Command": "go", "Description": "Switch to a worktree's iTerm tab"},
#     {"Command": "status", "Description": "Show debug info"}
#   ]
# }

# Wox front end of Git Manager; the logic lives in iterm/Scripts/AutoLaunch/gm.py.

import asyncio
import json
import sys
import time
from collections import Counter
from pathlib import Path

from wox_plugin import (
    ActionContext,
    ChangeQueryParam,
    Context,
    PluginInitParams,
    Query,
    QueryResponse,
    QueryType,
    Result,
    ResultAction,
    WoxImage,
)

ICON = WoxImage.new_emoji("🌳")
COMMANDS = {
    "new": "Create a worktree and its iTerm tab",
    "rm": "Remove a worktree and its iTerm tab",
    "go": "Switch to a worktree's iTerm tab",
    "status": "Show debug info",
}

# Written by iterm/Scripts/AutoLaunch/gm.py, read here and by
# hammerspoon/gm.lua.
CACHE_PATH = Path.home() / ".cache" / "grigoryvp-gm" / "projects.json"
# Written by iterm/Scripts/AutoLaunch/gm.py and hammerspoon/gm.lua.
LOG_PATH = CACHE_PATH.parent / "gm.log"
LOG_ROWS = 5


def cache_status() -> dict[str, str]:
    try:
        age = int(time.time() - CACHE_PATH.stat().st_mtime)
        projects = json.loads(CACHE_PATH.read_text())["projects"]
    except FileNotFoundError:
        return {"Cache": "missing"}
    counts = Counter(p["host"] for p in projects)
    return {
        "Cache": f"updated {age // 60}m {age % 60}s ago",
        "Projects": ", ".join(f"{host}: {n}" for host, n in sorted(counts.items())),
    }


# Pairs rather than a dict: entries from the same second share a time.
def log_status() -> list[tuple[str, str]]:
    try:
        lines = LOG_PATH.read_text().splitlines()[-LOG_ROWS:]
    except FileNotFoundError:
        lines = []
    if not lines:
        return [("Errors", "none")]
    # Newest first; each line is "<date> <time> <message>".
    return [
        (f"Error at {date} {clock}", message)
        for date, clock, message in (line.split(" ", 2) for line in reversed(lines))
    ]


async def running_status(*pgrep_args: str) -> str:
    proc = await asyncio.create_subprocess_exec(
        "pgrep",
        *pgrep_args,
        stdout=asyncio.subprocess.DEVNULL,
    )
    return "running" if await proc.wait() == 0 else "not running"


# Returns the error text, or None on success. RPCs return before doing their
# work, so errors in it show up only in iTerm's Script Console.
async def invoke_iterm(expression: str) -> str | None:
    script = (
        'tell application id "com.googlecode.iterm2" to '
        f'invoke API expression "{expression}"'
    )
    proc = await asyncio.create_subprocess_exec(
        "osascript",
        "-e",
        script,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.PIPE,
    )
    _, stderr = await proc.communicate()
    return stderr.decode().strip() if proc.returncode else None


class GitManager:
    async def init(self, ctx: Context, params: PluginInitParams) -> None:
        self.api = params.api

    async def query(self, ctx: Context, query: Query) -> QueryResponse:
        if query.command == "status":
            results = await self.status(query)
        elif query.command == "new":
            results = [self.rpc_result("new", "Open the project picker")]
        elif query.command == "go":
            results = [self.rpc_result("go", "Open the worktree picker")]
        elif query.command == "rm":
            results = [self.rpc_result("rm", "Open the worktree picker")]
        else:
            results = [self.command_result(query, name) for name in COMMANDS]
        return QueryResponse(results=results)

    def command_result(self, query: Query, name: str) -> Result:
        async def complete(ctx: Context, _: ActionContext) -> None:
            await self.api.change_query(
                ctx,
                ChangeQueryParam(
                    query_type=QueryType.INPUT,
                    query_text=f"{query.trigger_keyword} {name} ",
                ),
            )

        return Result(
            title=f"gm {name}",
            sub_title=COMMANDS[name],
            icon=ICON,
            actions=[
                ResultAction(
                    name="Select",
                    action=complete,
                    prevent_hide_after_action=True,
                )
            ],
        )

    # Commands that only call gm_<name>() in iterm/Scripts/AutoLaunch/gm.py.
    def rpc_result(self, name: str, sub_title: str) -> Result:
        async def run(ctx: Context, _: ActionContext) -> None:
            error = await invoke_iterm(f"gm_{name}()")
            if error:
                await self.api.notify(ctx, f"gm {name}: {error}")

        return Result(
            title=f"gm {name}",
            sub_title=sub_title,
            icon=ICON,
            actions=[ResultAction(name="Open", action=run)],
        )

    async def status(self, query: Query) -> list[Result]:
        rows = {
            "Query": repr(query.raw_query),
            "Search": repr(query.search),
            "Python": sys.version.split()[0],
            "iTerm2": await running_status("-x", "iTerm2"),
            "iTerm script": await running_status("-f", "AutoLaunch/gm.py"),
            "Hammerspoon": await running_status("-x", "Hammerspoon"),
            **cache_status(),
        }
        return [
            Result(title=value, sub_title=name, icon=ICON)
            for name, value in [*rows.items(), *log_status()]
        ]


plugin = GitManager()
