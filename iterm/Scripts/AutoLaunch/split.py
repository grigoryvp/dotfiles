#!/usr/bin/env python3
import iterm2

BOTTOM_ROWS = 10
RIGHT_COLUMNS = 80


async def _split_with_fixed_pane(
    window: iterm2.Window,
    tab: iterm2.Tab,
    session: iterm2.Session,
    vertical: bool,
    profile_customizations: iterm2.LocalWriteOnlyProfile | None = None,
) -> iterm2.Session:
    frame = await window.async_get_frame()

    # Refreshes the app state, so grid sizes below are post-split.
    pane = await session.async_split_pane(
        vertical=vertical, profile_customizations=profile_customizations
    )

    # The library seeds preferred_size from grid_size only when it first sees
    # a session, and async_update_layout() sends it for every pane, so a pane
    # resized since then (e.g. gm.py's bottom one) would snap back.
    for other in tab.all_sessions:
        if other.grid_size is not None:
            other.preferred_size = other.grid_size

    a, b = session.grid_size, pane.grid_size
    if a is not None and b is not None:
        # Split from the post-split total: the divider takes cells, and an
        # oversized layout makes iTerm refit the window, shrinking other panes.
        if vertical:
            pane.preferred_size = iterm2.Size(RIGHT_COLUMNS, a.height)
            session.preferred_size = iterm2.Size(
                a.width + b.width - RIGHT_COLUMNS, a.height
            )
        else:
            pane.preferred_size = iterm2.Size(a.width, BOTTOM_ROWS)
            session.preferred_size = iterm2.Size(
                a.width, a.height + b.height - BOTTOM_ROWS
            )
        await tab.async_update_layout()
    await window.async_set_frame(frame)
    return pane


# These two are also used by gm.py for the tabs it opens.
async def split_with_bottom_pane(
    window: iterm2.Window,
    tab: iterm2.Tab,
    session: iterm2.Session,
    profile_customizations: iterm2.LocalWriteOnlyProfile | None = None,
) -> iterm2.Session:
    return await _split_with_fixed_pane(
        window,
        tab,
        session,
        vertical=False,
        profile_customizations=profile_customizations,
    )


async def split_with_right_pane(
    window: iterm2.Window,
    tab: iterm2.Tab,
    session: iterm2.Session,
    profile_customizations: iterm2.LocalWriteOnlyProfile | None = None,
) -> iterm2.Session:
    return await _split_with_fixed_pane(
        window,
        tab,
        session,
        vertical=True,
        profile_customizations=profile_customizations,
    )


async def main(connection):
    app = await iterm2.async_get_app(connection)

    def find_session(session_id):
        session = app.get_session_by_id(session_id)
        if session is None or session.tab is None or session.tab.window is None:
            return None
        return session

    # Bound to shift-cmd-d by settings.py.
    @iterm2.RPC
    async def custom_horizontal_split(session_id=iterm2.Reference("id")):
        if session := find_session(session_id):
            await split_with_bottom_pane(session.tab.window, session.tab, session)

    # Bound to cmd-d by settings.py.
    @iterm2.RPC
    async def custom_vertical_split(session_id=iterm2.Reference("id")):
        if session := find_session(session_id):
            await split_with_right_pane(session.tab.window, session.tab, session)

    await custom_horizontal_split.async_register(connection)
    await custom_vertical_split.async_register(connection)


# gm.py imports this file.
if __name__ == "__main__":
    iterm2.run_forever(main)
