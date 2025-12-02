open_port() {
  local port=$1
  nc -l localhost $port >/dev/null 2>&1 &
  local pid=$!
  for i in {1..20}; do
    if nc -z localhost $port >/dev/null 2>&1; then
      echo $pid
      return 0
    fi
    sleep 0.05
  done
  kill $pid >/dev/null 2>&1
  return 1
}

_configure_wox() {
  pid=$(open_port 12345)
  kill $pid >/dev/null 2>&1
}

test() {
  _configure_wox
}

configure() {
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
    # This will require sudo access and waits for confirmation
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  # Add homebrew to path for the rest of the script
  eval "$(/opt/homebrew/bin/brew shellenv)"

  # Group settings that require sudo together

  # Disable spotlight for better battery and SSD life:
  sudo mdutil -a -i off
  # Tends to hang with 100% cpu load
  launchctl unload -w /System/Library/LaunchAgents/com.apple.ReportCrash.plist 2>/dev/null
  # Time zone from "sudo systemsetup -listtimezones"
  #! This crashes AFTER setting time zone, this is normal
  sudo systemsetup -settimezone "Europe/Amsterdam" 2>/dev/null
  # Wake on lid open
  sudo pmset -a lidwake 1
  # Restart on freeze
  sudo systemsetup -setrestartfreeze on
  # No sleep if not explicitly instructed to do so
  sudo pmset -a displaysleep 0
  sudo pmset -a sleep 0

  # Don't send search queries to Apple
  sudo defaults write com.apple.Safari UniversalSearchEnabled false
  sudo defaults write com.apple.Safari SuppressSearchSuggestions true
  # Show full URL in Safari address bar
  sudo defaults write com.apple.Safari ShowFullURLInSmartSearchField true
  # Safari home page
  sudo defaults write com.apple.Safari HomePage -string "about:blank"
  # Do not open files after downloading in Safari
  sudo defaults write com.apple.Safari AutoOpenSafeDownloads false
  # Hide Safari bookmarks bar
  sudo defaults write com.apple.Safari ShowFavoritesBar false
  # Enable Safari debug and develop menus.
  sudo defaults write com.apple.Safari IncludeInternalDebugMenu true
  sudo defaults write com.apple.Safari IncludeDevelopMenu true
  # Safari search on page with "contains"
  sudo defaults write com.apple.Safari FindOnPageMatchesWordStartsOnly false
  # Disable Safari auto correct
  sudo defaults write com.apple.Safari WebAutomaticSpellingCorrectionEnabled false
  # Disable Safari auto fill
  sudo defaults write com.apple.Safari AutoFillFromAddressBook false
  sudo defaults write com.apple.Safari AutoFillPasswords false
  sudo defaults write com.apple.Safari AutoFillCreditCardData false
  sudo defaults write com.apple.Safari AutoFillMiscellaneousForms false
  # Block pop-ups in Safari
  sudo defaults write com.apple.Safari WebKitJavaScriptCanOpenWindowsAutomatically false
  sudo defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically false

  brew update --verbose
  # For Deskflow
  brew tap deskflow/homebrew-tap
  # For Wox launcher
  brew tap wox-launcher/wox
  # For Python 3.10.0 on Apple Silicon
  brew install readline openssl
  # For Ruby 3.2
  brew install libyaml
  # For keepassxc-cli
  brew install --build-from-source libgpg-error
  # Install into applications, not as a cli
  brew install --cask mpv docker tailscale 
  brew install mas keepassxc karabiner-elements hammerspoon visual-studio-code font-jetbrains-mono-nerd-font google-chrome qbittorrent obs iterm2 gimp brave-browser the_silver_searcher michaeldfallen/formula/git-radar lsd eza bat diff-so-fancy uv rv notunes chatgpt slack whatsapp discord lunar double-commander elgato-control-center rode-central mimestream vlc zoom notion notion-calendar eqmac deskflow zsh-autosuggestions zsh-syntax-highlighting wox linearmouse llm lm-studio

  # Need to check for network issues
  # brew install orbstack

  if [ -e ~/.local/bin/uvc-util ]; then
    echo "uvc-util already installed"
  else
    echo "Installing uvc-util..."
    CUR_DIR=$(pwd)
    git clone https://github.com/jtfrey/uvc-util.git
    cd uvc-util/src
    gcc -o uvc-util -framework IOKit -framework Foundation uvc-util.m UVCController.m UVCType.m UVCValue.m
    chmod +x uvc-util
    mkdir -p ~/.local/bin/
    cp uvc-util ~/.local/bin/
    cd $CUR_DIR
    rm -rf uvc-util
  fi

  if [ -e /Applications/HEY.app ]; then
    echo "HEY.com already installed"
  else
    # Download and install HEY.com mail app
    echo "Downloading HEY.com client..."
    curl -LOSs "https://hey-desktop.s3.amazonaws.com/HEY-arm64.dmg"
    hdiutil attach "./HEY-arm64.dmg" 1>/dev/null
    vol_name=$(ls /Volumes | grep -E "^HEY.+arm64$")
    echo "Installing ${vol_name} ..."
    cp -R "/Volumes/${vol_name}/HEY.app" /Applications/
    hdiutil detach "/Volumes/${vol_name}" 1>/dev/null
    rm "./HEY-arm64.dmg"
  fi

  # Input method name lookup for debug purpose
  curl -Ls https://raw.githubusercontent.com/daipeihust/im-select/master/install_mac.sh | sh

  if [ -e ~/.nodenv ]; then
    echo "nodenv already installed"
  else
    git clone https://github.com/nodenv/nodenv.git ~/.nodenv
    git clone https://github.com/nodenv/node-build.git ~/.nodenv/plugins/node-build
    git clone https://github.com/nodenv/nodenv-update.git ~/.nodenv/plugins/nodenv-update
  fi

  if [ -e ~/.swiftenv ]; then
    echo "swiftenv already installed"
  else
    git clone https://github.com/kylef/swiftenv.git ~/.swiftenv
  fi

  # Seems not working on macOS, maybe switch to phpvm?
  # git clone https://github.com/phpenv/phpenv.git ~/.phpenv
  # git clone https://github.com/php-build/php-build ~/.phpenv/plugins/php-build
  # git clone https://github.com/jridgewell/phpenv-update ~/.phpenv/plugins/phpenv-update
  # export PATH="$HOME/.phpenv/bin:$PATH"

  export PATH="$HOME/.nodenv/bin:$PATH"
  export PATH="$HOME/.swiftenv/bin:$PATH"
  uv python install 3.13
  rv ruby install 3.4.5
  # Answer "no" to "already installed, continue?"
  echo "n" | nodenv install 23.7.0
  nodenv global 23.7.0

  if [ -e ~/dotfiles ] && [ -e ~/.ssh/.uploaded_to_github ]; then
    echo "Dotfiles already cloned"
  else
    git clone https://github.com/grigoryvp/dotfiles.git ~/dotfiles
    while true; do
      keepassxc-cli show --show-protected \
        --attributes username \
        --attributes password \
        ~/dotfiles/auth/passwords.kdbx github
      if [ $? -eq 0 ]; then
        break
      fi
    done
    echo "Sign in to GitHub and press enter for TOTP code"
    read -s
    while true; do
      keepassxc-cli show --totp ~/dotfiles/auth/passwords.kdbx github
      if [ $? -eq 0 ]; then
        break
      fi
    done
    cat ~/.ssh/id_rsa.pub
    echo "Add ssh to GitHub and press enter"
    read -s
    rm -rf ~/dotfiles
    git clone git@github.com:grigoryvp/dotfiles.git ~/dotfiles
    touch ~/.ssh/.uploaded_to_github
  fi

  if [ -e ~/xi ]; then
    echo "Knowledge base already cloned"
  elif [ -e ~/.ssh/.uploaded_to_github ]; then
    git clone git@github.com:grigoryvp/xi.git ~/.xi
  else
    echo "Not cloning knowledge base since ssh keys are not uploaded"
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

  open -a Hammerspoon
  echo "Configure Hammerspoon and press enter"
  read -s

  code --install-extension grigoryvp.language-xi
  code --install-extension grigoryvp.memory-theme
  code --install-extension grigoryvp.goto-link-provider
  code --install-extension grigoryvp.markdown-inline-fence
  code --install-extension grigoryvp.markdown-python-repl-syntax
  code --install-extension grigoryvp.markdown-pandoc-rawattr
  code --install-extension vscodevim.vim
  code --install-extension EditorConfig.EditorConfig
  code --install-extension emmanuelbeziat.vscode-great-icons
  code --install-extension esbenp.prettier-vscode
  code --install-extension formulahendry.auto-close-tag
  code --install-extension dnut.rewrap-revived
  code --install-extension streetsidesoftware.code-spell-checker
  code --install-extension streetsidesoftware.code-spell-checker-russian
  code --install-extension mark-wiemer.vscode-autohotkey-plus-plus
  VSCODE_DIR=~/Library/Application\ Support/Code/User
  if [ -e "$VSCODE_DIR" ]; then
    echo "'$VSCODE_DIR' already exists"
  else
    echo "Creating '$VSCODE_DIR' ..."
    mkdir -p $VSCODE_DIR
  fi
  ln -fs ~/dotfiles/vscode_keybindings.json "$VSCODE_DIR/keybindings.json"
  ln -fs ~/dotfiles/vscode_settings.json "$VSCODE_DIR/settings.json"
  ln -fs ~/dotfiles/vscode_tasks.json "$VSCODE_DIR/tasks.json"
  rm -rf "$VSCODE_DIR/snippets"
  ln -fs ~/dotfiles/vscode_snippets "$VSCODE_DIR/snippets"

  mkdir -p ~/.config/mpv
  echo "save-position-on-quit" > ~/.config/mpv/mpv.conf
  echo "loop-file=inf" >> ~/.config/mpv/mpv.conf
  open /Applications/Karabiner-Elements.app
  echo "Add Karabiner to accessability and press enter"
  read -s
  # Entire config dir should be symlinked
  rm -rf ~/.config/karabiner 
  ln -fs ~/dotfiles/karabiner ~/.config/karabiner

  _configure_wox

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
  # Max touchpad speed that can be set via GUI, cli can go beyond than.
  defaults write -g com.apple.trackpad.scaling 3
  # Switch off typing disable while trackpad is in use.
  defaults write com.apple.applemultitouchtrackpad TrackpadHandResting -int 0
  # Save to disk instead of iCloud by default.
  defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud false
  # Disable the app open confirmation.
  defaults write com.apple.LaunchServices LSQuarantine false
  # Input languages and locale
  defaults write -g AppleLanguages -array "en" "ru" "ja"
  defaults write -g AppleLocale -string "en_RU"
  # Instant dock auto hiding
  defaults write com.apple.dock autohide true
  defaults write com.apple.dock autohide-delay -float 0
  defaults write com.apple.dock autohide-time-modifier -float 0
  # No recent apps in dock
  defaults write com.apple.dock show-recents false
  # Require password
  defaults write com.apple.screensaver askForPassword -int 1
  defaults write com.apple.screensaver askForPasswordDelay -int 0
  # Copy email without name in Mail
  defaults write com.apple.mail AddressesIncludeNameOnPasteboard false
  # Disable inline attachments in Mail
  defaults write com.apple.mail DisableInlineAttachmentViewing true
  # "Continuos scroll" by default for PDF preview
  defaults write com.apple.Preview kPVPDFDefaultPageViewModeOption 0
  # Don't auto-show dock on mouse hover (m1-slash instead)
  defaults write com.apple.dock autohide-delay -float 999999
  # Change slow "Genie" dock minimize animation to fast "Scale"
  defaults write com.apple.dock "mineffect" -string "scale" && killall Dock
  # Disable "animate opening applications"
  defaults write com.apple.dock launchanim -bool false
  # Disable "show suggested and recent applications in Dock"
  defaults write com.apple.dock show-recents -bool false
  # Disable Mission Control "hot corners" (they trigger accidentally a lot)
  defaults write com.apple.dock wvous-tl-corner -int 0
  defaults write com.apple.dock wvous-tr-corner -int 0
  defaults write com.apple.dock wvous-bl-corner -int 0
  defaults write com.apple.dock wvous-br-corner -int 0
  # Auto-hide dock to get more vertical space (everything is on hotkeys)
  defaults write com.apple.dock autohide -bool true
  # Mute alerts
  osascript -e "set volume alert volume 0"
  # Mute volume change feedback
  defaults write -g "com.apple.sound.beep.feedback" -bool false
  # Disable screen saver (manually turn off screen by locking the laptop)
  defaults -currentHost write com.apple.screensaver idleTime -int 0

  # Remove all dock icons
  defaults write com.apple.dock persistent-apps -array ""

  # Apply changes
  killall Dock
  killall SystemUIServer
}

if [ "$1" = "--test" ]; then
  test
else
  configure
fi
