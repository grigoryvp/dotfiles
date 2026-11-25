# Fedora with GNOME. Run as a regular user from the GNOME session: gsettings
# needs the session bus, system-wide changes are made via sudo.

_check_env() {
  if [ "$(id -u)" -eq 0 ]; then
    echo "❌ Run as a regular user, not root, aborting" >&2
    exit 1
  fi
  case ":$XDG_CURRENT_DESKTOP:" in
    *:GNOME:*) ;;
    *)
      echo "❌ GNOME session required, aborting" >&2
      exit 1
      ;;
  esac
}

_lid_external_power() {
  busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
    org.freedesktop.login1.Manager HandleLidSwitchExternalPower 2>/dev/null
}

# Closing the lid on external power only locks the screen and the laptop
# keeps working
_configure_lid() {
  dir=/etc/systemd/logind.conf.d
  file="$dir/lid.conf"
  want='[Login]
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=lock
HandleLidSwitchDocked=ignore'
  if [ "$(cat "$file" 2>/dev/null)" = "$want" ]; then
    echo "Lid switch already configured"
    return 0
  fi
  sudo mkdir -p "$dir"
  printf '%s\n' "$want" | sudo tee "$file" >/dev/null
  # Restarting logind terminates the graphical session, SIGHUP only rereads
  # the config. It is handled asynchronously, so wait for the new value.
  sudo systemctl kill -s HUP systemd-logind
  i=0
  while [ "$(_lid_external_power)" != 's "lock"' ]; do
    if [ $i -ge 50 ]; then
      echo "❌ logind did not apply $file, aborting" >&2
      exit 1
    fi
    sleep 0.1
    i=$((i+1))
  done
  echo "Lid switch configured"
}

_clone_dotfiles() {
  if [ -e ~/dotfiles ]; then
    echo "Dotfiles already cloned"
    return 0
  fi
  sudo dnf install -y git
  git clone https://github.com/grigoryvp/dotfiles.git ~/dotfiles
}

# Built from source as upstream recommends, pinned to a release tag
_install_keyd() {
  if command -v keyd >/dev/null; then
    echo "keyd already installed"
    return 0
  fi
  sudo dnf install -y git gcc make kernel-headers
  dir=$(mktemp -d)
  git clone --depth 1 --branch v2.6.0 https://github.com/rvaiya/keyd "$dir"
  if ! make -C "$dir" || ! sudo make -C "$dir" install; then
    rm -rf "$dir"
    echo "❌ Failed to build keyd, aborting" >&2
    exit 1
  fi
  rm -rf "$dir"
  # The unit lands in /usr/local/lib/systemd/system, unseen until reload
  sudo systemctl daemon-reload
  echo "keyd installed"
}

_configure_keyd() {
  sudo mkdir -p /etc/keyd
  sudo ln -fs ~/dotfiles/keyd.conf /etc/keyd/default.conf
  if systemctl is-active --quiet keyd; then
    sudo keyd reload
  else
    sudo systemctl enable --now keyd
  fi
  echo "keyd configured"
}

KITTY_VERSION=0.51.1

# The official build instead of dnf: vertical tabs need 0.48+, the repos may
# lag behind
_install_kitty() {
  app="$HOME/.local/kitty.app"
  if "$app/bin/kitty" --version 2>/dev/null | grep -q " $KITTY_VERSION "; then
    echo "kitty already installed"
    return 0
  fi
  url=https://sw.kovidgoyal.net/kitty/installer.sh
  if ! curl -fsSL "$url" | sh /dev/stdin \
    installer="version-$KITTY_VERSION" launch=n; then
    echo "❌ Failed to install kitty, aborting" >&2
    exit 1
  fi
  mkdir -p ~/.local/bin ~/.local/share/applications
  ln -sf "$app/bin/kitty" "$app/bin/kitten" ~/.local/bin/
  # The desktop file names the binary and icon relative to PATH and the
  # icon theme, neither of which knows about kitty.app
  desktop="$HOME/.local/share/applications/kitty.desktop"
  icon="$app/share/icons/hicolor/256x256/apps/kitty.png"
  sed -e "s|Icon=kitty|Icon=$icon|g" -e "s|Exec=kitty|Exec=$app/bin/kitty|g" \
    "$app/share/applications/kitty.desktop" > "$desktop"
  # Makes desktop environments that use xdg-terminal-exec open kitty
  echo 'kitty.desktop' > ~/.config/xdg-terminals.list
  echo "kitty installed"
}

_configure_kitty() {
  sudo dnf install -y jetbrains-mono-fonts
  # Entire config dir should be symlinked
  rm -rf ~/.config/kitty
  ln -s ~/dotfiles/kitty ~/.config/kitty
  echo "kitty configured"
}

