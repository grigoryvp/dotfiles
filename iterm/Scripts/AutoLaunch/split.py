#!/usr/bin/env python3
import iterm2

BOTTOM_ROWS = 10
FUNCTION_NAME = "custom_horizontal_split"


def make_key_binding():
    return iterm2.KeyBinding(
        # Shift makes charactersIgnoringModifiers uppercase, so iTerm looks up "D".
        character=ord("D"),
        modifiers=[iterm2.Modifier.SHIFT, iterm2.Modifier.COMMAND],
        # Keycode lets iTerm match the physical key in non-Latin layouts
        # when "language-agnostic key bindings" is enabled.
        keycode=iterm2.Keycode.ANSI_D,
        action=iterm2.BindingAction.INVOKE_SCRIPT_FUNCTION,
        param=f"{FUNCTION_NAME}()",
        version=None,
        label=None,
    )


async def ensure_key_binding(connection):
    """Bind shift-cmd-d in Preferences > Keys so new machines need no manual setup."""
    wanted = make_key_binding()
    # The helper fails to decode the "null" an unset map returns on a fresh install.
    try:
        bindings = await iterm2.async_get_global_key_bindings(connection)
    except TypeError:
        bindings = []
    if wanted in bindings:
        return
    bindings = [b for b in bindings if b.key != wanted.key]
    bindings.append(wanted)
    await iterm2.async_set_global_key_bindings(connection, bindings)


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
    await ensure_key_binding(connection)


iterm2.run_forever(main)
