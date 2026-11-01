#!/usr/bin/env python3
# Skill Manager (SM): symlinks skills from the git repos in ~/skills into the
# agents' skill directories and updates them with `git pull`. Called via
# AppleScript `invoke API expression` by the Wox plugin
# (wox/plugins/single-file/sm.py).
import asyncio
import os
import re
from pathlib import Path

import iterm2

# status.py and workflow.py are in the same AutoLaunch dir, which Python puts
# on sys.path.
import status
import workflow
from workflow import (
    credential_args,
    find_cli,
    finish_command,
    log,
    report,
    run_command,
)

SKILLS_DIR = Path.home() / "skills"
AGENT_DIRS = [
    Path.home() / ".claude" / "skills",
    # Codex, experimental.
    Path.home() / ".agents" / "skills",
]
LOG_PATH = Path.home() / ".cache" / "grigoryvp-sm" / "sm.log"

# A pull runs new code in the agents, so only the user's own repos are pulled.
OWN_REMOTE = re.compile(
    r"(https://github\.com/|git@github\.com:|ssh://git@github\.com/)"
    r"grigoryvp/[A-Za-z0-9_.-]+/?"
)


def sources() -> list[Path]:
    if not SKILLS_DIR.is_dir():
        return []
    return sorted(
        p for p in SKILLS_DIR.iterdir() if p.is_dir() and not p.name.startswith(".")
    )


def skills(source: Path) -> list[Path]:
    return sorted(
        p
        for p in source.iterdir()
        if p.is_dir() and not p.name.startswith(".") and (p / "SKILL.md").is_file()
    )


def home_relative(path: Path) -> str:
    return f"~/{path.relative_to(Path.home())}"


# Links into ~/skills are SM's own; anything else belongs to the user or the
# agent.
def own_target(link: Path) -> Path | None:
    if not link.is_symlink():
        return None
    target = Path(os.path.normpath(link.parent / os.readlink(link)))
    return target if target.is_relative_to(SKILLS_DIR) else None


def sync() -> str:
    wanted: dict[str, Path] = {}
    warnings = []
    for source in sources():
        for skill in skills(source):
            if skill.name in wanted:
                warnings.append(f"skipped {skill.name} ({source.name})")
            else:
                wanted[skill.name] = skill
    added: set[str] = set()
    removed: set[str] = set()
    for agent_dir in AGENT_DIRS:
        agent_dir.mkdir(parents=True, exist_ok=True)
        for entry in list(agent_dir.iterdir()):
            target = own_target(entry)
            if target is not None and wanted.get(entry.name) != target:
                entry.unlink()
                removed.add(entry.name)
        for name, skill in wanted.items():
            link = agent_dir / name
            if own_target(link) is not None:
                continue
            if link.exists() or link.is_symlink():
                warnings.append(f"skipped {name} (taken in {home_relative(agent_dir)})")
                continue
            # Absolute, since ~/.claude is itself a symlink into dotfiles.
            link.symlink_to(skill)
            added.add(name)
    for warning in warnings:
        log(f"sm sync: {warning}")
    # A skill re-linked to another source is both removed and added.
    summary = f"{len(wanted)} skills, +{len(added)} -{len(removed)}"
    return ", ".join([summary, *warnings])


async def git(source: Path, *args: str) -> tuple[bool, str]:
    proc = await asyncio.create_subprocess_exec(
        "git",
        "-C",
        str(source),
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        # No TTY to answer a prompt, so fail instead of waiting forever.
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
    )
    stdout, stderr = await proc.communicate()
    if proc.returncode != 0:
        return False, stderr.decode().strip()
    return True, stdout.decode().strip()


# Returns True if pulled, False on failure, None if not a git repo.
async def pull(source: Path, gh: str | None) -> bool | None:
    ok, toplevel = await git(source, "rev-parse", "--show-toplevel")
    # A directory inside another repo is not a source repo either.
    if not ok or Path(toplevel) != source.resolve():
        return None
    ok, branch = await git(source, "symbolic-ref", "--short", "HEAD")
    if not ok:
        report(f"{source.name}: detached HEAD")
        return False
    ok, remote = await git(source, "config", "--get", f"branch.{branch}.remote")
    if not ok:
        report(f"{source.name}: {branch} has no upstream")
        return False
    # Applies insteadOf, so the check sees the URL git will use.
    ok, url = await git(source, "remote", "get-url", remote)
    if not ok:
        report(f"{source.name}: {url}")
        return False
    if not OWN_REMOTE.fullmatch(url.removesuffix(".git")):
        report(f"{source.name}: {url} is not on github.com/grigoryvp")
        return False
    await status.add_log("progress", f"git pull {source.name}")
    ok, output = await git(source, *credential_args(gh), "pull", "--ff-only")
    if not ok:
        report(f"{source.name}: git pull failed: {output}")
        return False
    return True


async def pull_all(gh: str | None) -> str:
    all_sources = sources()
    results = await asyncio.gather(*(pull(source, gh) for source in all_sources))
    pulled = sum(1 for result in results if result)
    not_git = [s.name for s, result in zip(all_sources, results) if result is None]
    parts = [f"{pulled} pulled"]
    if not_git:
        parts.append(f"not git repos: {', '.join(not_git)}")
    return ", ".join(parts)


async def main(connection):
    workflow.init(connection, LOG_PATH)
    gh = find_cli("gh")
    print(f"gh: {gh}")

    async def sync_now():
        await finish_command(sync())

    async def pull_now():
        pulled = await pull_all(gh)
        # Also links the sources that pulled when others failed.
        await finish_command(f"{pulled}; {sync()}")

    @iterm2.RPC
    async def sm_sync():
        run_command("sm SYNC", sync_now())

    @iterm2.RPC
    async def sm_pull():
        run_command("sm PULL", pull_now())

    await sm_sync.async_register(connection)
    await sm_pull.async_register(connection)


iterm2.run_forever(main)
