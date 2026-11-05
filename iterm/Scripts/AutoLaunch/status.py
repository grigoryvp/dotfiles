#!/usr/bin/env python3
# iTerm Status Bar: a one-line log in the title of every iTerm window.
#
# Run by iTerm, it owns the titles and registers the status_add() RPC.
# Imported by other AutoLaunch scripts (gm.py), it provides add_log(), which
# calls that RPC, so the titles have a single owner across processes.
import asyncio
import json
import sys
import time
import urllib.request

import iterm2

EMOJI = {"progress": "⌛", "success": "✅", "error": "⚠️"}
PROGRESS_INTERVAL_SEC = 1
# Steps take less, so a longer one has hung and needs no ticking.
PROGRESS_TICK_SEC = 60
RESULT_EXPIRY_SEC = 10 * 60
# A missing status must not stall the caller's workflow.
INVOKE_TIMEOUT_SEC = 2
# Hammerspoon draws the status next to the notch, see specs/notch.spec.md.
HAMMERSPOON_URL = "http://localhost:2020"
HAMMERSPOON_TIMEOUT_SEC = 1

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


# Shown without entries.
IDLE_TITLE = f"iTerm2 status plugin on Python {sys.version}"

# Keep the loops from being garbage collected.
_render_task: asyncio.Task | None = None
_notch_task: asyncio.Task | None = None


def post_to_notch(kind: str, text: str) -> None:
    body = json.dumps({"command": "notch_status", "kind": kind, "text": text})
    request = urllib.request.Request(HAMMERSPOON_URL, data=body.encode())
    try:
        urllib.request.urlopen(request, timeout=HAMMERSPOON_TIMEOUT_SEC).close()
    except OSError as error:
        print(f"failed to post the status to the notch: {error!r}")


async def main(connection):
    global _render_task, _notch_task
    app = await iterm2.async_get_app(connection)
    # (kind, text, monotonic time) of the latest entry.
    entry: tuple[str, str, float] | None = None
    changed = asyncio.Event()
    notch_changed = asyncio.Event()

    # The title and the seconds until it changes, None if it doesn't.
    def title() -> tuple[str, float | None]:
        nonlocal entry
        text = IDLE_TITLE
        wait: float | None = None
        if entry is not None:
            kind, entry_text, start = entry
            age = time.monotonic() - start
            if kind == "progress" and age < PROGRESS_TICK_SEC:
                text = f"{EMOJI[kind]} {entry_text} ({int(age)}s)"
                wait = PROGRESS_INTERVAL_SEC
            elif kind == "progress":
                # Stays until the next entry.
                text = f"{EMOJI[kind]} {entry_text} (>{PROGRESS_TICK_SEC // 60}m)"
            elif age < RESULT_EXPIRY_SEC:
                text = f"{EMOJI[kind]} {entry_text}"
                wait = RESULT_EXPIRY_SEC - age
            else:
                entry = None
        # The window title is an interpolated string.
        return text.replace("\\", "\\\\"), wait

    # Sleeps until the title changes, to save battery: a new entry, the next
    # second of a progress entry, its last tick or expiry. A window opened while idle gets
    # the title with the next entry.
    async def render():
        while True:
            # Cleared before reading the state, so a status_add() during the
            # pass isn't lost.
            changed.clear()
            current, wait = title()
            for window in app.terminal_windows:
                try:
                    await window.async_set_title(current)
                except iterm2.RPCException as error:
                    # E.g. the window closed meanwhile.
                    print(f"failed to set the title: {error!r}")
            try:
                # A new entry cuts the wait short and sets a new one.
                await asyncio.wait_for(changed.wait(), wait)
            except TimeoutError:
                pass

    # A loop of its own, so a slow or missing Hammerspoon doesn't hold the
    # titles back, while the posts keep the order of the entries. Hammerspoon
    # ticks and expires the entry by itself, so only new entries are posted.
    async def notify_notch():
        posted = None
        while True:
            await notch_changed.wait()
            notch_changed.clear()
            if entry is not None and entry is not posted:
                posted = entry
                kind, text, _ = entry
                await asyncio.to_thread(post_to_notch, kind, text)

    # Only updates the state: the loops call the iTerm API and Hammerspoon.
    @iterm2.RPC
    async def status_add(kind: str, text: str):
        nonlocal entry
        if kind not in EMOJI:
            raise ValueError(f"unknown kind: {kind}")
        entry = (kind, text, time.monotonic())
        changed.set()
        notch_changed.set()

    await status_add.async_register(connection)
    _render_task = asyncio.create_task(render())
    _notch_task = asyncio.create_task(notify_notch())


# gm.py imports this file.
if __name__ == "__main__":
    iterm2.run_forever(main)
