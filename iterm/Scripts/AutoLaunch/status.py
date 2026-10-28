#!/usr/bin/env python3
# iTerm Status Bar: a one-line log in the title of every iTerm window.
#
# Run by iTerm, it owns the titles and registers the status_add() RPC.
# Imported by other AutoLaunch scripts (gm.py), it provides add_log(), which
# calls that RPC, so the titles have a single owner across processes.
import asyncio
import sys
import time

import iterm2

EMOJI = {"progress": "⌛", "success": "✅", "error": "⚠️"}
EXPIRY_SEC = 60 * 60
RENDER_INTERVAL_SEC = 1
# A missing status must not stall the caller's workflow.
INVOKE_TIMEOUT_SEC = 2

_connection: iterm2.Connection | None = None


def init(connection: iterm2.Connection) -> None:
    global _connection
    _connection = connection


async def add_log(kind: str, text: str) -> None:
    if _connection is None:
        print(f"status {kind}: {text}")
        return
    # Escapes \ and ", so the text can't start \(...) interpolation.
    invocation = iterm2.util.invocation_string(
        "status_add", {"kind": kind, "text": text}
    )
    try:
        await iterm2.async_invoke_function(
            _connection, invocation, timeout=INVOKE_TIMEOUT_SEC
        )
    except Exception as error:
        print(f"status {kind}: {text}: {error!r}")


def format_age(seconds: float) -> str:
    # Entries expire within an hour, so no hours.
    if seconds < 60:
        return f"{int(seconds)}s"
    return f"{int(seconds // 60)}m"


# Shown without entries.
IDLE_TITLE = f"iTerm2 status plugin on Python {sys.version}"

# Keeps the render loop from being garbage collected.
_render_task: asyncio.Task | None = None


async def main(connection):
    global _render_task
    app = await iterm2.async_get_app(connection)
    # (kind, text, monotonic time) of the latest entry.
    entry: tuple[str, str, float] | None = None
    changed = asyncio.Event()

    def title() -> str:
        nonlocal entry
        if entry is not None and time.monotonic() - entry[2] > EXPIRY_SEC:
            entry = None
        if entry is None:
            text = IDLE_TITLE
        else:
            kind, text, start = entry
            text = f"{EMOJI[kind]} {text}"
            if kind == "progress":
                text += f" ({format_age(time.monotonic() - start)})"
        # The window title is an interpolated string.
        return text.replace("\\", "\\\\")

    async def render():
        while True:
            # Cleared before reading the state, so a status_add() during the
            # pass isn't lost.
            changed.clear()
            current = title()
            # Each pass also covers windows opened since the previous one.
            for window in app.terminal_windows:
                try:
                    await window.async_set_title(current)
                except iterm2.RPCException as error:
                    # E.g. the window closed meanwhile.
                    print(f"failed to set the title: {error!r}")
            try:
                await asyncio.wait_for(changed.wait(), RENDER_INTERVAL_SEC)
            except TimeoutError:
                pass

    # Only updates the state: the render loop calls the iTerm API.
    @iterm2.RPC
    async def status_add(kind: str, text: str):
        nonlocal entry
        if kind not in EMOJI:
            raise ValueError(f"unknown kind: {kind}")
        entry = (kind, text, time.monotonic())
        changed.set()

    await status_add.async_register(connection)
    _render_task = asyncio.create_task(render())


# gm.py imports this file.
if __name__ == "__main__":
    iterm2.run_forever(main)
