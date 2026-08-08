#!/usr/bin/env -S uv run --script --no-config
# /// script
# dependencies = ["iterm2"]
# ///
#
# Debug via:
# uv run ~/dotfiles/.claude/hooks/notify.py

import os

import iterm2


async def _notify(connection: iterm2.Connection) -> None:

    session_id = os.environ.get("ITERM_SESSION_ID")
    if not session_id:
        return
    session_id = session_id.rsplit(":", 1)[-1]

    app = await iterm2.async_get_app(connection)
    if app is None:
        return

    session = app.get_session_by_id(session_id)
    if session is None:
        return

    await session.async_inject(b"\a")


def notify():
    iterm2.run_until_complete(_notify)

if __name__ == "__main__":
    notify()
