#!/usr/bin/env python3
# Git Manager (GM): one git worktree and iTerm tab per task.
#
# Parts:
# - Project list: periodically and on `gm refresh` fetches repos from
#   github.com and gitlab.com into a JSON cache that the Hammerspoon UI reads.
# - RPC entry points: called via AppleScript `invoke API expression` by the
#   Wox plugin (wox/plugins/single-file/gm.py) to show UI through the
#   Hammerspoon HTTP server, and by hammerspoon/gm.lua with the user's pick.
# - Worktrees: clones into ~/git on first use, creates worktrees in
#   ~/Documents, merges them into the default branch, removes them after
#   checking for unpushed work.
# - New projects: creates private GitHub repos and their first worktree.
# - Tabs: opens a named tab per worktree, runs the stack's dependency
#   install there, and closes it when the worktree is removed.
# - Status: progress and outcome of the user's commands go to the window
#   title through status.py.
import asyncio
import contextvars
import json
import os
import re
import shlex
import shutil
import time
import traceback
import urllib.request
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from pathlib import Path

import iterm2

# split.py and status.py are in the same AutoLaunch dir, which Python puts on
# sys.path.
import status
from split import split_with_bottom_pane

# Started by App:startHttpServer() in hammerspoon/main.lua.
HAMMERSPOON_URL = "http://localhost:2020"

# iTerm launched from the Dock may lack Homebrew in PATH.
HOMEBREW_BIN = "/opt/homebrew/bin"


def find_cli(name: str) -> str | None:
    return shutil.which(name) or shutil.which(name, path=HOMEBREW_BIN)


# Written here, read by hammerspoon/gm.lua and wox/plugins/single-file/gm.py.
CACHE_PATH = Path.home() / ".cache" / "grigoryvp-gm" / "projects.json"
# Written here and by hammerspoon/gm.lua, read by wox/plugins/single-file/gm.py.
LOG_PATH = CACHE_PATH.parent / "gm.log"
LOG_MAX_BYTES = 1024 * 1024


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
        # git merge prints conflicts to stdout.
        output = (stderr or stdout).decode().strip()
        report(f"{Path(args[0]).name} failed: {output}")
        return None
    return stdout.decode()


# Returns the project count, None on failure.
async def fetch_github(gh: str) -> int | None:
    # --jq flattens pages: plain --paginate prints one JSON array per page.
    output = await run_cli(
        gh,
        "api",
        "user/repos?affiliation=owner,collaborator,organization_member&per_page=100",
        "--paginate",
        "--jq",
        ".[].full_name",
    )
    if output is None:
        return None
    paths = output.split()
    update_cache("github.com", paths)
    return len(paths)


async def fetch_gitlab(glab: str) -> int | None:
    # Unlike gh, glab merges pages into a single JSON array.
    output = await run_cli(
        glab,
        "api",
        "projects?membership=true&simple=true&per_page=100",
        "--paginate",
    )
    if output is None:
        return None
    paths = [p["path_with_namespace"] for p in json.loads(output)]
    update_cache("gitlab.com", paths)
    return len(paths)


REFRESH_INTERVAL_SEC = 10 * 60


# Checks only for a token locally: `auth status` calls the API, and offline
# reports a valid token as invalid.
async def has_token(*args: str) -> bool:
    proc = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    stdout, _ = await proc.communicate()
    # glab prints nothing and succeeds without a token.
    return proc.returncode == 0 and bool(stdout.strip())


# Returns the outcome for the status line. A CLI that isn't logged in isn't
# an error, so it's skipped without reporting.
async def fetch_host(
    host: str,
    cli: str | None,
    token_args: list[str],
    fetch: Callable[[str], Awaitable[int | None]],
) -> str:
    if cli is None:
        return f"{host} no CLI"
    if not await has_token(cli, *token_args):
        print(f"{host}: not authenticated")
        return f"{host} not authenticated"
    count = await fetch(cli)
    return f"{host} failed" if count is None else f"{host} {count} projects"


