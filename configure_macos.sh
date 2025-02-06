if ! [ -e ~/.ssh/id_rsa.pub ]; then
  ssh-keygen -t rsa -f "$HOME/.ssh/id_rsa" -N ""
fi
if ! [ -e ~/.ssh/known_hosts ]; then
  # Allows git clone without fingerprint confirmation
  ssh-keyscan github.com >> ~/.ssh/known_hosts
fi
# For Apple Silicon
softwareupdate --install-rosetta --agree-to-license
# XCode command-line tools
xcode-select --install
echo "Wait for the xcode-select GUI installer and press enter"
read -s
if [ -e /opt/homebrew/bin/brew ]; then
  echo "Homebrew already installed"
else
  yes "" | /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Add homebrew to path for the rest of the script
eval "$(/opt/homebrew/bin/brew shellenv)"
brew update --verbose
brew tap homebrew/cask-fonts
# For Python 3.10.0 on Apple Silicon
brew install readline openssl
# For Ruby 3.2
brew install libyaml
# For keepassxc-cli
brew install --build-from-source libgpg-error
# Install into applications, not as a cli
brew install mpv --cask
brew install mas keepassxc karabiner-elements hammerspoon visual-studio-code font-jetbrains-mono-nerd-font google-chrome qbittorrent obs iterm2 gimp brave-browser the_silver_searcher michaeldfallen/formula/git-radar exa lsd bat diff-so-fancy uv notunes chatgpt slack whatsapp discord lunar tailscale docker double-commander elgato-control-center rode-central mimestream vlc zoom

# Need to check for network issues
# brew install orbstack
if [ -e ~/dotfiles ]; then
  echo "Dotfiles already cloned"
else
  git clone https://github.com/grigoryvp/dotfiles.git ~/dotfiles
  echo "Press enter to confirm KeePassXC and view GitHub password"
  read -s
  open /Applications/KeePassXC.app ~/dotfiles/passwords.kdbx
  keepassxc-cli show -s ~/dotfiles/passwords.kdbx github
  cat ~/.ssh/id_rsa.pub
  echo "Add ssh to GitHub and press enter"
  read -s
  rm -rf ~/dotfiles
  git clone git@github.com:grigoryvp/dotfiles.git ~/dotfiles
fi
if [ -e ~/xi ]; then
  echo "Knowledge base already cloned"
else
  git clone git@github.com:grigoryvp/xi.git ~/.xi
fi
printf '#!/bin/sh\n. ~/dotfiles/shell-cfg.sh\n' > ~/.bashrc
printf '#!/bin/sh\n. ~/dotfiles/shell-cfg.sh\n' > ~/.zshrc
printf '#!/bin/sh\n. ~/.bashrc\n' > ~/.bash_profile
printf '[include]\npath = ~/dotfiles/git-cfg.toml\n' > ~/.gitconfig
if ! [ -e ~/.hammerspoon ]; then
  mkdir ~/.hammerspoon
fi
ln -fs ~/dotfiles/hammerspoon/init.lua ~/.hammerspoon/init.lua
ln -fs ~/dotfiles/.screenrc ~/.screenrc
ln -fs ~/dotfiles/.gitattributes ~/.gitattributes
ln -fs ~/dotfiles/.rubocop.yml ~/.rubocop.yml
if ! [ -e ~/.config/lsd ]; then
  mkdir -p ~/.config/lsd
fi
ln -fs ~/dotfiles/lsd.config.yaml ~/.config/lsd/config.yaml
if ! [ -e ~/.config/powershell ]; then
  mkdir -p ~/.config/powershell
