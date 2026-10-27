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
import shlex
import shutil
import time
import traceback
import urllib.request
from pathlib import Path

import iterm2

# split.py is in the same AutoLaunch dir, which Python puts on sys.path.
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
        report(f"{Path(args[0]).name} failed: {stderr.decode().strip()}")
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
                report(f"fetch failed: {result!r}")
        await asyncio.sleep(REFRESH_INTERVAL_SEC)


CLONES_DIR = Path.home() / "git"


# The CLIs clone with the protocol and credentials from their own config.
async def ensure_clone(host: str, path: str, cli: str | None) -> Path | None:
    repo = CLONES_DIR / host / path
    if repo.exists():
        return repo
    if cli is None:
        report(f"no CLI to clone from {host}")
        return None
    repo.parent.mkdir(parents=True, exist_ok=True)
    print(f"cloning {host}/{path}")
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


# (path, branch) pairs, the clone itself included; branch is None when
# detached.
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
    return worktrees


# For hammerspoon/gm.lua. Git lists the clone itself first; gm rm skips it,
# since `git worktree remove` refuses the main worktree.
async def collect_worktrees(with_clones: bool) -> list[dict[str, str]]:
    clones = find_clones()
    worktrees = []
    for clone, entries in zip(
        clones, await asyncio.gather(*map(list_worktrees, clones))
    ):
        project = str(clone.relative_to(CLONES_DIR))
        for path, branch in entries if with_clones else entries[1:]:
            # Lua can't tell a JSON null from a missing key anyway.
            worktree = {"path": str(path), "project": project}
            if branch is not None:
                worktree["branch"] = branch
            worktrees.append(worktree)
    return worktrees


# The clone a removable worktree belongs to. The path comes over RPC, so
# only worktrees of clones in ~/git qualify.
async def find_clone_of(worktree: Path) -> Path | None:
    clones = find_clones()
    for clone, entries in zip(
        clones, await asyncio.gather(*map(list_worktrees, clones))
    ):
        if any(path == worktree for path, _ in entries[1:]):
            return clone
    return None


# A description of what removal would lose, or None if nothing.
async def unsaved_work(worktree: Path) -> str | None:
    git = ["git", "-C", str(worktree)]
    status = await run_cli(*git, "status", "--porcelain")
    # Commits that no remote-tracking branch has, as of the last fetch.
    unpushed = await run_cli(*git, "rev-list", "--count", "HEAD", "--not", "--remotes")
    if status is None or unpushed is None:
        return "unknown state, git failed"
    reasons = []
    changes = len(status.splitlines())
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


async def create_worktree(repo: Path, branch: str, cli: str | None) -> Path | None:
    # Also rejects names starting with "-" that git would take for options.
    if not await git_succeeds("check-ref-format", "--branch", branch):
        report(f"invalid branch name: {branch}")
        return None
    git = ["git", "-C", str(repo)]
    # Plain git doesn't see the CLI's credentials for https remotes, so pass
    # the CLI as the only credential helper, the way `gh repo clone` does.
    auth = []
    if cli is not None:
        helper = f"!{shlex.quote(cli)} auth git-credential"
        auth = ["-c", "credential.helper=", "-c", f"credential.helper={helper}"]
    if await run_cli(*git, *auth, "fetch") is None:
        return None
    worktree = WORKTREES_DIR / f"{repo.name}-{branch.replace('/', '-')}"
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


# Background work has no caller to return errors to, so they go to the
# Script Console and to a log that `gm status` shows.
def report(message: str) -> None:
    print(message)
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    if LOG_PATH.exists() and LOG_PATH.stat().st_size > LOG_MAX_BYTES:
        os.replace(LOG_PATH, LOG_PATH.with_suffix(".log.1"))
    # One entry per line, so readers can take the last lines.
    entry = " | ".join(message.splitlines())
    with LOG_PATH.open("a") as log:
        log.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {entry}\n")


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


async def main(connection):
    app = await iterm2.async_get_app(connection)
    gh = find_cli("gh")
    glab = find_cli("glab")
    print(f"gh: {gh}, glab: {glab}")
    run_in_background(refresh_projects(gh, glab))
    clone_clis = {"github.com": gh, "gitlab.com": glab}

    async def find_tab(worktree: Path) -> iterm2.Tab | None:
        for window in app.windows:
            for tab in window.tabs:
                if await tab.async_get_variable("user.worktree") == str(worktree):
                    return tab
        return None

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
        tab = await find_tab(worktree)
        if tab is not None:
            await tab.async_activate()
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
        command = None
        if worktree is None:
            worktree = await create_worktree(repo, branch, cli)
            if worktree is None:
                return
            command = install_command(worktree)
        await open_tab(worktree, command)

    # urlopen() blocks and would stall the API connection.
    async def show_worktrees(command: str, with_clones: bool):
        worktrees = await collect_worktrees(with_clones)
        await asyncio.to_thread(call_hammerspoon, command, worktrees=worktrees)

    async def remove_worktree(worktree: Path, force: bool):
        clone = await find_clone_of(worktree)
        if clone is None:
            report(f"not a removable worktree: {worktree}")
            return
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
        tab = await find_tab(worktree)
        if tab is not None:
            # Without force iTerm still asks if something runs there.
            await tab.async_close()

    @iterm2.RPC
    async def gm_new():
        # urlopen() blocks and would stall the API connection.
        run_in_background(asyncio.to_thread(call_hammerspoon, "gm_new"))

    # Called by hammerspoon/gm.lua with "<host>/<path>" of the picked project.
    @iterm2.RPC
    async def gm_new_done(project: str, branch: str):
        run_in_background(new_worktree(project, branch))

    @iterm2.RPC
    async def gm_go():
        run_in_background(show_worktrees("gm_go", with_clones=True))

    # Called by hammerspoon/gm.lua with the path of the picked worktree.
    @iterm2.RPC
    async def gm_go_done(worktree: str):
        run_in_background(open_tab(Path(worktree), None))

    @iterm2.RPC
    async def gm_rm():
        run_in_background(show_worktrees("gm_rm", with_clones=False))

    # Called by hammerspoon/gm.lua with the path of the picked worktree.
    @iterm2.RPC
    async def gm_rm_done(worktree: str):
        run_in_background(remove_worktree(Path(worktree), force=False))

    # Called by hammerspoon/gm.lua once removal with unsaved work is confirmed.
    @iterm2.RPC
    async def gm_rm_force(worktree: str):
        run_in_background(remove_worktree(Path(worktree), force=True))

    await gm_new.async_register(connection)
    await gm_new_done.async_register(connection)
    await gm_go.async_register(connection)
    await gm_go_done.async_register(connection)
    await gm_rm.async_register(connection)
    await gm_rm_done.async_register(connection)
    await gm_rm_force.async_register(connection)


iterm2.run_forever(main)