async def fetch_projects(gh: str | None, glab: str | None) -> str:
    results = await asyncio.gather(
        fetch_host(
            "github.com",
            gh,
            ["auth", "token", "--hostname", "github.com"],
            fetch_github,
        ),
        fetch_host(
            "gitlab.com",
            glab,
            ["config", "get", "token", "--host", "gitlab.com"],
            fetch_gitlab,
        ),
        # An exception in one fetch must not stop the refresh loop.
        return_exceptions=True,
    )
    outcomes = []
    for result in results:
        if isinstance(result, BaseException):
            report(f"fetch failed: {result!r}")
        else:
            outcomes.append(result)
    return ", ".join(outcomes)


async def refresh_projects(gh: str | None, glab: str | None) -> None:
    while True:
        await fetch_projects(gh, glab)
        await asyncio.sleep(REFRESH_INTERVAL_SEC)


CLONES_DIR = Path.home() / "git"

# Characters GitHub keeps in repo names; no leading "-", which gh would take
# for an option. Same as in wox/plugins/single-file/gm.py.
REPO_NAME = re.compile(r"[A-Za-z0-9_.][A-Za-z0-9_.-]*")
# Branch of the first worktree of a project made by gm create.
CREATE_BRANCH = "new"


# The CLIs clone with the protocol and credentials from their own config.
async def ensure_clone(host: str, path: str, cli: str | None) -> Path | None:
    repo = CLONES_DIR / host / path
    if repo.exists():
        return repo
    if cli is None:
        report(f"no CLI to clone from {host}")
        return None
    repo.parent.mkdir(parents=True, exist_ok=True)
    await status.add_log("progress", f"cloning {path}")
    if await run_cli(cli, "repo", "clone", path, str(repo)) is None:
        return None
    return repo


async def git_succeeds(*args: str) -> bool:
    proc = await asyncio.create_subprocess_exec(
        "git",
        *args,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.DEVNULL,
    )
    return await proc.wait() == 0


WORKTREES_DIR = Path.home() / "Documents"


# Clones are the dirs with .git under ~/git; their worktrees live elsewhere.
def find_clones(root: Path = CLONES_DIR) -> list[Path]:
    if (root / ".git").exists():
        return [root]
    if not root.is_dir():
        return []
    return [clone for child in sorted(root.iterdir()) for clone in find_clones(child)]


# (path, branch) pairs of linked worktrees; branch is None when detached.
# Git lists the clone itself first, but clones are only a cache to make
# worktrees from.
async def list_worktrees(repo: Path) -> list[tuple[Path, str | None]]:
    # A worktree whose directory was deleted by hand still holds its branch
    # until pruned.
    if await run_cli("git", "-C", str(repo), "worktree", "prune") is None:
        return []
    output = await run_cli("git", "-C", str(repo), "worktree", "list", "--porcelain")
    if output is None:
        return []
    worktrees = []
    for entry in output.strip().split("\n\n"):
        fields = dict(line.partition(" ")[::2] for line in entry.splitlines())
        branch = fields.get("branch", "").removeprefix("refs/heads/") or None
        worktrees.append((Path(fields["worktree"]), branch))
    return worktrees[1:]


# For hammerspoon/gm.lua.
async def collect_worktrees() -> list[dict[str, str]]:
    clones = find_clones()
    worktrees = []
    for clone, entries in zip(
        clones, await asyncio.gather(*map(list_worktrees, clones))
    ):
        project = str(clone.relative_to(CLONES_DIR))
        for path, branch in entries:
            # Lua can't tell a JSON null from a missing key anyway.
            worktree = {"path": str(path), "project": project}
            if branch is not None:
                worktree["branch"] = branch
            worktrees.append(worktree)
    return worktrees


# The clone and branch of a worktree picked in the UI. The path comes over
# RPC, so only worktrees of clones in ~/git qualify.
async def locate_worktree(worktree: Path) -> tuple[Path, str | None] | None:
    clones = find_clones()
    for clone, entries in zip(
        clones, await asyncio.gather(*map(list_worktrees, clones))
    ):
        for path, branch in entries:
            if path == worktree:
                return clone, branch
    return None


