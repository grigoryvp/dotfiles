# {
#   "Id": "fc261a7b-5456-4e4e-a761-4f1050941652",
#   "Name": "Skill Manager",
#   "Author": "Grigory Petrov",
#   "Version": "0.1.0",
#   "MinWoxVersion": "2.4.2",
#   "Runtime": "Python",
#   "Description": "Agent skills from git repos in ~/skills",
#   "Icon": "emoji:🧩",
#   "TriggerKeywords": ["sm"],
#   "SupportedOS": ["Macos"],
#   "Commands": [
#     {"Command": "sync", "Description": "Link skills from ~/skills into the agents"},
#     {"Command": "pull", "Description": "Pull the skill repos and link their skills"}
#   ]
# }

# Wox front end of Skill Manager; the logic lives in iterm/Scripts/AutoLaunch/sm.py.

import asyncio

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

ICON = WoxImage.new_emoji("🧩")
COMMANDS = {
    "sync": "Link skills from ~/skills into the agents",
    "pull": "Pull the skill repos and link their skills",
}


# Returns the error text, or None on success. RPCs return before doing their
# work, so its outcome shows up in the iTerm status line.
# The expression goes in argv, so it needs no AppleScript escaping.
async def invoke_iterm(expression: str) -> str | None:
    proc = await asyncio.create_subprocess_exec(
        "osascript",
        "-e",
        "on run argv",
        "-e",
        'tell application id "com.googlecode.iterm2" to '
        "invoke API expression (item 1 of argv)",
        "-e",
        "end run",
        expression,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.PIPE,
    )
    _, stderr = await proc.communicate()
    return stderr.decode().strip() if proc.returncode else None


class SkillManager:
    async def init(self, ctx: Context, params: PluginInitParams) -> None:
        self.api = params.api

    async def query(self, ctx: Context, query: Query) -> QueryResponse:
        if query.command in COMMANDS:
            results = [self.rpc_result(query.command)]
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
            title=f"sm {name}",
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

    # Calls sm_<name>() in iterm/Scripts/AutoLaunch/sm.py.
    def rpc_result(self, name: str) -> Result:
        async def run(ctx: Context, _: ActionContext) -> None:
            error = await invoke_iterm(f"sm_{name}()")
            if error:
                await self.api.notify(ctx, f"sm {name}: {error}")

        return Result(
            title=f"sm {name}",
            sub_title=COMMANDS[name],
            icon=ICON,
            actions=[ResultAction(name="Run", action=run)],
        )


plugin = SkillManager()
