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


CLONES_DIR = Path.home() / "git"


# The CLIs clone with the protocol and credentials from their own config.
async def ensure_clone(host: str, path: str, cli: str | None) -> Path | None:
    repo = CLONES_DIR / host / path
    if repo.exists():
        return repo
    if cli is None:
        print(f"no CLI to clone from {host}")
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


async def find_worktree(repo: Path, branch: str) -> Path | None:
    output = await run_cli("git", "-C", str(repo), "worktree", "list", "--porcelain")
    if output is None:
        return None
    path = None
    for line in output.splitlines():
        if line.startswith("worktree "):
            path = Path(line.removeprefix("worktree "))
        elif line == f"branch refs/heads/{branch}":
            return path
    return None


async def ensure_worktree(repo: Path, branch: str, cli: str | None) -> Path | None:
    # Also rejects names starting with "-" that git would take for options.
    if not await git_succeeds("check-ref-format", "--branch", branch):
        print(f"invalid branch name: {branch}")
        return None
    git = ["git", "-C", str(repo)]
    # A worktree whose directory was deleted by hand still holds its branch
    # until pruned.
    if await run_cli(*git, "worktree", "prune") is None:
        return None
    # Git allows one worktree per branch, so reuse it, skipping the fetch.
    existing = await find_worktree(repo, branch)
    if existing is not None:
        return existing
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
    clone_clis = {"github.com": gh, "gitlab.com": glab}

    async def find_tab(worktree: Path) -> iterm2.Tab | None:
        for window in app.windows:
            for tab in window.tabs:
                if await tab.async_get_variable("user.worktree") == str(worktree):
                    return tab
        return None

    async def create_tab(worktree: Path) -> iterm2.Tab | None:
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
        if tab is None:
            return None
        # The title is an interpolated string, but repo and branch names
        # can't contain the backslash that starts interpolation.
        await tab.async_set_title(worktree.name)
        # A tab variable rather than a session one, so splits share it.
        await tab.async_set_variable("user.worktree", str(worktree))
        return tab

    async def open_tab(worktree: Path):
        tab = await find_tab(worktree) or await create_tab(worktree)
        if tab is None:
            print(f"failed to open a tab for {worktree}")
            return
        await tab.async_activate()
        # The launcher or Hammerspoon is frontmost at this point.
        await app.async_activate(ignoring_other_apps=True)

    async def new_worktree(project: str, branch: str):
        host, path = project.split("/", 1)
        cli = clone_clis.get(host)
        repo = await ensure_clone(host, path, cli)
        if repo is None:
            return
        worktree = await ensure_worktree(repo, branch, cli)
        if worktree is not None:
            await open_tab(worktree)

    @iterm2.RPC
    async def gm_new():
        # urlopen() blocks and would stall the API connection.
        run_in_background(asyncio.to_thread(call_hammerspoon, "gm_new"))

    # Called by hammerspoon/gm.lua with "<host>/<path>" of the picked project.
    @iterm2.RPC
    async def gm_new_done(project: str, branch: str):
        run_in_background(new_worktree(project, branch))

    await gm_new.async_register(connection)
    await gm_new_done.async_register(connection)


iterm2.run_forever(main)
