# My Win, WSL2, MacOS box auto config

## Windows install via cmd.exe

```bat
rem Allow PowerShell packages to be installed
powershell.exe -c Set-ExecutionPolicy RemoteSigned -scope CurrentUser
rem Install scoop
powershell.exe -c "iwr -useb get.scoop.sh | Invoke-Expression"
set PATH=%PATH%;%USERPROFILE%\scoop\shims
rem Install Powershell Core
scoop install https://raw.githubusercontent.com/grigoryvp/scoop-grigoryvp/master/7zip.json
scoop install git pwsh
rem Configure this box
pwsh.exe -c "iwr -useb https://raw.githubusercontent.com/grigoryvp/box-cfg/master/configure.ps1 | iex"
```

Follow instructions for post-configuration.

## WSL

```sh
printf '#!/bin/sh\n. /mnt/c/Users/user/.box-cfg/shell/.bashrc\n' >> ~/.bashrc
printf '#!/bin/sh\n. /mnt/c/Users/user/.box-cfg/shell/.bashrc\n' >> ~/.zshrc
printf '[include]\npath = /mnt/c/Users/user/.box-cfg/shell/git-cfg.toml\n' >> ~/.gitconfig
cp /mnt/c/Users/user/.box-cfg/shell/.gitattributes ~/.gitattributes
mkdir -p ~/.config/lsd/
cp /mnt/c/Users/user/.box-cfg/shell/lsd.config.yaml ~/.config/lsd/config.yaml
git clone https://github.com/michaeldfallen/git-radar ~/.git-radar
```

## OSX

