# My windows and OSX box automatic configuration

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

## OSX

```ps1
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
brew update --verbose
brew tap homebrew/cask-fonts
brew cask install keepassxc spectacle karabiner-elements visual-studio-code font-jetbrains-mono menumeters transmission powershell obs mpv bitbar
brew install exa node michaeldfallen/formula/git-radar readline xz pyenv rbenv nodeenv
git clone https://github.com/grigoryvp/box-cfg.git ~/.box-cfg
# Confirm execution of downloaded app.
open /Applications/KeePassXC.app
keepassxc-cli show -s ~/.box-cfg/passwords.kdbx github
# Add ssh to github
rm -rf ~/.box-cfg
git clone git@github.com:grigoryvp/box-cfg.git ~/.box-cfg
git clone git@github.com:grigoryvp/xi.git ~/.xi
curl -Ls https://raw.githubusercontent.com/daipeihust/im-select/master/install_mac.sh | sh
curl -Ls https://raw.githubusercontent.com/dracula/terminal-app/master/Dracula.terminal > ~/Downloads/Dracula.terminal
open ~/Downloads/Dracula.terminal
rm -rf ~/Downloads/Dracula.terminal
# Configure theme as "default", set "JetBrains" font, pwsh shell
cp ~/.box-cfg/shell/.bashrc ~/.bashrc
printf '#!/bin/sh\n. ~/.bashrc\n' > ~/.bash_profile
printf '#!/bin/sh\n. ~/.bash_profile\n' > ~/.zshrc
rm -f ~/.screenrc
ln ~/.box-cfg/shell/.screenrc ~/.screenrc
rm -f ~/.gitconfig
ln ~/.box-cfg/shell/.gitconfig ~/.gitconfig
mkdir -p ~/.config/powershell
rm -f ~/.config/powershell/profile.ps1
ln ~/.box-cfg/profile.ps1 ~/.config/powershell/profile.ps1
code
ln ~/.box-cfg/vscode_keybindings.json ~/Library/Application\ Support/Code/User/keybindings.json
ln ~/.box-cfg/vscode_settings.json ~/Library/Application\ Support/Code/User/settings.json
mpv
echo "save-position-on-quit" >> ~/.config/mpv/mpv.conf
# Disable spotlight for better battery life:
sudo mdutil -a -i off
open /Applications/Karabiner-Elements.app
# Confirm 'karabiner_grabber', 'karabiner_observer' for "Input Monitoring".
# From '/Library/Application Support/org.pqrs/Karabiner-Elements/bin' add
# 'karabiner_grabber', 'karabiner_observer', 'karabiner_console_user_server'
# into "Accessibility".
cp ~/.box-cfg/karabiner.json ~/.config/karabiner/karabiner.json
# OSX up to 10.13
unset CFLAGS
# OSX 10.14 and later (XCode version)
export CFLAGS="-I$(xcrun --show-sdk-path)/usr/include"
pyenv init
echo 'eval "$(pyenv init -)"' >> ~/.bash_profile
pyenv install 3.8.2 2.7.17
pyenv global 3.8.2
rbenv init
echo 'eval "$(rbenv init -)"' >> ~/.bash_profile
rbenv install 2.7.1
rbenv global 2.7.1
nodeenv init
echo 'eval "$(nodeenv init -)"' >> ~/.bash_profile
nodeenv install 13.12.0
nodeenv global 13.12.0
# Enable keyboard repeat, need to restart after that
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
# App store: Snap, Battery Monitor, Telegram, XCode, Affinity.
# Install https://ryanhanson.dev/scroll
# Install https://d11yldzmag5yn.cloudfront.net/prod/4.4.53909.0617/Zoom.pkg
# Install https://www.marcmoini.com/sx_en.html
# Install https://getbitbar.com/plugins/Network/ping.10s.sh
# Menu bar, from right to left:
# spectacle, wifi, bt, clock, short menu, battery monitor, menumeters
# Dock: cmd, vscode, browser, files, keepass, telegram lite
# Set max key repeat and min delay at "Preferences/Keyboard"
# Set notification center shortcut to "shift-command-backslash" in "Preferences/Keyboard/Shortcuts".
# Disable "⇧⌘/" in "Preferences/Keyboard/Shortcuts/App Shortcuts".
# Add "⌘w" to "Close Tab" in "Preferences/Keyboard/Shortcuts/App Shortcuts" for Safari.
# Disable corrections in "Preferences/Keyboard/Text".
# Disable sleep in "Preferences/Energy Saver".
# Add "Russian - PC", "Japanese" in "Preferences/Keyboard/Input Process".
# Configure "Spectacle" hotkeys.
# Configure "Snap" for "command-shift-option-control-number".
# Configure "Smart Scroll" for "Grab scroll without moving cursor", button 6.
# For old macOS versions:
# Disable welcome screen guest user in "Preferences/Users & Groups".
# "iTunes/Preferences/Devices/Prevent from syncing automatically"
```

## Todo

* Ignore subsequent "down" events on buttons that emulate mouse buttons.
* Implement "go-to-background" Ctrl-D via PS keyboard hook.
* Install "7+ Taskbar Tweaker" on Windows.

## License

The following licensing applies to My windows box automatic configuration:
Attribution-NonCommercial-NoDerivatives 4.0 International
(CC BY-NC-ND 4.0). For more information go to
[https://creativecommons.org/licenses/by-nc-nd/4.0/](https://creativecommons.org/licenses/by-nc-nd/4.0/)
