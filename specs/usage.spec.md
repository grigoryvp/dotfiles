# Subscription Usage

The usage of the AI subscriptions in the menu bar: Claude, Codex and
Antigravity, each as a white logo and two bars, the 5-hour window on the
left and the weekly one on the right. A click shows the percentages and
reset times.

Why: the limits are hit in the middle of work, and each tool shows its
usage only on request. Moving the ping graphs to the notch
(`specs/notch.spec.md`) freed the menu bar room for it.

Status: done.

## Components

- **Hammerspoon module** (`hammerspoon/usage.lua`): polls the providers,
  draws the item, builds the menu. Its item is created by `menuitem:new()`
  between the battery and the CPU graph items, so it is placed between
  them: a menu bar item is placed left of those created before it.
- **Logos** (`hammerspoon/usage-*.svg`): white, loaded by `hs.image`. The
  Claude one is the Claude Code pixel-art mascot, 12x8 pixels drawn at
  1.5 pt per pixel to stay sharp on Retina. OpenAI and Gemini are from
  Simple Icons.

## Providers

Each provider gives the percent and reset time of both windows, or an
error. All calls are async (`hs.http.asyncGet`, `hs.task`); commands are
killed after 20 s.

- **Claude**, every 10 min: `GET https://api.anthropic.com/api/oauth/usage`,
  the endpoint of the `/usage` command of Claude Code, with
  `anthropic-beta: oauth-2025-04-20`. The token is the one of Claude Code,
  read on each poll from the keychain item `Claude Code-credentials` with
  `/usr/bin/security`, which is in the item ACL, so there is no prompt.
  The 5-hour window is the `limits[]` item of kind `session`, the week is
  `weekly_all`; `weekly_scoped` (per model) is in the menu only. The
  `five_hour` and `seven_day` fields are a fallback.
- **Codex**, every 5 min: `GET https://chatgpt.com/backend-api/wham/usage`,
  the endpoint of the `/status` command, with the token and account ID
  from `~/.codex/auth.json`. `rate_limit.primary_window` is the 5-hour
  window, `secondary_window` the week. On an error: the last `rate_limits`
  of the newest session log in `~/.codex/sessions`, as old as the last
  Codex turn.
- **Antigravity**, every 15 min: `agy -p /usage --output-format json
  --log-file /dev/null`. The print mode answers without an agent turn and
  quota, takes about 3 s and exits; the IDE language server would stay
  running. Quotas are per group of models (Gemini, Claude and GPT) and
  come as a remaining fraction. Each bar shows the most used group, the
  menu shows all. The current tier has only weekly quotas, so the left bar
  stays empty. `--log-file` keeps the CLI from writing a log on each poll.

Tokens are never refreshed and credential files are never written: the
refresh tokens are single-use, and a refresh would log the tools out. An
expired Claude token is an error until Claude Code runs again.

Both endpoints are internal: the response is parsed defensively, a field
that is missing or of another type means no value.

## Display

- **Bars**: in the style of the CPU graph, black with a gray frame, the
  height of the menu bar, 4 pt wide, with a dark gray line between the two. Height is the percent, at least 2 pt. Green under
  30%, orange under 80%, red from 80%.
- **Gaps**: 8 pt between logos and bars, and to the icons of the neighbor
  items. macOS pads an item icon by 8 pt on each side, so the item is a
  transparent placeholder narrower by the padding, and a canvas over it
  draws the logos and bars, following the item on each menu update of
  `main.lua`, every second.
- **Reset**: a window past its reset time shows 0 until the next poll.
- **Stale**: values older than 3 poll intervals are gray and the logo is
  dimmed. No value yet: no bar.
- **Redraw**: only when the percents, colors or staleness change, checked
  on each poll and every minute.
- **Menu**: built on click. For each provider: its windows with reset
  time, the age of the values and the last error; the provider title opens
  its usage page. `Refresh now` polls all of them.

## Errors and rate limits

The usage endpoint of Claude answers 429 when polled often. On 429 the
next poll waits `Retry-After`, at least twice the previous delay, up to an
hour. Other errors are retried at the normal interval and shown in the menu
and the Hammerspoon console. Waking up or unlocking the screen polls all
providers, at most once a minute.
