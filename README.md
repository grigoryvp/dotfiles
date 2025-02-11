# My Win and MacOS box auto config

## Windows install

```ps1
winget install --silent Microsoft.PowerShell # asks elevation IN BACKGROUND
```

Relaunch terminal, continue with `Elevated PowerShell`:

```ps1
$repo_url = "https://raw.githubusercontent.com/grigoryvp/dotfiles"
$url = "$repo_url/master/configure_win.ps1"
# 'Invoke-Expression' instead of 'iex' since 'iex' is removed by profile.ps1
Invoke-WebRequest $url -OutFile ./configure.ps1
Set-ExecutionPolicy Unrestricted -Scope CurrentUser
./configure.ps1
```

Follow instructions for post-configuration.

```sh
sudo apt update
# pyenv build dependencies
sudo apt install make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
printf '. /mnt/c/Users/user/dotfiles/shell-cfg.sh\n' >> ~/.bashrc
printf '#!/bin/sh\n. /mnt/c/Users/user/dotfiles/shell-cfg\n' > ~/.zshrc
printf '[include]\npath = /mnt/c/Users/user/dotfiles/git-cfg.toml\n' > ~/.gitconfig
mkdir -p ~/.config/lsd/
cp /mnt/c/Users/user/dotfiles/.gitattributes ~/.gitattributes
cp /mnt/c/Users/user/dotfiles/lsd.config.yaml ~/.config/lsd/config.yaml
git clone https://github.com/michaeldfallen/git-radar ~/.git-radar
git clone https://github.com/pyenv/pyenv.git ~/.pyenv
git clone https://github.com/pyenv/pyenv-virtualenv.git ~/.pyenv/plugins/pyenv-virtualenv
# Reload shell
pyenv install 3.12.2
pyenv global 3.12.2
pip install --upgrade pip
```

## OSX

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/grigoryvp/dotfiles/HEAD/configure_macos.sh)"
# Install https://macos.telegram.org/
# Install Trello from App Store
# Command-drag-out menu icons except clock (until the "x" mark appears)
# Remove all dock icons except launchpad, calendar, settings
# Dock: iTerm, VSCode, Chrome, Double, Pass, Telegram, Mail, NotionC, Trello
# Dock left: ChatGPT, Slack, WhatsApp, HEY, Discord, Parallels
# Menu: hammerspoon, lunar, tailscale, command center, time
# Remove all widgets and add "Note" as widget
# Add noTunes.app, hammerspoon to Settings/General/Login
# In "Settings/Dock":
# * Minimize windows into application icon
# In "Settings/Wallpaper":
# * Set black wallpaper
# In "Settings/Notifications":
# * Disable everything for FaceTime
# In "Settings/Sound":
# * Disable startup sound
# * Mute interface sound effects
# In "Settings/Lock Screen":
# * Require password immediately after screen is locked
# In "Settings/Keyboard":
# * Disable backlit
# * Add "Russian-PC" and "Japanese-Romaji" for "Input Sources"
# In "Settings/Keyboard/Shortcuts":
# * Add "⇧⌘\" for "Mission Control/Notification Center"
# * Disable input source shortcuts in "Input sources"
# * Remove "⇧⌘/" app shortcut from "All Applications"
# * Add "⌘W" to "Close Tab" for "Safari" app shortcut
# * Add "⌥⇧⌘V" to "Paste and Match Style" for "Telegram" app shortcut
# * Enable F-keys in "Function Keys"
# * Disable caps in "Modifier Keys"
# In "Settings/Trackpad/More gestures":
# * Disable gestures
# For iTerm2 settings
# * Disable /General/Closing/Confirm
# * Disable /General/Selection/Clicking
# * Set Appearance/General/Theme to "Dark"
# * Set Appearance/Windows/Hide scrollbars
# * Set Profiles/Colors/Color presets to "Solarized Dark"
# * Set Profiles/Text/Font to "JetBrainsMono Nerd Font" size 16
# For DoubleCommander settings
# * In /Files views/Columns/Custom columns
#   * Change GETFILENAMENOEXT to GETFILENAME
#   * Delete the "ext" and "attr" columns
# * In /File operations/confirmation disable all confirmations
# For OBS settings
# * Turn off Advanced/General/Show warning on exit
# Login all chrome profiles and name them 01, 02, 03 etc
# Configure KeePass with browser integration and passkeys
# Configure ChatGPT for autostart and "dock only" icon.
# Add KeyLights, blue temp, 90% back, 40% front
# Import OBS Scenes
# App Store: Xcode, Amphetamine, Windows App, PowerPoint, Pixelmator
# Install Parallels Desktop
# Install https://onekey.so/download/
# Install https://tonkeeper.com/pro
# phpenv install 8.0.9 # https://github.com/phpenv/phpenv/issues/90
# phpenv global 8.0.9 # https://github.com/phpenv/phpenv/issues/90
# For old macOS versions:
# * Disable welcome screen guest user in "Preferences/Users & Groups"
# * Add 'karabiner_grabber', 'karabiner_observer',
#   'karabiner_console_user_server' into "Accessibility"
# * Install https://d11yldzmag5yn.cloudfront.net/prod/4.4.53909.0617/Zoom.pkg
# * iTunes/Preferences/Devices/Prevent from syncing automatically
```

## Todo

* Ignore subsequent "down" events on buttons that emulate mouse buttons.
* Implement "go-to-background" Ctrl-D via PS keyboard hook.

## License

The following licensing applies to My windows box automatic configuration:
Attribution-NonCommercial-NoDerivatives 4.0 International
(CC-BY-NC-ND-4.0). For more information go to
[https://creativecommons.org/licenses/by-nc-nd/4.0/](https://creativecommons.org/licenses/by-nc-nd/4.0/)