async def count_uncommitted(worktree: Path) -> int | None:
    output = await run_cli("git", "-C", str(worktree), "status", "--porcelain")
    return None if output is None else len(output.splitlines())


# A description of what removal would lose, or None if nothing.
async def unsaved_work(worktree: Path) -> str | None:
    changes = await count_uncommitted(worktree)
    # Commits that no remote-tracking branch has, as of the last fetch.
    unpushed = await run_cli(
        "git", "-C", str(worktree), "rev-list", "--count", "HEAD", "--not", "--remotes"
    )
    if changes is None or unpushed is None:
        return "unknown state, git failed"
    reasons = []
    if changes:
        reasons.append(f"{changes} uncommitted changes")
    if int(unpushed):
        reasons.append(f"{int(unpushed)} unpushed commits")
    return ", ".join(reasons) or None


async def find_worktree(repo: Path, branch: str) -> Path | None:
    for path, worktree_branch in await list_worktrees(repo):
        if worktree_branch == branch:
            return path
    return None


# Plain git doesn't see the CLI's credentials for https remotes, so pass the
# CLI as the only credential helper, the way `gh repo clone` does.
def credential_args(cli: str | None) -> list[str]:
    if cli is None:
        return []
    helper = f"!{shlex.quote(cli)} auth git-credential"
    return ["-c", "credential.helper=", "-c", f"credential.helper={helper}"]


async def create_worktree(repo: Path, branch: str, cli: str | None) -> Path | None:
    # Also rejects names starting with "-" that git would take for options.
    if not await git_succeeds("check-ref-format", "--branch", branch):
        report(f"invalid branch name: {branch}")
        return None
    git = ["git", "-C", str(repo)]
    await status.add_log("progress", f"fetching {repo.name}")
    if await run_cli(*git, *credential_args(cli), "fetch") is None:
        return None
    # A fresh clone holds the default branch, and git checks out a branch in
    # one worktree only.
    if await run_cli(*git, "switch", "--detach") is None:
        return None
    worktree = WORKTREES_DIR / f"{repo.name}--{branch.replace('/', '-')}"
    if await git_succeeds("-C", str(repo), "show-ref", "-q", f"refs/heads/{branch}"):
        args = [str(worktree), branch]
    elif await git_succeeds(
        "-C", str(repo), "show-ref", "-q", f"refs/remotes/origin/{branch}"
    ):
        args = ["--track", "-b", branch, str(worktree), f"origin/{branch}"]
    else:
        default = await run_cli(
            *git, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"
        )
        if default is None:
            return None
        # Otherwise the new branch would track the default one, and `git push`
        # would target it.
        args = ["--no-track", "-b", branch, str(worktree), default.strip()]
    if await run_cli(*git, "worktree", "add", *args) is None:
        return None
    # Same form as `git worktree list` gives, since tabs are matched by it.
    return worktree.resolve()


