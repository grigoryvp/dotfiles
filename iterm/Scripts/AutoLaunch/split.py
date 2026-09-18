#!/usr/bin/env python3
import iterm2

BOTTOM_ROWS = 10

async def main(connection):
    app = await iterm2.async_get_app(connection)

    @iterm2.RPC
    async def custom_horizontal_split(session_id=iterm2.Reference("id")):
        session = app.get_session_by_id(session_id)
        if session is None:
            return
        tab = session.tab
        window = tab.window
        frame = await window.async_get_frame()
        total = session.grid_size.height

        pane = await session.async_split_pane(vertical=False)

        width = session.grid_size.width
        pane.preferred_size = iterm2.Size(width, BOTTOM_ROWS)
        # 1 line for separator
        session.preferred_size = iterm2.Size(width, total - BOTTOM_ROWS)
        await tab.async_update_layout()
        await window.async_set_frame(frame)

    await custom_horizontal_split.async_register(connection)

iterm2.run_forever(main)