fi
ln -fs ~/dotfiles/profile.ps1 ~/.config/powershell/profile.ps1
code --install-extension grigoryvp.language-xi
code --install-extension grigoryvp.memory-theme
code --install-extension grigoryvp.goto-link-provider
code --install-extension vscodevim.vim
code --install-extension EditorConfig.EditorConfig
code --install-extension emmanuelbeziat.vscode-great-icons
code --install-extension esbenp.prettier-vscode
code --install-extension formulahendry.auto-close-tag
VSCODE_DIR=~/Library/Application\ Support/Code/User
ln -fs ~/dotfiles/vscode_keybindings.json $VSCODE_DIR/keybindings.json
ln -fs ~/dotfiles/vscode_settings.json $VSCODE_DIR/settings.json
ln -fs ~/dotfiles/vscode_tasks.json $VSCODE_DIR/tasks.json
ln -fs ~/dotfiles/vscode_snippets $VSCODE_DIR/snippets
mkdir -p ~/.config/mpv
echo "save-position-on-quit" > ~/.config/mpv/mpv.conf
echo "loop-file=inf" >> ~/.config/mpv/mpv.conf
open /Applications/Karabiner-Elements.app
echo "1) Add 'karabiner_grabber', 'karabiner_observer' for 'Input Monitoring'"
echo "2) Allow '.Karabiner-...Manager.app' in 'Security & Privacy'"
echo "3) Complete the 'Keyboard Setup Assistant'"
echo "4) Press enter"
read -s
# Entire config dir should be symlinked
rm -rf ~/.config/karabiner 
ln -fs ~/dotfiles/karabiner ~/.config/karabiner

# Amphetamine
mas install 937984704
# Windows App (RDP client)
mas install 1295203466

echo "Installing uvc-util..."
git clone https://github.com/jtfrey/uvc-util.git
cd uvc-util/src
gcc -o uvc-util -framework IOKit -framework Foundation uvc-util.m UVCController.m UVCType.m UVCValue.m
chmod +x uvc-util
cp uvc-util /Users/user/.local/bin/

# Download and install HEY.com mail app
echo "Downloading HEY.com client..."
curl -LOSs "https://hey-desktop.s3.amazonaws.com/HEY-arm64.dmg"
hdiutil attach "./HEY-arm64.dmg" 1>/dev/null
vol_name=$(ls /Volumes | grep -E "^HEY.+arm64$")
echo "Installing ${vol_name} ..."
cp -R "/Volumes/${vol_name}/HEY.app" /Applications/
hdiutil detach "/Volumes/${vol_name}" 1>/dev/null
rm "./HEY-arm64.dmg"

# Input method name lookup for debug purpose
curl -Ls https://raw.githubusercontent.com/daipeihust/im-select/master/install_mac.sh | sh

git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
git clone https://github.com/rkh/rbenv-update ~/.rbenv/plugins/rbenv-update
git clone https://github.com/nodenv/nodenv.git ~/.nodenv
git clone https://github.com/nodenv/node-build.git ~/.nodenv/plugins/node-build
git clone https://github.com/nodenv/nodenv-update.git ~/.nodenv/plugins/nodenv-update
git clone https://github.com/phpenv/phpenv.git ~/.phpenv
git clone https://github.com/php-build/php-build ~/.phpenv/plugins/php-build
git clone https://github.com/jridgewell/phpenv-update ~/.phpenv/plugins/phpenv-update
git clone https://github.com/kylef/swiftenv.git ~/.swiftenv
export PATH="$HOME/.rbenv/bin:$PATH"
export PATH="$HOME/.nodenv/bin:$PATH"
export PATH="$HOME/.phpenv/bin:$PATH"
export PATH="$HOME/.swiftenv/bin:$PATH"
uv python install 3.13
rbenv install 3.2.0
rbenv global 3.2.0
nodenv install 22.2.0
nodenv global 22.2.0

