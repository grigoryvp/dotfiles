#!/usr/bin/env python3
# Shared by the workflow scripts (gm.py, sm.py): command status, error
# reporting and background tasks. Each script runs in its own process, so
# this module's state is per script.
import asyncio
import contextvars
import os
import shlex
import shutil
import time
import traceback
from dataclasses import dataclass
from pathlib import Path

import iterm2

# In the same AutoLaunch dir, which Python puts on sys.path.
import status

# iTerm launched from the Dock may lack Homebrew in PATH.
HOMEBREW_BIN = "/opt/homebrew/bin"
LOG_MAX_BYTES = 1024 * 1024

_log_path: Path | None = None


def init(connection: iterm2.Connection, log_path: Path) -> None:
    global _log_path
    _log_path = log_path
    status.init(connection)


def find_cli(name: str) -> str | None:
    return shutil.which(name) or shutil.which(name, path=HOMEBREW_BIN)


@dataclass
class Command:
    name: str
    failed: bool = False


# The user's command being run. Its failures go to the status line, unlike
# those of periodic work, which would show an error all the time while
# offline.
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


# Returns the entry as written: one line, so readers can take the last lines.
def log(message: str) -> str:
    print(message)
    entry = " | ".join(message.splitlines())
    if _log_path is not None:
        _log_path.parent.mkdir(parents=True, exist_ok=True)
        if _log_path.exists() and _log_path.stat().st_size > LOG_MAX_BYTES:
            os.replace(_log_path, _log_path.with_suffix(".log.1"))
        with _log_path.open("a") as file:
            file.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {entry}\n")
    return entry


# Background work has no caller to return errors to, so they go to the
# Script Console, to a log that the Wox plugin's status shows and to the
# status line.
def report(message: str) -> None:
    fail_command(log(message))


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


async def run_cli(*args: str, env: dict[str, str] | None = None) -> str | None:
    proc = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env={**os.environ, **env} if env else None,
    )
    stdout, stderr = await proc.communicate()
    if proc.returncode != 0:
        # git merge prints conflicts to stdout.
        output = (stderr or stdout).decode().strip()
        report(f"{Path(args[0]).name} failed: {output}")
        return None
    return stdout.decode()


# Plain git doesn't see the CLI's credentials for https remotes, so pass the
# CLI as the only credential helper, the way `gh repo clone` does.
def credential_args(cli: str | None) -> list[str]:
    if cli is None:
        return []
    helper = f"!{shlex.quote(cli)} auth git-credential"
    return ["-c", "credential.helper=", "-c", f"credential.helper={helper}"]


# A module only; iTerm runs every AutoLaunch file, so this one exits at once.
if __name__ == "__main__":
    pass
