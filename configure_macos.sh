export HOMEBREW_NO_ASK=1
# Suppress "run brew ..." hints printed after each install
export HOMEBREW_NO_ENV_HINTS=1

# Wox runs under a crash supervisor that relaunches a child killed by signal
_wox_quit() {
  if ! pgrep -x wox >/dev/null; then
    return 0
  fi
  osascript \
    -e 'ignoring application responses' \
    -e 'tell application "Wox" to quit' \
    -e 'end ignoring'
  i=0
  while pgrep -x wox >/dev/null; do
    if [ $i -ge 100 ]; then
      echo "❌ Wox did not quit, aborting" >&2
      exit 1
    fi
    sleep 0.2
    i=$((i+1))
  done
}

_wox_db_ready() {
  [ -e "$1" ] || return 1
  tables=$(sqlite3 "$1" "select name from sqlite_master where type='table'
    and name in ('wox_settings','plugin_settings');" 2>/dev/null | wc -l)
  [ "$tables" -eq 2 ]
}

_configure_wox() {
  echo "Configuring Wox..."
  # Wox writes '~/Library/LaunchAgents/com.github.wox.plist' to autostart but
  # does not create the directory, missing on a fresh macOS account: without
  # it Wox reconciles the autostart setting back to "off" after the import
  mkdir -p "$HOME/Library/LaunchAgents"
  db="$HOME/.wox/wox-user/wox.db"
  if ! _wox_db_ready "$db"; then
    open -a Wox
    i=0
    while [ $i -lt 100 ]; do
      port=$(cat "$HOME/.wox/wox.lock" 2>/dev/null)
      if [ -n "$port" ] && curl -sf -m 1 "http://127.0.0.1:$port/ping" >/dev/null; then
        break
      fi
      sleep 0.2
      i=$((i+1))
    done
    # The control port answers before the schema is written.
    i=0
    while ! _wox_db_ready "$db"; do
      if [ $i -ge 100 ]; then
        echo "❌ Wox did not create the schema in '$db', aborting" >&2
        exit 1
      fi
      sleep 0.2
      i=$((i+1))
    done
  fi
  # A running Wox keeps settings in memory and writes them back on exit,
  # silently discarding the import
  _wox_quit
  if ! sqlite3 "$db" < "$HOME/dotfiles/wox-settings.sql"; then
    echo "❌ Failed to import '$HOME/dotfiles/wox-settings.sql', aborting" >&2
    exit 1
  fi
  echo "Wox configured"
}

# Install packages one by one: a failure then names the package and stops
# the script instead of being lost in the output of a long brew install.
_brew_install() {
  opts=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --*) opts="$opts $1"; shift ;;
      *) break ;;
    esac
  done
  for pkg in "$@"; do
    # Tap-qualified names like "user/formula/pkg" are listed by the last part
    name="${pkg##*/}"
    if brew list --formula --versions "$name" > /dev/null 2>&1 \
      || brew list --cask --versions "$name" > /dev/null 2>&1; then
      echo "$name already installed"
      continue
    fi
    if ! brew install $opts "$pkg"; then
      echo "❌ Failed to install $pkg, aborting" >&2
      exit 1
    fi
  done
}

# Homebrew dropped the cask: recent macOS refuses to run the unsigned app
# installed by it. Hardcoded aarch64 build from
# sourceforge.net/p/doublecmd/wiki/Download
_install_doublecmd() {
  if [ -e "/Applications/Double Commander.app" ]; then
    echo "Double Commander already installed"
    return 0
  fi
  ver="1.2.9"
  dmg="doublecmd-$ver.cocoa.aarch64.dmg"
  url="https://sourceforge.net/projects/doublecmd/files/Double%20Commander"
  url="$url/v$ver/$dmg/download"
  echo "Downloading Double Commander $ver..."
  if ! curl -LSs -o "./$dmg" "$url"; then
    echo "❌ Failed to download '$url', aborting" >&2
    exit 1
  fi
  if ! hdiutil attach "./$dmg" -nobrowse 1>/dev/null; then
    echo "❌ Failed to mount './$dmg', aborting" >&2
    rm "./$dmg"
    exit 1
  fi
  echo "Installing Double Commander..."
  cp -R "/Volumes/Double Commander/Double Commander.app" /Applications/
  ret=$?
  hdiutil detach "/Volumes/Double Commander" 1>/dev/null
  rm "./$dmg"
  if [ $ret -ne 0 ]; then
    echo "❌ Failed to copy Double Commander into /Applications, aborting" >&2
    exit 1
  fi
}

