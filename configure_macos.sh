# For Apple Silicon
softwareupdate --install-rosetta --agree-to-license
# XCode command-line tools
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew update --verbose
brew tap homebrew/cask-fonts
# For Python 3.9.1 on Apple Silicon
brew install readline openssl
# For keepassxc-cli
brew install --build-from-source libgpg-error
brew install mas keepassxc karabiner-elements hammerspoon visual-studio-code font-jetbrains-mono-nerd-font microsoft-edge qbittorrent obs mpv iterm2 gimp tor-browser the_silver_searcher michaeldfallen/formula/git-radar exa lsd bat diff-so-fancy
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
# Close any preferences so settings are not overwritten.
osascript -e 'tell application "System Preferences" to quit'
# Show hidden files, folders and extensions.
chflags nohidden ~/Library
defaults write com.apple.finder AppleShowAllFiles YES
defaults write -g AppleShowAllExtensions -bool true
# Keep folders on top while sorting by name in Finder.
defaults write com.apple.finder _FXSortFoldersFirst -bool true
# Change extension without a warning.
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
# Do not create .DS_Store on removable media and network.
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
# Do not verify disk images
defaults write com.apple.frameworks.diskimages skip-verify -bool true
defaults write com.apple.frameworks.diskimages skip-verify-locked -bool true
defaults write com.apple.frameworks.diskimages skip-verify-remote -bool true
# Show Finder path and status bars.
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
# List view for all Finder windows by default
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
# Disable empty trash warning
defaults write com.apple.finder WarnOnEmptyTrash -bool false
# Enable keyboard repeat, need to restart after that.
defaults write -g ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
# Prevent OS from changing text being entered.
defaults write -g NSAutomaticCapitalizationEnabled -bool false
defaults write -g NSAutomaticDashSubstitutionEnabled -bool false
defaults write -g NSAutomaticPeriodSubstitutionEnabled -bool false
defaults write -g NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write -g NSAutomaticSpellingCorrectionEnabled -bool false
# Max touchpad speed that can be set via GUI, cli can go beyound than.
defaults write -g com.apple.trackpad.scaling 3
# Switch off typing disable while trackpad is in use.
defaults write com.apple.applemultitouchtrackpad TrackpadHandResting -int 0
# Save to disk instead of iCloud by default.
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
# Disable the app open confirmation.
defaults write com.apple.LaunchServices LSQuarantine -bool false
# Input langauges and locale
defaults write -g AppleLanguages -array "en" "ru" "ja"
defaults write -g AppleLocale -string "en_RU"
# Minimize windows into apps
defaults write com.apple.dock minimize-to-application -bool true
# Instant dock auto hiding
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0
# No recent apps in dock
defaults write com.apple.dock show-recents -bool false
# Time zone from "sudo systemsetup -listtimezones"
sudo systemsetup -settimezone "Europe/Moscow" > /dev/null
# Wake on lid open
sudo pmset -a lidwake 1
# Restart on freeze
sudo systemsetup -setrestartfreeze on
# No sleep
sudo pmset -a displaysleep 0
sudo pmset -a sleep 0
# Require password
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0
# Don't send search queries to Apple
defaults write com.apple.Safari UniversalSearchEnabled -bool false
defaults write com.apple.Safari SuppressSearchSuggestions -bool true
# Show full URL in Safari address bar
defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
# Safari home page
defaults write com.apple.Safari HomePage -string "about:blank"
# Do not open files after downloading in Safari
defaults write com.apple.Safari AutoOpenSafeDownloads -bool false
# Hide Safari bookmarks bar
defaults write com.apple.Safari ShowFavoritesBar -bool false
# Enable Safari debug and develop menus.
defaults write com.apple.Safari IncludeInternalDebugMenu -bool true
defaults write com.apple.Safari IncludeDevelopMenu -bool true
# Safari search on page with "contains"
defaults write com.apple.Safari FindOnPageMatchesWordStartsOnly -bool false
# Disable Safari auto correct
defaults write com.apple.Safari WebAutomaticSpellingCorrectionEnabled -bool false
# Disable Safari auto fill
defaults write com.apple.Safari AutoFillFromAddressBook -bool false
defaults write com.apple.Safari AutoFillPasswords -bool false
defaults write com.apple.Safari AutoFillCreditCardData -bool false
defaults write com.apple.Safari AutoFillMiscellaneousForms -bool false
# Block pop-ups in Safari
defaults write com.apple.Safari WebKitJavaScriptCanOpenWindowsAutomatically -bool false
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically -bool false
# Copy email without name in Mail
defaults write com.apple.mail AddressesIncludeNameOnPasteboard -bool false
# Disable inline attachments in Mail
defaults write com.apple.mail DisableInlineAttachmentViewing -bool true
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
export PATH="$HOME/.rbenv/bin:$PATH"
export PATH="$HOME/.rbenv/bin:$PATH"
export PATH="$HOME/.rbenv/bin:$PATH"
export PATH="$HOME/.rbenv/bin:$PATH"
pyenv install 3.9.6
pyenv global 3.9.6
python3 -m pip install --upgrade pip virtualenv
rbenv install 3.0.2
rbenv global 3.0.2
nodenv install 17.0.1
nodenv global 17.0.1