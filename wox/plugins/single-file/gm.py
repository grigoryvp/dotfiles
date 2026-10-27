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
import sys

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


async def is_running(process_name: str) -> bool:
    proc = await asyncio.create_subprocess_exec(
        "pgrep",
        "-x",
        process_name,
        stdout=asyncio.subprocess.DEVNULL,
    )
    return await proc.wait() == 0


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
            results = [self.new_result()]
        elif query.command in COMMANDS:
            results = [
                Result(title=f"gm {query.command}: not implemented yet", icon=ICON)
            ]
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

    def new_result(self) -> Result:
        async def run(ctx: Context, _: ActionContext) -> None:
            error = await invoke_iterm("gm_new()")
            if error:
                await self.api.notify(ctx, f"gm new: {error}")

        return Result(
            title="gm new",
            sub_title="Open the project picker",
            icon=ICON,
            actions=[ResultAction(name="Open", action=run)],
        )

    async def status(self, query: Query) -> list[Result]:
        rows = {
            "Query": repr(query.raw_query),
            "Search": repr(query.search),
            "Python": sys.version.split()[0],
            "iTerm2": "running" if await is_running("iTerm2") else "not running",
            "Hammerspoon": (
                "running" if await is_running("Hammerspoon") else "not running"
            ),
        }
        return [
            Result(title=value, sub_title=name, icon=ICON)
            for name, value in rows.items()
        ]


plugin = GitManager()