```ps1
softwareupdate --install-rosetta --agre-to-license
arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
brew update --verbose
brew tap homebrew/cask-fonts
# For Python 3.9.1 on Apple Silicon
brew install readline openssl
brew install keepassxc rectangle karabiner-elements hammerspoon visual-studio-code font-jetbrains-mono-nerd-font qbittorrent obs mpv iterm2 gimp tor-browser the_silver_searcher michaeldfallen/formula/git-radar exa lsd
git clone https://github.com/grigoryvp/box-cfg.git ~/.box-cfg
# Confirm execution of downloaded app.
open /Applications/KeePassXC.app ~/.box-cfg/passwords.kdbx
keepassxc-cli show -s ~/.box-cfg/passwords.kdbx github
# Add ssh to github
rm -rf ~/.box-cfg
git clone git@github.com:grigoryvp/box-cfg.git ~/.box-cfg
git clone git@github.com:grigoryvp/xi.git ~/.xi
printf '#!/bin/sh\n. ~/.box-cfg/shell/.bashrc\n' > ~/.bashrc
printf '#!/bin/sh\n. ~/.bashrc\n' > ~/.bash_profile
printf '#!/bin/sh\n. ~/.bash_profile\n' > ~/.zshrc
ln -fs /hammerspoon.lua ~/.hammerspoon/init.lua
ln -fs ~/.box-cfg/shell/.screenrc ~/.screenrc
ln -fs ~/.box-cfg/shell/.gitattributes ~/.gitattributes
mkdir -p ~/.config/lsd/
ln -fs ~/.box-cfg/shell/lsd.config.yaml ~/.config/lsd/config.yaml
printf '[include]\npath = ~/.box-cfg/shell/git-cfg.toml\n' >> ~/.gitconfig
mkdir -p ~/.config/powershell
ln -fs ~/.box-cfg/profile.ps1 ~/.config/powershell/profile.ps1
code --install-extension grigoryvp.language-xi
code --install-extension grigoryvp.memory-theme
code --install-extension vscodevim.vim
code --install-extension EditorConfig.EditorConfig
ln -fs ~/.box-cfg/vscode_keybindings.json ~/Library/Application\ Support/Code/User/keybindings.json
ln -fs ~/.box-cfg/vscode_settings.json ~/Library/Application\ Support/Code/User/settings.json
# Create config dir.
mpv --help
echo "save-position-on-quit" >> ~/.config/mpv/mpv.conf
# Disable spotlight for better battery life:
sudo mdutil -a -i off
open /Applications/Karabiner-Elements.app
# Confirm 'karabiner_grabber', 'karabiner_observer' for "Input Monitoring".
# From '/Library/Application Support/org.pqrs/Karabiner-Elements/bin'
cp ~/.box-cfg/karabiner.json ~/.config/karabiner/karabiner.json
# Enable keyboard repeat, need to restart after that
defaults write -g ApplePressAndHoldEnabled -bool false
defaults write -g NSAutomaticCapitalizationEnabled -bool false
defaults write com.apple.applemultitouchtrackpad TrackpadHandResting -int 0
# Input method name lookup for debug purpose
curl -Ls https://raw.githubusercontent.com/daipeihust/im-select/master/install_mac.sh | sh
git clone https://github.com/pyenv/pyenv.git ~/.pyenv
git clone https://github.com/pyenv/pyenv-virtualenv.git $(pyenv root)/plugins/pyenv-virtualenv
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git $(rbenv root)/plugins/ruby-build
git clone https://github.com/nodenv/nodenv.git ~/.nodenv
git clone https://github.com/nodenv/node-build.git $(nodenv root)/plugins/node-build
# Reload shell
pyenv install 3.9.1
pyenv global 3.9.1
pip install --upgrade pip
rbenv install 3.0.0
rbenv global 3.0.0
nodenv install 15.8.0
nodenv global 15.8.0
# Add "Russian-PC", "Japanese-Romaji" in "Preferences/Keyboard/Input Process".
# App store: Snap, Battery Monitor, XCode, Affinity.
# Install https://www.marcmoini.com/sx_en.html
# Install https://macos.telegram.org/
# Configure "Snap" for "command-shift-option-control-number".
# Configure "Smart Scroll":
# * Disable "Hover Scroll".
# * "Grab scroll without moving cursor" to button 6.
# * Enable "Scroll without moving cursor".
# * Disable "Inertia".
# Configure "Rectangle" hotkeys.
# Configure iTerm2 theme, set "JetBrainsMono Nerd Font".
# Menu: rectangle, wifi, bt, clock, short menu, battery monitor, menumeters
# Drop "/System/Library/CoreServices/Finder.app" into dock.
# Dock: iTerm2, vscode, browser, Finder, Keepass, Telegram lite
# Set max key repeat and min delay in "Preferences/Keyboard"
# Set "⇧⌘\" to "Notification Center" in "Preferences/Keyboard/Shortcuts".
# In "Preferences/Keyboard/Shortcuts/App Shortcuts":
# * Remove "⇧⌘/"
# * Add "⌘W" to "Close Tab" for "Safari".
# * Add "⌥⇧⌘V" to "Paste and Match Style" for "Telegram".
# Disable corrections in "Preferences/Keyboard/Text".
# Disable sleep in "Preferences/Energy Saver".
# Enable password lock in "Preferences/Security/General/Require password".
# For old macOS versions:
# Add 'karabiner_grabber', 'karabiner_observer',
#   'karabiner_console_user_server' into "Accessibility".
# Install https://d11yldzmag5yn.cloudfront.net/prod/4.4.53909.0617/Zoom.pkg
# Install https://getbitbar.com/plugins/Network/ping.10s.sh
# Disable welcome screen guest user in "Preferences/Users & Groups".
# "iTunes/Preferences/Devices/Prevent from syncing automatically"
```

## Todo

* Ignore subsequent "down" events on buttons that emulate mouse buttons.
* Implement "go-to-background" Ctrl-D via PS keyboard hook.

## License

The following licensing applies to My windows box automatic configuration:
Attribution-NonCommercial-NoDerivatives 4.0 International
(CC BY-NC-ND 4.0). For more information go to
[https://creativecommons.org/licenses/by-nc-nd/4.0/](https://creativecommons.org/licenses/by-nc-nd/4.0/)