_install_hey() {
  if [ -e /Applications/HEY.app ]; then
    echo "HEY.com already installed"
    return 0
  fi
  dmg="HEY-arm64.dmg"
  url="https://www.hey.com/desktop/$dmg"
  echo "Downloading HEY.com client..."
  # Without -f curl happily saves an HTTP error page as the .dmg
  if ! curl -fLSs -o "./$dmg" "$url"; then
    echo "❌ Failed to download '$url', aborting" >&2
    exit 1
  fi
  # Volume name carries the version, so take it from the mount output
  vol=$(hdiutil attach "./$dmg" -nobrowse | grep -o '/Volumes/.*' | tail -1)
  if [ -z "$vol" ]; then
    echo "❌ Failed to mount './$dmg', aborting" >&2
    rm "./$dmg"
    exit 1
  fi
  echo "Installing HEY.com..."
  cp -R "$vol/HEY.app" /Applications/
  ret=$?
  hdiutil detach "$vol" 1>/dev/null
  rm "./$dmg"
  if [ $ret -ne 0 ]; then
    echo "❌ Failed to copy HEY.app into /Applications, aborting" >&2
    exit 1
  fi
}

# Input method name lookup for debug purpose
_install_im_select() {
  if [ -e ~/.local/bin/im-select ]; then
    echo "im-select already installed"
    return 0
  fi
  # Upstream install_mac.sh writes into root-owned /usr/local/bin and ignores
  # the failure, so fetch the binary ourselves
  url="https://raw.githubusercontent.com/daipeihust/im-select/master/macOS/out"
  if [ "$(uname -m)" = "arm64" ]; then
    url="$url/apple/im-select"
  else
    url="$url/intel/im-select"
  fi
  echo "Downloading im-select..."
  mkdir -p ~/.local/bin/
  if ! curl -fLSs -o ~/.local/bin/im-select "$url"; then
    echo "❌ Failed to download '$url', aborting" >&2
    rm -f ~/.local/bin/im-select
    exit 1
  fi
  chmod +x ~/.local/bin/im-select
}

_dock_tile() {
  # Emits one "persistent-apps" tile, which is what a "keep in dock" icon is.
  # Only the app url is given: the Dock fills in the rest of the fields
  # ("GUID", "book", "file-label") on restart.
  cat <<EOF
    <dict>
      <key>tile-type</key><string>file-tile</string>
      <key>tile-data</key>
      <dict>
        <key>file-data</key>
        <dict>
          <key>_CFURLString</key><string>file://$1/</string>
          <key>_CFURLStringType</key><integer>15</integer>
        </dict>
      </dict>
    </dict>
EOF
}

_symbolic_hotkey() {
  id=$1 enabled=$2 char=$3 keycode=$4 modifiers=$5
  # A macOS system shortcut is a numeric id in the AppleSymbolicHotKeys
  # dictionary. The key combination is always stored, even for a disabled
  # shortcut: without it the GUI shows the shortcut as unassigned instead of
  # disabled, and re-enabling it in the GUI is then impossible.
  # "char" is the unicode code point the key produces without shift (-1 for
  # keys that produce none), "keycode" is the hardware key and "modifiers" is
  # a bit mask: shift 0x20000, control 0x40000, option 0x80000, cmd 0x100000.
  # 65535 in "char"/"keycode" means "no key".
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$id" "
    <dict>
      <key>enabled</key><$enabled/>
      <key>value</key>
      <dict>
        <key>type</key><string>standard</string>
        <key>parameters</key>
        <array>
          <integer>$char</integer>
          <integer>$keycode</integer>
          <integer>$modifiers</integer>
        </array>
      </dict>
    </dict>"
}

_input_source_layout() {
  # Emits one "AppleEnabledInputSources" entry for a plain keyboard layout.
  # The numeric id is Apple's id of the layout resource and must match the
  # name, otherwise the system drops the entry.
  cat <<EOF
    <dict>
      <key>InputSourceKind</key><string>Keyboard Layout</string>
      <key>KeyboardLayout ID</key><integer>$2</integer>
      <key>KeyboardLayout Name</key><string>$1</string>
    </dict>
EOF
}