# Returns why the worktree's branch wasn't merged and pushed, or None.
async def merge_to_default(
    clone: Path, worktree: Path, branch: str | None, cli: str | None
) -> str | None:
    if branch is None:
        return "detached HEAD, no branch to merge"
    changes = await count_uncommitted(worktree)
    if changes is None:
        return "unknown state, git failed"
    if changes:
        return f"{changes} uncommitted changes"
    git = ["git", "-C", str(clone)]
    auth = credential_args(cli)
    await status.add_log("progress", f"fetching {clone.name}")
    if await run_cli(*git, *auth, "fetch") is None:
        return "fetch failed, see gm status"
    default = await run_cli(*git, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
    if default is None:
        return "no default branch, see gm status"
    default = default.strip()
    # The merge runs in the clone: it is detached and otherwise unused, while
    # the local default branch may be checked out in some worktree.
    if await run_cli(*git, "switch", "--detach", default) is None:
        return f"switch to {default} failed, see gm status"
    # Detached HEAD would make git say "into HEAD" in the default message.
    message = f"Merge branch '{branch}'"
    if await run_cli(*git, "merge", "-m", message, branch) is None:
        await git_succeeds("-C", str(clone), "merge", "--abort")
        return f"merge into {default} failed, see gm status"
    default_name = default.removeprefix("origin/")
    await status.add_log("progress", f"pushing {branch} to {default_name}")
    target = f"HEAD:refs/heads/{default_name}"
    if await run_cli(*git, *auth, "push", "origin", target) is None:
        return "push failed, see gm status"
    return None


# All matches run, e.g. for a Python backend with a JS frontend.
INSTALL_COMMANDS = [
    ("uv.lock", "uv sync"),
    ("poetry.lock", "poetry install"),
    ("pnpm-lock.yaml", "pnpm i"),
    ("package-lock.json", "npm ci"),
    ("yarn.lock", "yarn install"),
    ("bun.lock", "bun install"),
]


def install_command(worktree: Path) -> str | None:
    commands = [cmd for name, cmd in INSTALL_COMMANDS if (worktree / name).exists()]
    return " && ".join(commands) or None


def call_hammerspoon(command: str, **params) -> None:
    body = json.dumps({"command": command, **params}).encode()
    urllib.request.urlopen(HAMMERSPOON_URL, data=body, timeout=5).close()


@dataclass
class Command:
    name: str
    failed: bool = False


# The user's command being run. Its failures go to the status line, unlike
# those of the periodic refresh, which would show an error all the time
# while offline.
_command: contextvars.ContextVar[Command | None] = contextvars.ContextVar(
    "command", default=None
)


# Only the first failure is shown: later ones are usually its consequences.
def fail_command(text: str) -> None:
    command = _command.get()
    if command is None or command.failed:
        return
    command.failed = True
    run_in_background(status.add_log("error", f"{command.name}: {text}"))


async def finish_command(details: str = "") -> None:
    command = _command.get()
    if command is not None and not command.failed:
        text = f"{command.name}: {details}" if details else command.name
        await status.add_log("success", text)


# Background work has no caller to return errors to, so they go to the
# Script Console, to a log that `gm status` shows and to the status line.
def report(message: str) -> None:
    print(message)
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    if LOG_PATH.exists() and LOG_PATH.stat().st_size > LOG_MAX_BYTES:
        os.replace(LOG_PATH, LOG_PATH.with_suffix(".log.1"))
    # One entry per line, so readers can take the last lines.
    entry = " | ".join(message.splitlines())
    with LOG_PATH.open("a") as log:
        log.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {entry}\n")
    fail_command(entry)


# iTerm suspends an AppleScript `invoke API expression` until the called RPC
# returns, queueing all other AppleEvents, and an RPC that calls the iTerm API
# meanwhile never returns. So RPCs only schedule their work.
_background: set[asyncio.Task] = set()


def _finish_background(task: asyncio.Task) -> None:
    _background.discard(task)
    # Nobody awaits these tasks, so their exceptions would otherwise be lost.
    if task.cancelled():
        return
    error = task.exception()
    if error is not None:
        traceback.print_exception(error)
        report(f"failed: {error!r}")


def run_in_background(coro) -> None:
    task = asyncio.create_task(coro)
    _background.add(task)
    task.add_done_callback(_finish_background)


def run_command(name: str, coro) -> None:
    # The task and its done callback copy the current context, so the
    # command is seen by everything it runs, unhandled exceptions included.
    token = _command.set(Command(name))
    try:
        run_in_background(coro)
    finally:
        _command.reset(token)


async def main(connection):
    status.init(connection)
    app = await iterm2.async_get_app(connection)
    gh = find_cli("gh")
    glab = find_cli("glab")
    print(f"gh: {gh}, glab: {glab}")
    run_in_background(refresh_projects(gh, glab))
    clone_clis = {"github.com": gh, "gitlab.com": glab}

    async def find_tabs(worktree: Path) -> list[iterm2.Tab]:
        tabs = []
        for window in app.windows:
            for tab in window.tabs:
                if await tab.async_get_variable("user.worktree") == str(worktree):
                    tabs.append(tab)
        return tabs

    # Returns the top session; the bottom one is the shift-cmd-d split.
    async def create_tab(worktree: Path) -> iterm2.Session | None:
        profile = iterm2.LocalWriteOnlyProfile()
        profile.set_initial_directory_mode(
            iterm2.InitialWorkingDirectory.INITIAL_WORKING_DIRECTORY_CUSTOM
        )
        profile.set_custom_directory(str(worktree))
        window = app.current_window
        if window is None:
            window = await iterm2.Window.async_create(
                connection, profile_customizations=profile
            )
            tab = window.current_tab if window else None
        else:
            tab = await window.async_create_tab(profile_customizations=profile)
        session = tab.current_session if tab else None
        if window is None or tab is None or session is None:
            return None
        await split_with_bottom_pane(
            window, tab, session, profile_customizations=profile
        )
        # The title is an interpolated string, but repo and branch names
        # can't contain the backslash that starts interpolation.
        await tab.async_set_title(worktree.name)
        # A tab variable rather than a session one, so splits share it.
        await tab.async_set_variable("user.worktree", str(worktree))
        return session

    # GM never types into a tab it didn't just create: something may be
    # running there.
    async def open_tab(worktree: Path, command: str | None):
        tabs = await find_tabs(worktree)
        if tabs:
            await tabs[0].async_activate()
        else:
            session = await create_tab(worktree)
            if session is None:
                report(f"failed to open a tab for {worktree}")
                return
            if command is not None:
                # The shell reads it once started; no newline, so the user
                # reviews it and presses Enter.
                await session.async_send_text(command)
            # Selects the tab too; focus goes where the command is.
            await session.async_activate()
        # The launcher or Hammerspoon is frontmost at this point.
        await app.async_activate(ignoring_other_apps=True)

    async def new_worktree(project: str, branch: str):
        host, path = project.split("/", 1)
        cli = clone_clis.get(host)
        repo = await ensure_clone(host, path, cli)
        if repo is None:
            return
        # Git allows one worktree per branch, so an existing one is reused
        # without a fetch, and its dependencies are presumably installed.
        worktree = await find_worktree(repo, branch)
        if worktree is not None:
            await open_tab(worktree, None)
        else:
            worktree = await create_worktree(repo, branch, cli)
            if worktree is None:
                return
            await open_tab(worktree, install_command(worktree))
        await finish_command()

    async def create_project(name: str):
        if gh is None:
            report("no gh to create a repo")
            return
        if not REPO_NAME.fullmatch(name):
            report(f"invalid repo name: {name}")
            return
        await status.add_log("progress", f"creating {name}")
        output = await run_cli(gh, "repo", "create", name, "--private", "--add-readme")
        if output is None:
            return
        # Without a TTY gh prints only the URL: https://github.com/<owner>/<name>.
        path = "/".join(output.strip().split("/")[-2:])
        # So that gm new lists it before the periodic refresh.
        run_in_background(fetch_github(gh))
        await new_worktree(f"github.com/{path}", CREATE_BRANCH)

    # urlopen() blocks and would stall the API connection.
    async def show_worktrees(command: str, **params):
        worktrees = await collect_worktrees()
        await asyncio.to_thread(
            call_hammerspoon, command, worktrees=worktrees, **params
        )

    async def show_merge():
        window = app.current_window
        tab = window.current_tab if window else None
        active = await tab.async_get_variable("user.worktree") if tab else None
        # Lua can't tell a JSON null from a missing key anyway.
        await show_worktrees("gm_merge", **({"active": active} if active else {}))

    async def remove_worktree(worktree: Path, force: bool):
        found = await locate_worktree(worktree)
        if found is None:
            report(f"not a removable worktree: {worktree}")
            return
        clone, _ = found
        if not force:
            reasons = await unsaved_work(worktree)
            if reasons is not None:
                await asyncio.to_thread(
                    call_hammerspoon,
                    "gm_rm_confirm",
                    worktree=str(worktree),
                    reasons=reasons,
                )
                return
        args = ["--force"] if force else []
        git = ["git", "-C", str(clone), "worktree", "remove", *args, str(worktree)]
        if await run_cli(*git) is None:
            return
        for tab in await find_tabs(worktree):
            # Without force iTerm still asks if something runs there.
            await tab.async_close()
        await finish_command()

    @iterm2.RPC
    async def gm_new():
        # urlopen() blocks and would stall the API connection.
        run_in_background(asyncio.to_thread(call_hammerspoon, "gm_new"))

    # Called by hammerspoon/gm.lua with "<host>/<path>" of the picked project.
    @iterm2.RPC
    async def gm_new_done(project: str, branch: str):
        # Same name as the worktree directory.
        name = f"{Path(project).name}--{branch.replace('/', '-')}"
        run_command(f"gm NEW {name}", new_worktree(project, branch))

    # Called by wox/plugins/single-file/gm.py with the new repo's name.
    @iterm2.RPC
    async def gm_create(name: str):
        run_command(f"gm CREATE {name}", create_project(name))

    async def refresh_now():
        await status.add_log("progress", "refreshing projects")
        await finish_command(await fetch_projects(gh, glab))

    # Called by wox/plugins/single-file/gm.py; no UI, results land in the cache.
    @iterm2.RPC
    async def gm_refresh():
        run_command("gm REFRESH", refresh_now())

    @iterm2.RPC
    async def gm_go():
        run_in_background(show_worktrees("gm_go"))

    async def go_worktree(worktree: Path):
        await open_tab(worktree, None)
        await finish_command()

    # Called by hammerspoon/gm.lua with the path of the picked worktree.
    @iterm2.RPC
    async def gm_go_done(worktree: str):
        run_command(f"gm GO {Path(worktree).name}", go_worktree(Path(worktree)))

    async def merge_worktree(worktree: Path):
        found = await locate_worktree(worktree)
        if found is None:
            report(f"not a mergeable worktree: {worktree}")
            return
        clone, branch = found
        host = clone.relative_to(CLONES_DIR).parts[0]
        reason = await merge_to_default(clone, worktree, branch, clone_clis.get(host))
        if reason is not None:
            # A no-op if a reported git failure is the reason.
            fail_command(reason)
            await asyncio.to_thread(
                call_hammerspoon,
                "gm_merge_failed",
                worktree=str(worktree),
                reason=reason,
            )
            return
        # Pushed, so nothing is unsaved and no confirmation shows up. Removal
        # also logs the command's success.
        await remove_worktree(worktree, force=False)

    @iterm2.RPC
    async def gm_merge():
        run_in_background(show_merge())

    # Called by hammerspoon/gm.lua with the path of the picked worktree.
    @iterm2.RPC
    async def gm_merge_done(worktree: str):
        run_command(f"gm MERGE {Path(worktree).name}", merge_worktree(Path(worktree)))

    @iterm2.RPC
    async def gm_rm():
        run_in_background(show_worktrees("gm_rm"))

    # Called by hammerspoon/gm.lua with the path of the picked worktree.
    @iterm2.RPC
    async def gm_rm_done(worktree: str):
        run_command(
            f"gm RM {Path(worktree).name}", remove_worktree(Path(worktree), force=False)
        )

    # Called by hammerspoon/gm.lua once removal with unsaved work is confirmed.
    @iterm2.RPC
    async def gm_rm_force(worktree: str):
        run_command(
            f"gm RM {Path(worktree).name}", remove_worktree(Path(worktree), force=True)
        )

    await gm_new.async_register(connection)
    await gm_new_done.async_register(connection)
    await gm_create.async_register(connection)
    await gm_refresh.async_register(connection)
    await gm_go.async_register(connection)
    await gm_go_done.async_register(connection)
    await gm_merge.async_register(connection)
    await gm_merge_done.async_register(connection)
    await gm_rm.async_register(connection)
    await gm_rm_done.async_register(connection)
    await gm_rm_force.async_register(connection)


iterm2.run_forever(main)
