# My windows and OSX box automatic configuration

## Windows

```bat
rem Allow PowerShell packages to be installed
powershell.exe -c Set-ExecutionPolicy RemoteSigned -scope CurrentUser
rem Install scoop
powershell.exe -c iwr -useb get.scoop.sh | iex
rem Install Powershell Core
scoop install https://raw.githubusercontent.com/grigoryvp/scoop-grigoryvp/master/7zip.json git pwsh
rem Configure this box
pwsh.exe -c iwr -useb https://raw.githubusercontent.com/grigoryvp/box-cfg/master/configure.ps1 | iex
```

Follow instructions for post-configuration.

## OSX

```ps1
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
brew update --verbose
brew tap homebrew/cask-fonts
brew cask install keepassxc spectacle karabiner-elements visual-studio-code font-monoid menumeters transmission powershell obs vlc zoomus
brew install exa node michaeldfallen/formula/git-radar readline xz pyenv rbenv
npm i -g git-alias
# Fixes 'cannot lock ref' case sensetive issue.
git config --global fetch.prune true
git clone https://github.com/grigoryvp/box-cfg.git ~/.box-cfg
keepassxc-cli show -s ~/.box-cfg/passwords.kdbx github
# Add ssh to github
rm -rf ~/.box-cfg
git clone git@github.com:grigoryvp/box-cfg.git ~/.box-cfg
git clone git@github.com:grigoryvp/xi.git ~/.xi
curl -Ls https://raw.githubusercontent.com/daipeihust/im-select/master/install_mac.sh | sh
curl -Ls https://raw.githubusercontent.com/dracula/terminal-app/master/Dracula.terminal > ~/Downloads/Dracula.terminal
open ~/Downloads/Dracula.terminal
rm -rf ~/Downloads/Dracula.terminal
ln ~/.box-cfg/shell/.bashrc ~/.bashrc
printf '#!/bin/sh\n. ~/.bashrc\n' > ~/.bash_profile
ln ~/.box-cfg/shell/.screenrc ~/.screenrc
ln ~/.box-cfg/shell/.gitconfig ~/.gitconfig
code
ln ~/.box-cfg/vscode_keybindings.json ~/Library/Application\ Support/Code/User/keybindings.json
ln ~/.box-cfg/vscode_settings.json ~/Library/Application\ Support/Code/User/settings.json
# Start Karabiner-Elements
cp ~/.box-cfg/karabiner.json ~/.config/karabiner/karabiner.json
xcode-select --install
# OSX up to 10.13
unset CFLAGS
# OSX 10.14 and later (XCode version)
# export CFLAGS="-I$(xcrun --show-sdk-path)/usr/include"
pyenv init
echo 'eval "$(pyenv init -)"' >> ~/.bash_profile
pyenv install 3.7.4
pyenv global 3.7.4
rbenv init
echo 'eval "$(rbenv init -)"' >> ~/.bash_profile
rbenv install 2.6.5
rbenv global 2.6.5
# Enable keyboard repeat, need to restart after that
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
# Install Short Menu, Battery Monitor, XCode, Affinity, Telegram (Not "Telegram Desktop"), Chatty from app store.
# Menu bar, from right to left:
# spectacle, wifi, bt, clock, short menu, battery monitor, menumeters
# Install tampermonkey for Safari.
# Set max key repeat and min delay at "Preferences/Keyboard"
# Set notification center shortcut to "shift-command-backslash" in "Preferences/Keyboard/Shortcuts".
# Disable "⇧⌘/" in "Preferences/Keyboard/Shortcuts/App Shortcuts".
# Add "⌘w" to "Close Tab" in "Preferences/Keyboard/Shortcuts/App Shortcuts" for Safari.
# Disable corrections in "Preferences/Keyboard/Text".
# Disable sleep in "Preferences/Energy Saver".
# Disable welcome screen guest user in "Preferences/Users & Groups".
# Add "Russian - PC", "Japanese" in "Preferences/Keyboard/Input Process".
# Configure spectacle hotkeys.
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
