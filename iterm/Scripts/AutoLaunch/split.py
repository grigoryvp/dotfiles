#!/usr/bin/env python3
import iterm2

BOTTOM_ROWS = 10


# Also used by gm.py for the tabs it opens.
async def split_with_bottom_pane(
    window: iterm2.Window,
    tab: iterm2.Tab,
    session: iterm2.Session,
    profile_customizations: iterm2.LocalWriteOnlyProfile | None = None,
) -> None:
    frame = await window.async_get_frame()
    size = session.grid_size

    pane = await session.async_split_pane(
        vertical=False, profile_customizations=profile_customizations
    )

    if size is not None:
        pane.preferred_size = iterm2.Size(size.width, BOTTOM_ROWS)
        # 1 line for separator
        session.preferred_size = iterm2.Size(size.width, size.height - BOTTOM_ROWS)
        await tab.async_update_layout()
    await window.async_set_frame(frame)


async def main(connection):
    app = await iterm2.async_get_app(connection)

    # Bound to shift-cmd-d by settings.py.
    @iterm2.RPC
    async def custom_horizontal_split(session_id=iterm2.Reference("id")):
        session = app.get_session_by_id(session_id)
        if session is None or session.tab is None or session.tab.window is None:
            return
        await split_with_bottom_pane(session.tab.window, session.tab, session)

    await custom_horizontal_split.async_register(connection)


# gm.py imports this file.
if __name__ == "__main__":
    iterm2.run_forever(main)