# Disable spotlight for better battery and SSD life:
sudo mdutil -a -i off
# Close any preferences so settings are not overwritten.
osascript -e 'tell application "System Preferences" to quit'
# Show hidden files, folders and extensions.
chflags nohidden ~/Library
defaults write com.apple.finder AppleShowAllFiles YES
defaults write -g AppleShowAllExtensions true
# Keep folders on top while sorting by name in Finder.
defaults write com.apple.finder _FXSortFoldersFirst true
# Change extension without a warning.
defaults write com.apple.finder FXEnableExtensionChangeWarning false
# Do not create .DS_Store on removable media and network.
defaults write com.apple.desktopservices DSDontWriteNetworkStores true
defaults write com.apple.desktopservices DSDontWriteUSBStores true
# Do not verify disk images
defaults write com.apple.frameworks.diskimages skip-verify true
defaults write com.apple.frameworks.diskimages skip-verify-locked true
defaults write com.apple.frameworks.diskimages skip-verify-remote true
# Show Finder path and status bars.
defaults write com.apple.finder ShowPathbar true
defaults write com.apple.finder ShowStatusBar true
# List view for all Finder windows by default
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
# Disable empty trash warning
defaults write com.apple.finder WarnOnEmptyTrash false
# Enable keyboard repeat, need to restart after that.
defaults write -g ApplePressAndHoldEnabled false
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
# Prevent OS from changing text being entered.
defaults write -g NSAutomaticCapitalizationEnabled false
defaults write -g NSAutomaticDashSubstitutionEnabled false
defaults write -g NSAutomaticPeriodSubstitutionEnabled false
defaults write -g NSAutomaticQuoteSubstitutionEnabled false
defaults write -g NSAutomaticSpellingCorrectionEnabled false
# Max touchpad speed that can be set via GUI, cli can go beyound than.
defaults write -g com.apple.trackpad.scaling 3
# Switch off typing disable while trackpad is in use.
defaults write com.apple.applemultitouchtrackpad TrackpadHandResting -int 0
# Save to disk instead of iCloud by default.
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud false
# Disable the app open confirmation.
defaults write com.apple.LaunchServices LSQuarantine false
# Input langauges and locale
defaults write -g AppleLanguages -array "en" "ru" "ja"
defaults write -g AppleLocale -string "en_RU"
# Minimize windows into apps
defaults write com.apple.dock minimize-to-application true
# Instant dock auto hiding
defaults write com.apple.dock autohide true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0
# No recent apps in dock
defaults write com.apple.dock show-recents false
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
defaults write com.apple.Safari UniversalSearchEnabled false
defaults write com.apple.Safari SuppressSearchSuggestions true
# Show full URL in Safari address bar
defaults write com.apple.Safari ShowFullURLInSmartSearchField true
# Safari home page
defaults write com.apple.Safari HomePage -string "about:blank"
# Do not open files after downloading in Safari
defaults write com.apple.Safari AutoOpenSafeDownloads false
# Hide Safari bookmarks bar
defaults write com.apple.Safari ShowFavoritesBar false
# Enable Safari debug and develop menus.
defaults write com.apple.Safari IncludeInternalDebugMenu true
defaults write com.apple.Safari IncludeDevelopMenu true
# Safari search on page with "contains"
defaults write com.apple.Safari FindOnPageMatchesWordStartsOnly false
# Disable Safari auto correct
defaults write com.apple.Safari WebAutomaticSpellingCorrectionEnabled false
# Disable Safari auto fill
defaults write com.apple.Safari AutoFillFromAddressBook false
defaults write com.apple.Safari AutoFillPasswords false
defaults write com.apple.Safari AutoFillCreditCardData false
defaults write com.apple.Safari AutoFillMiscellaneousForms false
# Block pop-ups in Safari
defaults write com.apple.Safari WebKitJavaScriptCanOpenWindowsAutomatically false
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically false
# Copy email without name in Mail
defaults write com.apple.mail AddressesIncludeNameOnPasteboard false
# Disable inline attachments in Mail
defaults write com.apple.mail DisableInlineAttachmentViewing true
# "Continuos scroll" by default for PDF preview
defaults write com.apple.Preview kPVPDFDefaultPageViewModeOption 0
# Don't auto-show dock on mouse hover (m1-slash instead)
defaults write com.apple.dock autohide-delay -float 999999
# Tends to hang with 100% cpu load
launchctl unload -w /System/Library/LaunchAgents/com.apple.ReportCrash.plist

echo "Disable caps via Settings/Keyboard/Shortcuts/Modifier"
