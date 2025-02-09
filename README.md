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
# Configure hammerspoon for autostart
# Command-drag-out menu icons except clock (until the "x" mark appears)
# Remove all dock icons except launchpad, calendar, settings
# Add "trello" as chrome app
# Install https://macos.telegram.org/
# Dock: iTerm, VSCode, Chrome, Double, Pass, Telegram, Mail, NotionC, Trello
# Dock left: ChatGPT, Slack, WhatsApp, HEY, Discord, Parallels
# Menu: hammerspoon, lunar, tailscale, command center, time
# Add noTunes.app in Settings/General/Login
# In "Settings/Lock Screen"
# * Disable Screen Saver
# * Set "require password" to "Immediately"
# Disable Music access to bluetooth in /Preferences/Privacy/Bluetooth"
# In "Settings/Keyboard" disable brightness
# In "Settings/Keyboard/Shortcuts":
# * Remove "input sources" ^-space shortcuts
# * Remove "⇧⌘/" app shortcut from "All Applications"
# * Add "⌘W" to "Close Tab" for "Safari" app shortcut
# * Add "⌥⇧⌘V" to "Paste and Match Style" for "Telegram" app shortcut
# * Add "⇧⌘\" for "Mission Control/Notification Center"
# * Enable F-keys in "Function keys"
# * Disable caps in "Modifier Keys"
# In "Settings/Keyboard/Input Sources":
# * Add "Russian-PC", "Japanese-Romaji"
# Disable all in "Settings/Trackpad/More Gestures":
# Remove all widgets and add notes as widget
# Configure default email reader in the "Apple Mail" app settings.
# For iTerm2 settings
# * Disable /General/Selection/Clicking
# * Set Appearance/General/Theme to "Dark"
# * Set Appearance/Windows/Hide scrollbars
# * Set Profiles/Colors/Color presets to "Solarized Dark"
# * Set Profiles/Text/Font to "JetBrainsMono Nerd Font" size 16
# Configure KeePass
# Configure ChatGPT for autostart and "dock only" icon.
# Configure F2 to cm_HorizontalFilePanels for Double Commander
# Add KeyLights, blue temp, 90% back, 40% front
# Import OBS Scenes
# Install Xcode (this may take HOURS, better to do with App Store):
# mas install 497799835
# Install Amphetamine
# mas install 937984704
# Install Windows App (RDP client)
# mas install 1295203466
# Install https://onekey.so/download/
# Install https://tonkeeper.com/pro
# Install Parallels Desktop
# Install Microsoft PowerPoint
# Install Pixelmator Pro from App Store
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
* A way to communicate with hammerspoon without hotkeys.
* Remember window resize state while moving it between screens.

## License

The following licensing applies to My windows box automatic configuration:
Attribution-NonCommercial-NoDerivatives 4.0 International
(CC-BY-NC-ND-4.0). For more information go to
[https://creativecommons.org/licenses/by-nc-nd/4.0/](https://creativecommons.org/licenses/by-nc-nd/4.0/)
