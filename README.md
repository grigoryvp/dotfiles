# My Win, WSL2, MacOS box auto config

## Windows install via cmd.exe

```bat
rem Allow PowerShell packages to be installed
powershell.exe -c Set-ExecutionPolicy Unrestricted -scope CurrentUser
rem Install scoop
powershell.exe -c "iwr -useb get.scoop.sh | Invoke-Expression"
set PATH=%PATH%;%USERPROFILE%\scoop\shims
rem Install Powershell Core
scoop install 7zip git pwsh sudo
git config --global core.autocrlf input
rem Configure this box; inspect $error if Invoke-Expression fails.
pwsh.exe -c "Invoke-WebRequest -useb https://raw.githubusercontent.com/grigoryvp/dotfiles/master/configure.ps1 | Invoke-Expression"
```

Follow instructions for post-configuration.

## WSL

```ps1
sudo powershell.exe -c Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
sudo powershell.exe -c Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
# Restart
curl -LOSs https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi
msiexec /i wsl_update_x64.msi
wsl --set-default-version 2
# Install distribution
explorer https://aka.ms/wslstore
```

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
pyenv install 3.9.5
pyenv global 3.9.5
pip install --upgrade pip
```

## OSX

```ps1
# For Apple Silicon
softwareupdate --install-rosetta --agree-to-license
# XCode command-line tools
xcode-select --install
arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
brew update --verbose
brew tap homebrew/cask-fonts
# For Python 3.9.1 on Apple Silicon
brew install readline openssl
# For keepassxc-cli
brew install --build-from-source libgpg-error
brew install mas keepassxc karabiner-elements hammerspoon visual-studio-code font-jetbrains-mono-nerd-font qbittorrent obs mpv iterm2 gimp tor-browser the_silver_searcher michaeldfallen/formula/git-radar exa lsd
# Amphetamine, Xcode
mas install 937984704 497799835
git clone https://github.com/grigoryvp/dotfile.git ~/dotfiles
# Confirm execution of downloaded app.
open /Applications/KeePassXC.app ~/dotfiles/passwords.kdbx
keepassxc-cli show -s ~/dotfiles/passwords.kdbx github
# Add ssh to github
rm -rf ~/dotfiles
git clone git@github.com:grigoryvp/dotfiles.git ~/dotfiles
git clone git@github.com:grigoryvp/xi.git ~/.xi
printf '#!/bin/sh\n. ~/dotfiles/shell-cfg.sh\n' > ~/.bashrc
printf '#!/bin/sh\n. ~/dotfiles/shell-cfg.sh\n' > ~/.zshrc
printf '#!/bin/sh\n. ~/.bashrc\n' > ~/.bash_profile
printf '[include]\npath = ~/dotfiles/git-cfg.toml\n' > ~/.gitconfig
ln -fs ~/dotfiles/hammerspoon/init.lua ~/.hammerspoon/init.lua
ln -fs ~/dotfiles/.screenrc ~/.screenrc
ln -fs ~/dotfiles/.gitattributes ~/.gitattributes
mkdir -p ~/.config/lsd
ln -fs ~/dotfiles/lsd.config.yaml ~/.config/lsd/config.yaml
mkdir -p ~/.config/powershell
ln -fs ~/dotfiles/profile.ps1 ~/.config/powershell/profile.ps1
code --install-extension grigoryvp.language-xi
code --install-extension grigoryvp.memory-theme
code --install-extension vscodevim.vim
code --install-extension EditorConfig.EditorConfig
ln -fs ~/dotfiles/vscode_keybindings.json ~/Library/Application\ Support/Code/User/keybindings.json
ln -fs ~/dotfiles/vscode_settings.json ~/Library/Application\ Support/Code/User/settings.json
# Create config dir.
mpv --help
echo "save-position-on-quit" >> ~/.config/mpv/mpv.conf
# Disable spotlight for better battery and SSD life:
sudo mdutil -a -i off
open /Applications/Karabiner-Elements.app
# Confirm 'karabiner_grabber', 'karabiner_observer' for "Input Monitoring".
# From '/Library/Application Support/org.pqrs/Karabiner-Elements/bin'
# Karabiner can't detect config file change if linked via symlink.
ln -f ~/dotfiles/karabiner.json ~/.config/karabiner/karabiner.json
# Enable keyboard repeat, need to restart after that
defaults write -g ApplePressAndHoldEnabled -bool false
defaults write -g NSAutomaticCapitalizationEnabled -bool false
# Max touchpad speed that can be set via GUI, cli can go beyound than.
defaults write -g com.apple.trackpad.scaling 3
# Switch off typing disable while trackpad is in use.
defaults write com.apple.applemultitouchtrackpad TrackpadHandResting -int 0
# Input method name lookup for debug purpose
curl -Ls https://raw.githubusercontent.com/daipeihust/im-select/master/install_mac.sh | sh
git clone https://github.com/pyenv/pyenv.git ~/.pyenv
git clone https://github.com/pyenv/pyenv-virtualenv.git ~/.pyenv/plugins/pyenv-virtualenv
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
git clone https://github.com/nodenv/nodenv.git ~/.nodenv
git clone https://github.com/nodenv/node-build.git ~/.nodenv/plugins/node-build
git clone https://github.com/phpenv/phpenv.git ~/.phpenv
git clone https://github.com/php-build/php-build ~/.phpenv/plugins/php-build
# Reload shell
pyenv install 3.9.5
pyenv global 3.9.5
pip install --upgrade pip
rbenv install 3.0.1
rbenv global 3.0.1
nodenv install 16.0.0
nodenv global 16.0.0
# phpenv install 8.0.3 # https://github.com/phpenv/phpenv/issues/90
# phpenv global 8.0.3 # https://github.com/phpenv/phpenv/issues/90
# Add "Russian-PC", "Japanese-Romaji" in "Preferences/Keyboard/Input Process".
# Install https://macos.telegram.org/
# Configure Amphetamine autostart and auto session on start and wake.
# Configure iTerm2 theme, set "JetBrainsMono Nerd Font".
# Menu: hammerspoon, amphetamine, command center, time
# Drop "/System/Library/CoreServices/Finder.app" into dock.
# Dock: iTerm2, vscode, browser, Finder, Keepass, Telegram lite
# Set max key repeat and min delay in "Preferences/Keyboard"
# Set "⇧⌘\" to "Notification Center" in "Preferences/Keyboard/Shortcuts".
# In "Preferences/Keyboard/Shortcuts/App Shortcuts":
# * Remove "⇧⌘/"
# * Add "⌘W" to "Close Tab" for "Safari".
# * Add "⌥⇧⌘V" to "Paste and Match Style" for "Telegram".
# In "Preferenes/Dock & Menu Bar" remove all icons except 24h clock.
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
