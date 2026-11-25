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

test() {
  _install_keyd
  _configure_keyd
}

configure() {
  _check_env

  # Group settings that require sudo together

  _configure_lid
  _clone_dotfiles
  _install_keyd
  _configure_keyd

  # No idle suspend on external power, otherwise a laptop with the lid
  # closed falls asleep anyway
  gsettings set org.gnome.settings-daemon.plugins.power \
    sleep-inactive-ac-type 'nothing'

  echo "✅ configuration complete"
}

if [ "$1" = "--test" ]; then
  test
else
  configure
fi