# Microsoft's repo instead of Flatpak: the sandbox hides host toolchains
# from extensions and the integrated terminal
_install_vscode() {
  if command -v code >/dev/null; then
    echo "VSCode already installed"
    return 0
  fi
  key=https://packages.microsoft.com/keys/microsoft.asc
  sudo rpm --import "$key"
  printf '%s\n' \
    '[code]' \
    'name=Visual Studio Code' \
    'baseurl=https://packages.microsoft.com/yumrepos/vscode' \
    'enabled=1' \
    'autorefresh=1' \
    'type=rpm-md' \
    'gpgcheck=1' \
    "gpgkey=$key" \
    | sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
  if ! sudo dnf install -y code; then
    echo "❌ Failed to install VSCode, aborting" >&2
    exit 1
  fi
  echo "VSCode installed"
}

_configure_vscode() {
  # VSCode bundles its own node that prints deprecation warnings to stderr
  NODE_NO_WARNINGS=1
  export NODE_NO_WARNINGS
  while IFS= read -r ext; do
    code --install-extension "$ext" </dev/null >/dev/null
  done <<'EOF'
grigoryvp.language-xi
grigoryvp.memory-theme
grigoryvp.goto-link-provider
grigoryvp.markdown-inline-fence
grigoryvp.markdown-python-repl-syntax
grigoryvp.markdown-pandoc-rawattr
vscodevim.vim
EditorConfig.EditorConfig
emmanuelbeziat.vscode-great-icons
esbenp.prettier-vscode
formulahendry.auto-close-tag
dnut.rewrap-revived
streetsidesoftware.code-spell-checker
streetsidesoftware.code-spell-checker-russian
mark-wiemer.vscode-autohotkey-plus-plus
charliermarsh.ruff
harrydowning.yaml-embedded-languages
EOF
  unset NODE_NO_WARNINGS
  dir=~/.config/Code/User
  mkdir -p "$dir"
  ln -fs ~/dotfiles/vscode_keybindings.json "$dir/keybindings.json"
  ln -fs ~/dotfiles/vscode_settings.json "$dir/settings.json"
  ln -fs ~/dotfiles/vscode_tasks.json "$dir/tasks.json"
  rm -rf "$dir/snippets"
  ln -s ~/dotfiles/vscode_snippets "$dir/snippets"
  echo "VSCode configured"
}

# dnf instead of Flatpak: keepassxc-cli lands on PATH
_install_keepassxc() {
  if command -v keepassxc >/dev/null; then
    echo "KeePassXC already installed"
    return 0
  fi
  if ! sudo dnf install -y keepassxc; then
    echo "❌ Failed to install KeePassXC, aborting" >&2
    exit 1
  fi
  echo "KeePassXC installed"
}

# KeePassXC quits gracefully on SIGTERM
_keepassxc_quit() {
  if ! pkill -x keepassxc; then
    return 0
  fi
  i=0
  while pgrep -x keepassxc >/dev/null; do
    if [ $i -ge 100 ]; then
      echo "❌ KeePassXC did not quit, aborting" >&2
      exit 1
    fi
    sleep 0.2
    i=$((i+1))
  done
}

# Copied, not symlinked: KeePassXC keeps its KeeShare private key in this
# file, which must not end up in the repository. A running KeePassXC writes
# its settings back on exit, overwriting the copy.
_configure_keepassxc() {
  _keepassxc_quit
  dir=~/.config/keepassxc
  mkdir -p "$dir"
  if ! cp ~/dotfiles/keepassxc.ini "$dir/keepassxc.ini"; then
    echo "❌ Failed to copy keepassxc.ini, aborting" >&2
    exit 1
  fi
  echo "KeePassXC configured"
}

test() {
  _install_keepassxc
  _configure_keepassxc
}

configure() {
  _check_env

  # Group settings that require sudo together

  _configure_lid
  _clone_dotfiles
  _install_keyd
  _configure_keyd
  _install_kitty
  _configure_kitty
  _install_vscode
  _configure_vscode
  _install_keepassxc
  _configure_keepassxc

  # No idle suspend on external power, otherwise a laptop with the lid
  # closed falls asleep anyway
  gsettings set org.gnome.settings-daemon.plugins.power \
    sleep-inactive-ac-type 'nothing'

  # Mute the terminal bell: GNOME's own is played by mutter for any app,
  # Ptyxis (the default terminal) plays its own
  gsettings set org.gnome.desktop.wm.preferences audible-bell false
  if gsettings list-schemas | grep -qx org.gnome.Ptyxis; then
    gsettings set org.gnome.Ptyxis audible-bell false
  fi

  echo "✅ configuration complete"
}

if [ "$1" = "--test" ]; then
  test
else
  configure
fi