_configure_input_sources() {
  # Writing the whole array keeps this idempotent, unlike "-array-add".
  # Order here is the order of the input menu. Kotoeri needs two entries:
  # the input method itself and the mode it starts in; "RomajiTyping" plus
  # the "Japanese" mode is what the GUI calls "Japanese - Romaji".
  defaults write com.apple.HIToolbox AppleEnabledInputSources -array \
    "$(_input_source_layout ABC 252)" \
    "$(_input_source_layout RussianWin 19458)" \
    '<dict>
       <key>Bundle ID</key>
       <string>com.apple.inputmethod.Kotoeri.RomajiTyping</string>
       <key>Input Mode</key>
       <string>com.apple.inputmethod.Japanese</string>
       <key>InputSourceKind</key><string>Input Mode</string>
     </dict>' \
    '<dict>
       <key>Bundle ID</key>
       <string>com.apple.inputmethod.Kotoeri.RomajiTyping</string>
       <key>InputSourceKind</key><string>Keyboard Input Method</string>
     </dict>'
  # The menu bar caches the list
  killall TextInputMenuAgent 2>/dev/null || true
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
  # For Python 3.10.0 on Apple Silicon
  _brew_install readline openssl
  # For PHP
  _brew_install autoconf
  # For Ruby 3.2
  _brew_install libyaml
  # For keepassxc-cli
  _brew_install --build-from-source libgpg-error
  # Install into applications, not as a cli
  _brew_install --cask docker tailscale
  _brew_install mas keepassxc karabiner-elements hammerspoon visual-studio-code font-jetbrains-mono-nerd-font google-chrome obs iterm2 gimp brave-browser the_silver_searcher michaeldfallen/formula/git-radar lsd eza bat diff-so-fancy uv notunes chatgpt slack whatsapp discord lunar elgato-control-center mimestream vlc zoom notion notion-calendar eqmac zsh-autosuggestions zsh-syntax-highlighting wox linearmouse llm lm-studio mactop linear-linear mise fzf claude-code codex

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

  _install_hey

  _install_doublecmd

  _install_im_select

  mise use -g python@3.14.5
  mise use -g node@24.16.0
  mise use -g ruby@4.0.5
  # No prebuilt binaries, fails to compile from source
  _brew_install php
  mise use -g swift@6.3

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
    echo "Sign in to GitHub via Chrome and press enter for TOTP code"
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

  if [ -e ~/.xi ]; then
    echo "Knowledge base already cloned"
  elif [ -e ~/.ssh/.uploaded_to_github ]; then
    git clone git@github.com:grigoryvp/xi.git ~/.xi
  else
    echo "Not cloning knowledge base since ssh keys are not uploaded"
  fi

  # Machine-specific Claude config
  printf 'export ANTHROPIC_MODEL=opus\n' > ~/.env

  printf '#!/bin/sh\n. ~/dotfiles/shell-cfg.sh\n' > ~/.bashrc
  printf '#!/bin/sh\n. ~/dotfiles/shell-cfg.sh\n' > ~/.zshrc
  printf '#!/bin/sh\n. ~/.bashrc\n' > ~/.bash_profile
  printf '[include]\npath = ~/dotfiles/git-cfg.toml\n' > ~/.gitconfig
  if ! [ -e ~/.hammerspoon ]; then
    mkdir ~/.hammerspoon
  fi
  ln -fs ~/dotfiles/hammerspoon/init.lua ~/.hammerspoon/init.lua

  # Use Claude as source-of-truth
  if [ -e ~/.claude ]; then
    rm -rf ~/.claude
  fi
  ln -fs ~/dotfiles/.claude ~/.claude
  if [ -e ~/.codex ]; then
    rm -rf ~/.codex
  fi
  ln -fs ~/dotfiles/.codex ~/.codex
  sudo mkdir -p /etc/codex
  sudo ln -fs ~/dotfiles/.codex/user-config.toml /etc/codex/config.toml
  rm -f ~/.codex/prompts ~/.codex/skills
  ln -fs ~/dotfiles/.claude/commands ~/.codex/prompts
  ln -fs ~/dotfiles/.claude/skills ~/.codex/skills
  ln -fs ~/dotfiles/.claude/CLAUDE.md ~/.codex/AGENTS.md

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
  if ! [ -e ~/Library/Application\ Support/iTerm2/Scripts ]; then
    mkdir -p ~/Library/Application\ Support/iTerm2/Scripts
  fi
  rm -f ~/Library/Application\ Support/iTerm2/Scripts/AutoLaunch
  ln -fs ~/dotfiles/iterm/Scripts/AutoLaunch \
         ~/Library/Application\ Support/iTerm2/Scripts/AutoLaunch

  open -a Hammerspoon
  echo "Configure Hammerspoon, ENABLE ACCESSABILITY and press enter"
  read -s
  # Autostart
  hs -c "hs.autoLaunch(true)" >/dev/null

  echo "Configuring VSCode..."
  code --install-extension grigoryvp.language-xi >/dev/null
  code --install-extension grigoryvp.memory-theme >/dev/null
  code --install-extension grigoryvp.goto-link-provider >/dev/null
  code --install-extension grigoryvp.markdown-inline-fence >/dev/null
  code --install-extension grigoryvp.markdown-python-repl-syntax >/dev/null
  code --install-extension grigoryvp.markdown-pandoc-rawattr >/dev/null
  code --install-extension vscodevim.vim >/dev/null
  code --install-extension EditorConfig.EditorConfig >/dev/null
  code --install-extension emmanuelbeziat.vscode-great-icons >/dev/null
  code --install-extension esbenp.prettier-vscode >/dev/null
  code --install-extension formulahendry.auto-close-tag >/dev/null
  code --install-extension dnut.rewrap-revived >/dev/null
  code --install-extension streetsidesoftware.code-spell-checker >/dev/null
  code --install-extension streetsidesoftware.code-spell-checker-russian \
    >/dev/null
  code --install-extension mark-wiemer.vscode-autohotkey-plus-plus >/dev/null
  code --install-extension charliermarsh.ruff >/dev/null
  code --install-extension harrydowning.yaml-embedded-languages >/dev/null
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
  echo "VSCode configured"

  open /Applications/Karabiner-Elements.app
  echo "Add Karabiner to accessability and press enter"
  read -s
  # Entire config dir should be symlinked
  rm -rf ~/.config/karabiner 
  ln -fs ~/dotfiles/karabiner ~/.config/karabiner

  _configure_wox
  open -a Wox

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
  # Use F1..F12 as plain function keys, media control needs "fn"
  defaults write -g com.apple.keyboard.fnState -bool true
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
  _configure_input_sources
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
  osascript -e "set alert volume to 0"
  # Mute volume change feedback
  defaults write -g "com.apple.sound.beep.feedback" -bool false
  # Disable power attach chime
  defaults write com.apple.PowerChime ChimeOnNoHardware -bool true
  killall PowerChime >/dev/null 2>&1
  # Disable screen saver (manually turn off screen by locking the laptop)
  defaults -currentHost write com.apple.screensaver idleTime -int 0

  # Replace all "keep in dock" icons with just these. Finder is not a part of
  # "persistent-apps" and is always shown first, so these land after it.
  defaults write com.apple.dock persistent-apps -array \
    "$(_dock_tile "/System/Applications/System Settings.app")" \
    "$(_dock_tile "/Applications/iTerm.app")" \
    "$(_dock_tile "/Applications/Visual Studio Code.app")" \
    "$(_dock_tile "/Applications/Google Chrome.app")"

  # Disable caps lock alongside its hardware light indicator. Key itself
  # is used as meta by Karabiner. This option is available in Settings under
  # Keyboard/Keyboard Shortcuts/Modifier Keys/Caps Lock.
  # NOTE: Change is not displayed in GUI settings, but works!
  hidutil property --set '{
    "UserKeyMapping": [{
      "HIDKeyboardModifierMappingSrc": 0x700000039,
      "HIDKeyboardModifierMappingDst":0x0}]}' > /dev/null

  # Free cmd+space for Wox by disabling the Spotlight search shortcut
  _symbolic_hotkey 64 false 32 49 1048576   # cmd+space

  # Notification Center
  _symbolic_hotkey 163 true 92 42 1179648   # shift+cmd+backslash

  # Reload hotkeys so the change applies without a re-login
  sysadmin=/System/Library/PrivateFrameworks/SystemAdministration.framework
  "$sysadmin/Resources/activateSettings" -u

  # Apply changes
  killall Dock 2>/dev/null || true
  killall SystemUIServer 2>/dev/null || true

  echo "✅ configuration complete"
}

if [ "$1" = "--test" ]; then
  test
else
  configure
fi
