# Notch Status

The state of the iTerm status line (`specs/status.spec.md`) and the ping
graphs next to the notch of the built-in display: a command started from
Wox (e.g. `gm merge`) shows its progress and result there, and a click
opens the iTerm Script Console with the full log.

Why: with the Minimal iTerm theme the window has no title bar, so the
status line in the window title is not visible anymore. The menu bar tint
(Menu Bar Tint, set up by `configure_macos.sh`) makes the black notch
visible, so drawing at its sides looks like part of the notch, like Boring
Notch does.

Status: done.

## Components

- **iTerm script** (`iterm/Scripts/AutoLaunch/status.py`): stays the single
  owner of the status state and also reports every change of it to
  Hammerspoon.
- **Hammerspoon module** (`hammerspoon/notch.lua`): draws the indicator,
  ticks the elapsed time, expires results and handles the click.
- **Hammerspoon app** (`hammerspoon/main.lua`): passes the ping graphs to
  the ears on every heartbeat (0.2 s), as it draws its menu bar item; they
  are drawn by `menuitem.graphElements()`, shared with that item. The item
  keeps only the CPU graph and the battery, unless there is no notch: see
  Without the notch.

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
for now. A Hammerspoon reload loses the entry: the ears stay empty until the
next one.

## Geometry

- **Notch**: Hammerspoon has no API for it. `NSScreen`'s
  `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are the menu bar parts
  at its sides, so the notch is the gap between them. Read through
  `hs.osascript.javascript()` on start and on screen changes, and matched
  to `hs.screen` by x, the axis they share. On the current MacBook: the
  left area ends at x = 771.5, the right one starts at 956.5, so the notch
  is 185 pt wide, the areas are 32 pt high and the menu bar 33 pt.
- **Ears**: two black shapes of the notch height, one on each side of it,
  with the outer bottom corner rounded like the notch's own, so the notch
  looks wider. Width: 80 pt each, from the content: a 6 pt pad off the
  rounded corner, 24 pt of text, the 42 pt ping graph of 20 columns, 4 pt
  gaps.
- **Screens**: only a screen with a notch, i.e. with non-empty auxiliary
  areas. No ears on external displays.
- **Level**: `mainMenu + 1`, above the menu bar, so the ears cover its
  tint. macOS moves a window one level below the menu bar (`mainMenu - 1`)
  down out of the menu bar area, but leaves this one in place. Not shown in
  fullscreen spaces: the ears don't have the fullscreen auxiliary behavior.
- **Shape**: the black rectangle sticks out of the canvas at the top and
  10 pt under the notch, so only its outer bottom corner is rounded (8 pt,
  as the notch's) and the ear merges with the notch.
- **Overlap**: the ears cover the menu bar next to the notch: the end of
  the app menus on the left and the leftmost status items on the right.
  macOS itself moves menus and status items that don't fit away from the
  notch, but doesn't know about the ears: see App menus.

## App menus

macOS moves the app menus that don't fit at the left of the notch to its
right, but doesn't know about the ears, so a long menu bar can reach under
them. Then that ear narrows to an 8 pt strip, as wide as its rounded
corner, without content: the notch keeps its shape and the menu is visible.
The other ear stays.

- **Check**: the frames of the active app's menu bar items through
  Accessibility (`AXMenuBar` children, `AXFrame`), compared with the ears.
- **When**: on app activation (`hs.application.watcher`), on start and on
  screen changes, not by polling: an app rarely changes its menus while
  active. The result is cached by bundle ID; screen changes clear the
  cache, since the notch position changes.
- **Not handled**: an app that changes its menus while active, and status
  items on the right reaching the right ear (they are drawn by many apps;
  there are usually far fewer than fit the 771 pt).

On the current apps the menus end at 277 to 623 pt, before the left ear
at 691.5 pt.

## Content

The status is next to the notch, the graphs outside of it: there is no
status most of the time, and the empty part then looks like the notch
itself. The ping to the internet and the status icon matter more, so they
are on the right.

- **Left ear**: the ping graph to the router, as it was in the menu bar
  item, and the elapsed time of a progress entry in seconds (`12`), `>1m`
  after the first minute, as in the title; empty for results.
- **Right ear**: the ping graph to the internet and the kind icon, the
  same as in the title: ⌛ progress, ✅ success, ⚠️ error.
- **Idle**: no entry or an expired one: the ears stay with the graphs and
  without the status.
- **Narrowed**: neither status nor graph.
- **Expiry and ticking**: the same rules as the title (see Behavior in
  `specs/status.spec.md`): results expire after 10 minutes, progress never;
  ticking every second during the first minute only, to save battery.
- **Status text**: not shown, there is no room. It is in the window title and in
  the Script Console. Menlo 12, white, centered; emoji as in the title.

## Without the notch

When no screen has a notch, e.g. a MacBook without one, or the geometry
can't be read, there are no ears, and their content goes into the menu bar
on the left of the CPU graph, from right to left: the ping graph to the
internet, the one to the router, the kind icon and the elapsed time, then
the message notifications and the timer, as before.

- **Items**: each graph is a separate menu bar item drawn like the CPU
  graph; the icon and the time are one item with the title `12 ⌛`, or just
  the icon for results. Without a status the item is hidden.
- **Same rules**: the icon, the time, ticking and expiry are those of the
  ears.
- **Click**: on the status item opens the Script Console, as on the ears;
  the graph items open the menu, as the CPU graph does.
- **Switch**: checked on every heartbeat, so connecting or disconnecting a
  screen with a notch moves the content between the ears and the menu bar.

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
