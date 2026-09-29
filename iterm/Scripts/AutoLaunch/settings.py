import json

import iterm2

Key = iterm2.PreferenceKey

GLOBAL_PREFS: dict[Key | str, object] = {
    Key.PROMPT_ON_QUIT: False,
    Key.ONLY_WHEN_MORE_TABS: False,
    # General/Selection "Clicking on a command selects it"; absent from the enum.
    "ClickToSelectCommand": False,
    Key.THEME: 1,  # Dark
    Key.HIDE_SCROLLBAR: True,
    Key.TAP_BAR_POSTIION: 2,  # Left
    Key.HIDE_TAB_BAR_WHEN_ONLY_ONE_TAB: False,
    Key.HIDE_TAB_NUMBER: True,
    # The enum's HIDE_TAB_CLOSE_BUTTON maps to a key iTerm2 3.7 no longer reads.
    "TabsHaveCloseButton": False,
    Key.HIDE_TAB_ACTIVITY_INDICATOR: True,
    Key.SHOW_TAB_NEW_OUTPUT_INDICATOR: False,
    Key.DIM_BACKGROUND_WINDOWS: True,
    Key.DIM_ONLY_TEXT: True,
    Key.SPLIT_PANE_DIMMING_AMOUNT: 0.6,
}

COLOR_PRESET = "Solarized Dark"
BACKGROUND = iterm2.Color(0, 0, 0)
# PostScript name of "JetBrainsMono Nerd Font Mono", as iTerm2 stores it.
FONT = "JetBrainsMonoNFM-Regular 16"
INITIAL_DIRECTORY = iterm2.InitialWorkingDirectory.INITIAL_WORKING_DIRECTORY_RECYCLE
PROFILE_FLAGS = {
    "silence_bell": True,
    # "Filter Alerts": notify on bell only.
    "send_bell_alert": True,
    "send_idle_alert": False,
    "send_new_output_alert": False,
    "send_session_ended_alert": False,
    "send_terminal_generated_alerts": False,
}

# RPC served by split.py. iTerm's own shift-cmd-d splits 50/50.
SPLIT_FUNCTION = "custom_horizontal_split"


async def get_pref(connection, key: Key | str):
    # iterm2.async_get_preference() rejects plain strings; go through the RPC.
    name = key.value if isinstance(key, Key) else key
    proto = await iterm2.rpc.async_get_preference(connection, name)
    result = proto.preferences_response.results[0].get_preference_result
    return json.loads(result.json_value)


async def apply_global_prefs(connection):
    for key, wanted in GLOBAL_PREFS.items():
        if await get_pref(connection, key) != wanted:
            await iterm2.async_set_preference(connection, key, wanted)


def same_color(a, b):
    if a is None or b is None:
        return False
    return all(
        round(getattr(a, c)) == round(getattr(b, c))
        for c in ("red", "green", "blue", "alpha")
    )


async def apply_colors(connection, profile):
    preset = await iterm2.ColorPreset.async_get(connection, COLOR_PRESET)
    if preset is None:
        return
    wanted = {c.key: c for c in preset.values}
    wanted["Background Color"] = BACKGROUND
    if all(same_color(profile.get_color_with_key(k), c) for k, c in wanted.items()):
        return
    await profile.async_set_color_preset(preset)
    await profile.async_set_background_color(BACKGROUND)


async def apply_profile(connection):
    profile = await iterm2.Profile.async_get_default(connection)
    await apply_colors(connection, profile)

    if profile.initial_directory_mode != INITIAL_DIRECTORY.value:
        await profile.async_set_initial_directory_mode(INITIAL_DIRECTORY)
    if profile.normal_font != FONT:
        await profile.async_set_normal_font(FONT)
    # Getters return 0/1, or None for keys never written; some of those
    # default to on, so None must be written too.
    for name, wanted in PROFILE_FLAGS.items():
        if getattr(profile, name) != wanted:
            await getattr(profile, f"async_set_{name}")(wanted)


def make_split_key_binding():
    return iterm2.KeyBinding(
        # Shift makes charactersIgnoringModifiers uppercase, so iTerm looks up "D".
        character=ord("D"),
        modifiers=[iterm2.Modifier.SHIFT, iterm2.Modifier.COMMAND],
        # Keycode lets iTerm match the physical key in non-Latin layouts
        # when "language-agnostic key bindings" is enabled.
        keycode=iterm2.Keycode.ANSI_D,
        action=iterm2.BindingAction.INVOKE_SCRIPT_FUNCTION,
        param=f"{SPLIT_FUNCTION}()",
        version=None,
        label=None,
    )


async def apply_key_bindings(connection):
    """Bind shift-cmd-d in Preferences > Keys so new machines need no manual setup."""
    wanted = make_split_key_binding()
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
    await apply_global_prefs(connection)
    await apply_profile(connection)
    await apply_key_bindings(connection)


iterm2.run_until_complete(main)
