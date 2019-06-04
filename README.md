# My windows and OSX box automatic configuration

## Windows

Install PowerShell Core from [releases](https://github.com/PowerShell/PowerShell/releases) page.

```ps1
cd ~; Invoke-WebRequest -OutFile configure.ps1 -Uri https://raw.githubusercontent.com/grigoryvp/box-cfg/master/configure.ps1; & .\configure.ps1
```

Follow instructions for post-configuration.

## OSX

```ps1
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
brew update --verbose
brew tap homebrew/cask-fonts
brew cask install keepassxc spectacle karabiner-elements visual-studio-code font-monoid yujitach-menumeters itsycal transmission powershell obs vlc zoomus
brew install exa node michaeldfallen/formula/git-radar readline xz pyenv rbenv
npm i -g git-alias
git clone https://github.com/grigoryvp/box-cfg.git ~/.box-cfg
keepassxc-cli show ~/.box-cfg/passwords.kdbx github
# Add ssh to github
rm -rf ~/.box-cfg
git clone git@github.com:grigoryvp/box-cfg.git ~/.box-cfg
git clone git@github.com:grigoryvp/xi.git ~/.xi
# Menu bar, from right to left:
# spectacle, wifi, bt, clock, itsycal, short menu, battery monitor, menumeters
curl -Ls https://raw.githubusercontent.com/daipeihust/im-select/master/install_mac.sh | sh
curl -Ls https://raw.githubusercontent.com/dracula/terminal-app/master/Dracula.terminal > ~/Downloads/Dracula.terminal
open ~/Downloads/Dracula.terminal
rm -rf ~/Downloads/Dracula.terminal
ln ~/.box-cfg/shell/.bashrc ~/.bashrc
printf '#!/bin/sh\n. ~/.bashrc\n' > ~/.bash_profile
ln ~/.box-cfg/shell/.screenrc ~/.screenrc
ln ~/.box-cfg/shell/.gitconfig ~/.gitconfig
ln ~/.box-cfg/vscode_keybindings.json ~/Library/Application\ Support/Code/User/keybindings.json
ln ~/.box-cfg/vscode_settings.json ~/Library/Application\ Support/Code/User/settings.json
cp ~/.box-cfg/karabiner.json ~/.config/karabiner/karabiner.json
cp ~/.box-cfg/osx/automator/* ~/Library/Services/
cp ~/.box-cfg/osx/pbs.plist ~/Library/Preferences/pbs.plist
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
xcode-select --install
export CFLAGS="-I$(xcrun --show-sdk-path)/usr/include"
pyenv init
echo 'eval "$(pyenv init -)"' >> ~/.bash_profile
pyenv install 3.7.3
pyenv global 3.7.3
rbenv init
echo 'eval "$(rbenv init -)"' >> ~/.bash_profile
rbenv install 2.6.2
rbenv global 2.6.2
# Set hotkeys for services
# Install Short Menu, Battery Monitor, XCode, Affinity, Telegram (Not "Telegram Desktop"), Chatty from app store.
# Install tampermonkey for Safari.
# Set max key repeat and min delay at "Preferences/Keyboard"
# Set notification center shortcut in "Preferences/Keyboard/Shortcuts".
# Disable "⇧⌘/" in "Preferences/Keyboard/Shortcuts/App Shortcuts".
# Disable corrections in "Preferences/Keyboard/Text".
# Add "Russian - PC", "Japanese" in "Preferences/Keyboard/Input Process".
# Configure spectacle hotkeys.
# "iTunes/Preferences/Devices/Prevent from syncing automatically"
```

## Todo

* Ignore subsequent "down" events on buttons that emulate mouse buttons.
* Implement "go-to-background" Ctrl-D via PS keyboard hook.
* Install "7+ Taskbar Tweaker".

## License

The following licensing applies to My windows box automatic configuration:
Attribution-NonCommercial-NoDerivatives 4.0 International
(CC BY-NC-ND 4.0). For more information go to
[https://creativecommons.org/licenses/by-nc-nd/4.0/](https://creativecommons.org/licenses/by-nc-nd/4.0/)
