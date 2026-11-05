# Notch Status

The state of the iTerm status line (`specs/status.spec.md`) next to the
notch of the built-in display: a command started from Wox (e.g. `gm merge`)
shows its progress and result there, and a click opens the iTerm Script
Console with the full log.

Why: with the Minimal iTerm theme the window has no title bar, so the
status line in the window title is not visible anymore. The menu bar strip
(`hammerspoon/menubarbg.lua`) made the black notch visible, so drawing at
its sides looks like part of the notch, like Boring Notch does.

Status: done.

## Components

- **iTerm script** (`iterm/Scripts/AutoLaunch/status.py`): stays the single
  owner of the status state and also reports every change of it to
  Hammerspoon.
- **Hammerspoon module** (`hammerspoon/notch.lua`): draws the indicator,
  ticks the elapsed time, expires results and handles the click.

## Call chain

```
gm.py: await add_log("progress", "git push test-project")
status.py: RPC status_add() -> state -> render loop
  -> window titles, as before
  -> HTTP POST localhost:2020
       {"command": "notch_status", "kind": "progress",
        "text": "git push test-project"}
Hammerspoon: App:startHttpServer() -> notch:setStatus(kind, text)
  -> redraws the ears, starts its own ticking and expiry timers
```

`status.py` posts only new entries, not every tick: Hammerspoon keeps the
time of the entry and redraws by its own timer. The posts run in a loop of
their own, next to the render loop, so a slow or missing Hammerspoon
doesn't hold the titles back, while the posts keep the order of the
entries. Each post has a 1 s timeout; its error is printed to the Script
Console and swallowed, as `add_log()` does. Hammerspoon ignores `text`
for now. A Hammerspoon reload loses the entry: the ears come back with the
next one.

## Geometry

- **Notch**: Hammerspoon has no API for it. `NSScreen`'s
  `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are the menu bar parts
  at its sides, so the notch is the gap between them. Read through
  `hs.osascript.javascript()` on start and on screen changes, and matched
  to `hs.screen` by x, the axis they share. On the current MacBook: the left area ends at x = 771.5, the right one starts at
  956.5, so the notch is 185 pt wide, the areas are 32 pt high and the menu
  bar 33 pt.
- **Ears**: two black shapes of the notch height, one on each side of it,
  with the outer bottom corner rounded like the notch's own, so the notch
  looks wider. Width: 28 pt each.
- **Screens**: only a screen with a notch, i.e. with non-empty auxiliary
  areas. No ears on external displays.
- **Level**: `mainMenu + 1`, above the menu bar, so the ears cover its
  strip. macOS moves a window one level below the menu bar (`mainMenu - 1`)
  down out of the menu bar area, but leaves this one in place. Not shown in
  fullscreen spaces: the ears don't have the fullscreen auxiliary behavior.
- **Shape**: the black rectangle sticks out of the canvas at the top and
  10 pt under the notch, so only its outer bottom corner is rounded (8 pt,
  as the notch's) and the ear merges with the notch.
- **Overlap**: the ears cover the menu bar next to the notch: the end of
  the app menus on the left and the leftmost status items on the right.
  That's why they are narrow; macOS itself moves menus and status items
  that don't fit away from the notch, but doesn't know about the ears.

## Content

- **Left ear**: the kind icon, the same as in the title: ⌛ progress, ✅
  success, ⚠️ error.
- **Right ear**: the elapsed time of a progress entry in seconds (`12`),
  `>1m` after the first minute, as in the title. Empty for results.
- **Idle**: no entry or an expired one: no ears, the notch is plain.
- **Expiry and ticking**: the same rules as the title (see Behavior in
  `specs/status.spec.md`): results expire after 10 minutes, progress never;
  ticking every second during the first minute only, to save battery.
- **Text**: not shown, there is no room. It is in the window title and in
  the Script Console. Menlo 12, white, centered; emoji as in the title.

## Click

A click on either ear opens the iTerm Script Console: iTerm is activated
and Scripts > Manage > Console is selected with
`hs.application:selectMenuItem()`. The ears are `hs.canvas` objects with
mouse events enabled for this.

## Open questions

- Emoji or drawn icons: emoji are colored and may look foreign next to the
  black notch; a drawn spinner would show progress without the time.
- Whether to keep the status in the window title at all with the Minimal
  theme, or to leave only the notch.
