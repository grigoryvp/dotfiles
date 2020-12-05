# My Win, WSL, OSX box auto config

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
printf '[include]\npath = /mnt/c/Users/user/.box-cfg/shell/git-cfg.toml\n' >> ~/.gitconfig
cp /mnt/c/Users/user/.box-cfg/shell/.gitattributes ~/.gitattributes
```

## OSX

```ps1
softwareupdate --install-rosetta --agre-to-license
arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
brew update --verbose
brew tap homebrew/cask-fonts
brew cask install keepassxc spectacle karabiner-elements visual-studio-code font-jetbrains-mono menumeters transmission powershell obs mpv bitbar iterm2
arch -x86_64 brew install exa michaeldfallen/formula/git-radar readline xz node
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
rm -f ~/.screenrc
ln ~/.box-cfg/shell/.screenrc ~/.screenrc
rm -f ~/.gitattributes
ln ~/.box-cfg/shell/.gitattributes ~/.gitattributes
printf '[include]\npath = ~/.box-cfg/shell/git-cfg.toml\n' >> ~/.gitconfig
mkdir -p ~/.config/powershell
rm -f ~/.config/powershell/profile.ps1
ln ~/.box-cfg/profile.ps1 ~/.config/powershell/profile.ps1
code --install-extension grigoryvp.language-xi
code --install-extension grigoryvp.memory-theme
code --install-extension vscodevim.vim
code --install-extension EditorConfig.EditorConfig
code --install-extension vscode-icons-team.vscode-icons
ln ~/.box-cfg/vscode_keybindings.json ~/Library/Application\ Support/Code/User/keybindings.json
ln ~/.box-cfg/vscode_settings.json ~/Library/Application\ Support/Code/User/settings.json
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
# Add "Russian-PC", "Japanese-Romaji" in "Preferences/Keyboard/Input Process".
# App store: Snap, Battery Monitor, Telegram Lite, XCode, Affinity.
# Install https://www.marcmoini.com/sx_en.html
# Configure "Snap" for "command-shift-option-control-number".
# Configure "Smart Scroll" for "Grab scroll without moving cursor", button 6.
# Configure "Spectacle" hotkeys.
# Configure iTerm2 theme, set "JetBrains" font, "/usr/local/bin/pwsh" shell
# Menu: spectacle, wifi, bt, clock, short menu, battery monitor, menumeters
# Dock: iTerm2, vscode, browser, files, keepass, telegram lite
# Set max key repeat and min delay at "Preferences/Keyboard"
# Set notification center shortcut to "shift-command-backslash" in "Preferences/Keyboard/Shortcuts".
# Disable "⇧⌘/" in "Preferences/Keyboard/Shortcuts/App Shortcuts".
# Add "⌘w" to "Close Tab" in "Preferences/Keyboard/Shortcuts/App Shortcuts" for Safari.
# Disable corrections in "Preferences/Keyboard/Text".
# Disable sleep in "Preferences/Energy Saver".
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
