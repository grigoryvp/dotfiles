# Skill Manager (SM)

Makes skills from several git repositories available to coding agents and
updates them with a `git pull`. Each repository is cloned by hand into
`~/skills/<source>`, e.g. `~/skills/grigoryvp-public` and
`~/skills/grigoryvp-private`; SM symlinks its skills into the agents' skill
directories, so a pull updates them in place.

Why not a plugin marketplace: its skills are installed copies with versions
that need explicit add and update steps, while a symlink to a working copy
needs neither.

Status: spec only, nothing is implemented yet.

## Components

Same split as GM (`specs/gm.spec.md`), so all workflow logic lives in iTerm
scripts and reports through the iTerm status line:

- **Wox plugin** (`wox/plugins/single-file/sm.py`): `sm` keyword and
  commands, only forwards them.
- **iTerm script** (`iterm/Scripts/AutoLaunch/sm.py`): all logic.
- **Hammerspoon**: none, SM has no UI yet; a future one goes to
  `hammerspoon/sm.lua`.

Code shared with GM (`run_in_background()`, `run_command()`, `report()`,
the log) moves from `gm.py` into an AutoLaunch module imported by both, the
way `split.py` and `status.py` are. iTerm also runs it as a script, so its
`__main__` does nothing.

## Commands

- `sm sync`: links the skills of all sources into the agents' directories
  and removes stale links.
- `sm pull`: `git pull` in every source, then `sm sync`.

`sm` with no command lists the commands, as `gm` does.

## Call chain

```
Wox (sm pull, Enter)
  -> osascript: tell application id "com.googlecode.iterm2"
       to invoke API expression "sm_pull()"
iTerm script: RPC sm_pull() -> run_in_background(): pull, then sync
```

`sm sync` is the same with `sm_sync()`. RPCs take no arguments and return
at once (see "iTerm RPCs must return immediately" in `specs/gm.spec.md`).

## Design

- **Sources**: the non-hidden directories in `~/skills`, in name order. A
  skill is a non-hidden subdirectory of a source with a `SKILL.md` file;
  other subdirectories (`scripts`, `.github`) are skipped. The plugin layout
  (`<source>/skills/<name>/SKILL.md`) is not supported until a source needs
  it.
- **Agents**: a constant list of skill directories, so a new agent (e.g.
  Gemini) is one more entry:
  - Claude Code: `~/.claude/skills`. It is a directory of the dotfiles repo,
    whose `.gitignore` ignores everything there, since the list of skills in
    use is personal data.
  - Codex (experimental): `~/.agents/skills`. Codex also reads
    `~/.codex/skills`, but keeps its own system skills in `.system` there.
    `configure_macos.sh` creates the directory.
- **Links**: `<agent dir>/<skill>` -> `~/skills/<source>/<skill>` with an
  absolute target, since `~/.claude` is itself a symlink into dotfiles. A
  link is SM's own if its target is under `~/skills`; SM never touches
  anything else in an agent directory (e.g. Claude's `synced` or Codex's
  `.system`).
- **Sync**: the wanted links are computed first, so the result doesn't
  depend on earlier syncs. On a name clash between sources the first source
  in name order wins and the others are skipped with a warning; an entry
  that isn't SM's own takes the name too, also with a warning. Then in every
  agent directory (created if missing): SM's own links that aren't wanted
  (dangling, or pointing to another source) are removed, missing ones are
  created. Warnings are not failures: they go to the log and to the success
  text, e.g. `sm SYNC: 14 skills, +1 -2, skipped review (grigoryvp-public)`.
- **Pull**: all sources concurrently. Each one is checked first:
  - not a git repository (its own top level, not a parent's): skipped
    without an error and named in the success text, so a directory managed
    by hand still works for `sm sync`;
  - otherwise it is an error and no pull unless the current branch has an
    upstream and its remote's URL (`git
    remote get-url`, which applies `insteadOf`) must be a GitHub repository
    of `grigoryvp` (`https://github.com/grigoryvp/...`,
    `git@github.com:grigoryvp/...` or `ssh://git@github.com/grigoryvp/...`).
    Why: a pull runs new code in the agents with the user's permissions, so
    only the user's own repositories are updated automatically.

  Then `git pull --ff-only` with `GIT_TERMINAL_PROMPT=0` and gh as the only
  credential helper, as GM's fetch does. A failed source doesn't stop the
  others, and sync runs after all of them, so the pulled ones are linked.
- **Status line and errors**: as in GM, through `status.py`: progress
  before each pull (`git pull grigoryvp-public`), the command in caps on
  success (`sm PULL`, `sm SYNC`), `<command>: <message>` on the first
  failure. The log is `~/.cache/grigoryvp-sm/sm.log`, in GM's format.

## Open questions

- Whether Claude Code picks up a new skill directory in a running session
  or only after a restart; check when implementing and note it here.
