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

_configure_ssh() {
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  if ! [ -e ~/.ssh/id_rsa.pub ]; then
    ssh-keygen -t rsa -f ~/.ssh/id_rsa -N ""
  fi
  # Allows git clone without fingerprint confirmation
  if ! ssh-keygen -F github.com >/dev/null; then
    ssh-keyscan github.com 2>/dev/null >> ~/.ssh/known_hosts
  fi
  echo "SSH configured"
}

# Remote is switched instead of recloning: a fresh clone would lose local
# changes in ~/dotfiles
_switch_dotfiles_to_ssh() {
  if [ -e ~/.ssh/.uploaded_to_github ]; then
    echo "Dotfiles already switched to SSH"
    return 0
  fi
  db=~/dotfiles/auth/passwords.kdbx
  until keepassxc-cli show --show-protected \
    --attributes username --attributes password "$db" github; do :; done
  echo "Sign in to GitHub via browser and press enter for TOTP code"
  read -r _
  until keepassxc-cli show --totp "$db" github; do :; done
  cat ~/.ssh/id_rsa.pub
  echo "Add SSH key to GitHub and press enter"
  read -r _
  git -C ~/dotfiles remote set-url origin \
    git@github.com:grigoryvp/dotfiles.git
  until git -C ~/dotfiles ls-remote origin >/dev/null; do
    echo "GitHub rejected the SSH key, fix it and press enter"
    read -r _
  done
  touch ~/.ssh/.uploaded_to_github
  echo "Dotfiles switched to SSH"
}

_clone_knowledge_base() {
  if [ -e ~/.xi ]; then
    echo "Knowledge base already cloned"
  elif [ -e ~/.ssh/.uploaded_to_github ]; then
    git clone git@github.com:grigoryvp/xi.git ~/.xi
  else
    echo "Not cloning knowledge base since ssh keys are not uploaded"
  fi
}

# Skill Manager sources (specs/sm.spec.md)
_clone_skills() {
  if ! [ -e ~/.ssh/.uploaded_to_github ]; then
    echo "Not cloning skills since ssh keys are not uploaded"
    return 0
  fi
  mkdir -p ~/skills
  for pair in public-skills:skills private-skills:private-skills; do
    dir="$HOME/skills/${pair%%:*}"
    if [ -e "$dir" ]; then
      echo "$dir already cloned"
    else
      git clone "git@github.com:grigoryvp/${pair#*:}.git" "$dir"
    fi
  done
}

# Use the dotfiles as source-of-truth. Unlike macOS, where the login lives in
# Keychain, ~/.claude holds the login and memory: existing state is moved,
# not deleted. The repo's settings.json wins.
_configure_claude() {
  if [ -L ~/.claude ]; then
    echo "Claude already configured"
    return 0
  fi
  if [ -d ~/.claude ]; then
    for src in ~/.claude/* ~/.claude/.[!.]*; do
      [ -e "$src" ] || continue
      dst="$HOME/dotfiles/.claude/${src##*/}"
      if [ -e "$dst" ]; then
        echo "⚠️ Not moving $src: $dst exists" >&2
      elif ! mv "$src" "$dst"; then
        echo "❌ Failed to move $src, aborting" >&2
        exit 1
      fi
    done
    rm -rf ~/.claude
  fi
  ln -s ~/dotfiles/.claude ~/.claude
  echo "Claude configured"
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
  # Copied, not symlinked: keyd runs command() actions from the config as
  # root, so a user-writable config would hand root to any user process
  sudo rm -f /etc/keyd/default.conf
  sudo install -m 644 ~/dotfiles/keyd.conf /etc/keyd/default.conf
  # keyd runs commands as root, while the session bus accepts only the user
  # that owns it. Root-owned for the same reason as the config.
  uid=$(id -u)
  sudo tee /usr/local/bin/lang-keys >/dev/null <<EOF
#!/bin/sh
exec setpriv --reuid=$uid --regid=$(id -g) --clear-groups \\
  env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \\
  gdbus call --session --dest org.gnome.Shell \\
  --object-path /org/gnome/Shell/Extensions/LangKeys \\
  --method org.gnome.Shell.Extensions.LangKeys.Activate "\$1" >/dev/null
EOF
  sudo chmod 755 /usr/local/bin/lang-keys
  if systemctl is-active --quiet keyd; then
    sudo keyd reload
  else
    sudo systemctl enable --now keyd
  fi
  echo "keyd configured"
}

# Same set as on macOS and Windows: English, Russian, Japanese, picked by
# m1-shift-f/d/s via keyd, /usr/local/bin/lang-keys and the lang-keys
# extension
_configure_input_sources() {
  sudo dnf install -y ibus-mozc
  # Mozc defaults with active_on_launch flipped: Japanese starts in hiragana
  # instead of direct input, like Kotoeri on macOS
  mkdir -p ~/.config/mozc
  cat > ~/.config/mozc/ibus_config.textproto <<'EOF'
engines {
  name : "mozc-jp"
  longname : "Mozc"
  layout : "default"
  layout_variant : ""
  layout_option : ""
  rank : 80
}
active_on_launch: True
EOF
  gsettings set org.gnome.desktop.input-sources sources \
    "[('xkb', 'us'), ('xkb', 'ru'), ('ibus', 'mozc-jp')]"

  ext=lang-keys@grigoryvp
  dir=~/.local/share/gnome-shell/extensions
  mkdir -p "$dir"
  rm -rf "${dir:?}/$ext"
  ln -s ~/dotfiles/gnome/$ext "$dir/$ext"
  # GNOME Shell discovers new extensions only on login, until then
  # "gnome-extensions enable" refuses an unknown one
  cur=$(gsettings get org.gnome.shell enabled-extensions)
  case "$cur" in
    *"'$ext'"*) ;;
    "@as []") gsettings set org.gnome.shell enabled-extensions "['$ext']" ;;
    *) gsettings set org.gnome.shell enabled-extensions "${cur%]}, '$ext']" ;;
  esac
  echo "Input sources configured, log out and back in to apply"
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

# Fingerprints from the vendors' setup docs
CLAUDE_CODE_KEY_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
DOCKER_KEY_FPR=060A61C51B558A7F742B77AAC52FEB6B621E9F35

_import_key_with_fpr() {
  url=$1 fpr=$2 name=$3
  file=$(mktemp)
  if ! curl -fsSL "$url" -o "$file"; then
    rm -f "$file"
    echo "❌ Failed to download $name key, aborting" >&2
    exit 1
  fi
  if [ "$(gpg --show-keys --with-colons "$file" | grep '^fpr:')" \
    != "fpr:::::::::$fpr:" ]; then
    rm -f "$file"
    echo "❌ Unexpected $name key, aborting" >&2
    exit 1
  fi
  sudo rpm --import "$file"
  rm -f "$file"
}

# Keys are imported up front: "dnf install -y" would otherwise accept any
# key the repo serves
_configure_dnf_repos() {
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

  key=https://downloads.claude.ai/keys/claude-code.asc
  _import_key_with_fpr "$key" "$CLAUDE_CODE_KEY_FPR" "Claude Code"
  printf '%s\n' \
    '[claude-code]' \
    'name=Claude Code' \
    'baseurl=https://downloads.claude.ai/claude-code/rpm/stable' \
    'enabled=1' \
    'gpgcheck=1' \
    "gpgkey=$key" \
    | sudo tee /etc/yum.repos.d/claude-code.repo >/dev/null

  # Docker's own repo instead of Fedora's moby-engine: the buildx and
  # compose plugins come from there
  key=https://download.docker.com/linux/fedora/gpg
  _import_key_with_fpr "$key" "$DOCKER_KEY_FPR" "Docker"
  printf '%s\n' \
    '[docker-ce-stable]' \
    'name=Docker CE Stable' \
    "baseurl=${key%/gpg}/\$releasever/\$basearch/stable" \
    'enabled=1' \
    'gpgcheck=1' \
    "gpgkey=$key" \
    | sudo tee /etc/yum.repos.d/docker-ce.repo >/dev/null
  # Fedora ships the Google Chrome repo disabled. Its /etc/default/google-chrome
  # also stops Chrome from adding a duplicate repo on install.
  sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub
  sudo dnf install -y fedora-workstation-repositories \
    'dnf-command(config-manager)'
  sudo dnf config-manager setopt google-chrome.enabled=1

  key=https://pkgs.tailscale.com/stable/fedora/repo.gpg
  sudo rpm --import "$key"
  printf '%s\n' \
    '[tailscale-stable]' \
    'name=Tailscale stable' \
    'baseurl=https://pkgs.tailscale.com/stable/fedora/$basearch' \
    'enabled=1' \
    'type=rpm' \
    'repo_gpgcheck=1' \
    'gpgcheck=1' \
    "gpgkey=$key" \
    | sudo tee /etc/yum.repos.d/tailscale.repo >/dev/null

  sudo dnf install -y 'dnf-command(copr)'
  sudo dnf copr enable -y jdxcode/mise
  echo "dnf repos configured"
}

# Microsoft's repo instead of Flatpak: the sandbox hides host toolchains
# from extensions and the integrated terminal
_install_vscode() {
  if command -v code >/dev/null; then
    echo "VSCode already installed"
    return 0
  fi
  if ! sudo dnf install -y code; then
    echo "❌ Failed to install VSCode, aborting" >&2
    exit 1
  fi
  echo "VSCode installed"
}

_install_chrome() {
  if rpm -q google-chrome-stable >/dev/null; then
    echo "Chrome already installed"
    return 0
  fi
  if ! sudo dnf install -y google-chrome-stable; then
    echo "❌ Failed to install Chrome, aborting" >&2
    exit 1
  fi
  echo "Chrome installed"
}

# Qt6 build: the GTK one is still GTK2
# Fedora packages the Go yq by mikefarah, not the Python jq wrapper
_install_yq() {
  if rpm -q yq >/dev/null; then
    echo "yq already installed"
    return 0
  fi
  if ! sudo dnf install -y yq; then
    echo "❌ Failed to install yq, aborting" >&2
    exit 1
  fi
  echo "yq installed"
}

_install_flameshot() {
  if rpm -q flameshot >/dev/null; then
    echo "Flameshot already installed"
    return 0
  fi
  if ! sudo dnf install -y flameshot wl-clipboard; then
    echo "❌ Failed to install Flameshot, aborting" >&2
    exit 1
  fi
  echo "Flameshot installed"
}

# There is no cli option for the save path, so the key is edited into the ini
# in place, keeping whatever was set through the tray menu. QSettings sorts
# the keys inside a section, so a new one is appended to "[General]".
_flameshot_ini_set() {
  ini="$HOME/.config/flameshot/flameshot.ini"
  awk -v key="$1" -v value="$2" '
    $0 ~ "^" key "=" { print key "=" value; done = 1; next }
    /^\[/ && general && !done { print key "=" value; done = 1 }
    /^\[General\]/ { general = 1 }
    { print }
    END { if (!done) print key "=" value }
  ' "$ini" > "$ini.new" && mv "$ini.new" "$ini"
}

# keyd turns m3-slash into this combination, picked to clash with nothing
FLAMESHOT_KEYS='<Primary><Alt><Super>slash'

_configure_flameshot() {
  # Hiding the tray icon leaves the daemon running: capture is started by
  # the "flameshot gui" command
  flameshot config --autostart true --trayicon false >/dev/null 2>&1
  # Flameshot rejects a save path that does not exist and falls back to its
  # default, so the directory is created first
  mkdir -p "$HOME/Screenshots"
  _flameshot_ini_set savePath "$HOME/Screenshots"
  # Done by flameshot-gui.sh instead, Flameshot's own copy is lost on Wayland
  _flameshot_ini_set copyPathAfterSave false
  _flameshot_ini_set showDesktopNotification false
  if ! flameshot config --check 2>&1 | grep -q "No errors detected"; then
    echo "❌ Flameshot rejected its configuration, aborting" >&2
    exit 1
  fi

  # Launched by GNOME rather than by keyd: keyd runs commands as root,
  # outside the session
  keys=org.gnome.settings-daemon.plugins.media-keys
  path=/org/gnome/settings-daemon/plugins/media-keys
  path="$path/custom-keybindings/flameshot/"
  schema="$keys.custom-keybinding:$path"
  gsettings set "$schema" name Flameshot
  gsettings set "$schema" command "$HOME/dotfiles/flameshot-gui.sh"
  gsettings set "$schema" binding "$FLAMESHOT_KEYS"
  cur=$(gsettings get $keys custom-keybindings)
  case "$cur" in
    *"'$path'"*) ;;
    "@as []") gsettings set $keys custom-keybindings "['$path']" ;;
    *) gsettings set $keys custom-keybindings "${cur%]}, '$path']" ;;
  esac
  echo "Flameshot configured"
}

_install_doublecmd() {
  if rpm -q doublecmd-qt6 >/dev/null; then
    echo "Double Commander already installed"
    return 0
  fi
  if ! sudo dnf install -y doublecmd-qt6; then
    echo "❌ Failed to install Double Commander, aborting" >&2
    exit 1
  fi
  echo "Double Commander installed"
}

_install_tailscale() {
  if ! rpm -q tailscale >/dev/null; then
    if ! sudo dnf install -y tailscale; then
      echo "❌ Failed to install Tailscale, aborting" >&2
      exit 1
    fi
  fi
  sudo systemctl enable --now tailscaled
  if ! tailscale status >/dev/null 2>&1; then
    # Prints a login URL and waits for the login
    if ! sudo tailscale up --operator="$USER"; then
      echo "❌ Failed to log in to Tailscale, aborting" >&2
      exit 1
    fi
  fi
  echo "Tailscale installed"
}

# Nothing is reachable from outside except via Tailscale. The default zone
# is what NetworkManager gives every new network, e.g. a cafe Wi-Fi.
_configure_firewall() {
  # Docker and k3s ports bypass the zones: they are guarded per interface
  # by our own nftables table, loaded before the network is up
  sudo install -m 644 ~/dotfiles/ingress-guard.nft \
    /etc/nftables/ingress-guard.nft
  sudo tee /etc/systemd/system/ingress-guard.service >/dev/null <<'EOF'
[Unit]
Description=Guard containers and pods from external interfaces
DefaultDependencies=no
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/nftables/ingress-guard.nft
ExecStop=/usr/sbin/nft delete table inet ingress_guard

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable ingress-guard
  if ! sudo systemctl restart ingress-guard; then
    echo "❌ Failed to load ingress-guard.nft, aborting" >&2
    exit 1
  fi

  # Strict mode blocks DNAT'd traffic from the tailnet as well. Set by
  # earlier versions of this script.
  conf=/etc/firewalld/firewalld.conf
  if sudo grep -q '^StrictForwardPorts=yes' "$conf"; then
    sudo sed -i 's/^StrictForwardPorts=.*/StrictForwardPorts=no/' "$conf"
    sudo systemctl restart firewalld
  fi

  # Connections pinned to another zone would skip the default one
  nmcli -t -f UUID,TYPE con show | while IFS=: read -r uuid type; do
    case "$type" in
      802-11-wireless|802-3-ethernet)
        sudo nmcli con modify "$uuid" connection.zone ""
        ;;
    esac
  done

  fc="sudo firewall-cmd --permanent"
  sudo firewall-cmd --set-default-zone=drop
  # DHCPv6 replies are not tracked as related to the request, unlike
  # DHCPv4, whose client uses a raw socket that bypasses the firewall
  $fc --zone=drop --add-service=dhcpv6-client
  $fc --zone=trusted --add-interface=tailscale0
  # k3s pods reach the host via these, not via the default zone. Interfaces,
  # not the pod CIDRs: a source address is easy to spoof from the Wi-Fi.
  $fc --zone=trusted --add-interface=cni0
  $fc --zone=trusted --add-interface=flannel.1
  # Superseded by ingress-guard.nft
  if $fc --get-policies | grep -qw drop-forward; then
    $fc --delete-policy=drop-forward
  fi
  sudo firewall-cmd --reload
  echo "Firewall configured"
}

# The user is not added to the "docker" group: it is root without a
# password, so docker is run via sudo
_install_docker() {
  if ! rpm -q docker-ce >/dev/null; then
    if ! sudo dnf install -y docker-ce docker-ce-cli containerd.io \
      docker-buildx-plugin docker-compose-plugin; then
      echo "❌ Failed to install Docker, aborting" >&2
      exit 1
    fi
  fi
  sudo systemctl enable --now docker
  echo "Docker installed"
}

K3S_VERSION=v1.37.2+k3s1

# The node lives on the tailnet: the Wi-Fi address changes with every
# network, and the API and NodePorts are reached via Tailscale anyway
_install_k3s() {
  if k3s --version 2>/dev/null | grep -qF "$K3S_VERSION"; then
    echo "k3s already installed"
    return 0
  fi
  ip=$(tailscale ip -4)
  if [ -z "$ip" ]; then
    echo "❌ No Tailscale IP for the k3s node, aborting" >&2
    exit 1
  fi
  sudo mkdir -p /etc/rancher/k3s /etc/systemd/system/k3s.service.d
  printf 'node-ip: %s\nflannel-iface: tailscale0\n' "$ip" \
    | sudo tee /etc/rancher/k3s/config.yaml >/dev/null
  printf '[Unit]\nAfter=tailscaled.service\nWants=tailscaled.service\n' \
    | sudo tee /etc/systemd/system/k3s.service.d/tailscale.conf >/dev/null
  # The installer adds the Rancher repo for the SELinux policy and installs
  # from it with "dnf install -y", which would accept any key
  sudo rpm --import https://rpm.rancher.io/public.key
  # Pinned installer: it runs as root
  url="https://raw.githubusercontent.com/k3s-io/k3s/$K3S_VERSION/install.sh"
  file=$(mktemp)
  if ! curl -fsSL "$url" -o "$file" \
    || ! INSTALL_K3S_VERSION="$K3S_VERSION" sh "$file"; then
    rm -f "$file"
    echo "❌ Failed to install k3s, aborting" >&2
    exit 1
  fi
  rm -f "$file"
  echo "k3s installed"
}

_install_claude_code() {
  if rpm -q claude-code >/dev/null; then
    echo "Claude Code already installed"
    return 0
  fi
  if ! sudo dnf install -y claude-code; then
    echo "❌ Failed to install Claude Code, aborting" >&2
    exit 1
  fi
  echo "Claude Code installed"
}

# The dnf part of the languages setup, kept apart from the slow mise part to
# group sudo calls
_install_mise() {
  set --
  while IFS= read -r pkg; do
    set -- "$@" "$pkg"
  done <<'EOF'
mise
uv
php
swift-lang
gcc
make
patch
bzip2
tar
perl-FindBin
openssl-devel
libyaml-devel
libffi-devel
readline-devel
zlib-devel
gdbm-devel
ncurses-devel
EOF
  # Swift and PHP come from dnf, as PHP comes from brew on macOS: swift.org
  # has no builds for current Fedora. The rest is for mise to build Ruby and
  # Lua from source.
  if ! sudo dnf install -y "$@"; then
    echo "❌ Failed to install mise and its dependencies, aborting" >&2
    exit 1
  fi
  echo "mise installed"
}

_install_languages() {
  mise use -g python@3.14.5
  mise use -g node@24.16.0
  mise use -g ruby@4.0.5
  mise use -g lua@5.5.1
  mise use -g go@1.27.4
  # For agents
  uv tool install ruff
  echo "Languages installed"
}

_configure_vscode() {
  # Bundled vsce-sign verifies extension signatures with libssl.so.3 only,
  # which Fedora 45 moved out of the default install along with OpenSSL 3
  sudo dnf install -y 'libssl.so.3()(64bit)'
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

# The dash in Activities, in the order shown. GNOME Shell shows a missing app
# as nothing, so such apps are left out with a warning.
_configure_favorite_apps() {
  apps=
  for app in kitty com.microsoft.VSCode google-chrome doublecmd-qt6 \
    org.keepassxc.KeePassXC; do
    found=
    for dir in ~/.local/share/applications /usr/share/applications; do
      [ -e "$dir/$app.desktop" ] && found=1
    done
    if [ -n "$found" ]; then
      apps="$apps${apps:+, }'$app.desktop'"
    else
      echo "⚠️ Not pinning $app: it is not installed" >&2
    fi
  done
  gsettings set org.gnome.shell favorite-apps "[$apps]"
  echo "Favorite apps configured"
}

# Fedora's own ~/.bashrc is the only place that sources /etc/bashrc, so
# the replacement keeps doing it
_configure_shell() {
  printf '%s\n' \
    '#!/bin/sh' \
    'if [ -f /etc/bashrc ]; then . /etc/bashrc; fi' \
    '. ~/dotfiles/shell-cfg.sh' \
    > ~/.bashrc
  printf '#!/bin/sh\n. ~/dotfiles/shell-cfg.sh\n' > ~/.zshrc
  printf '#!/bin/sh\n. ~/.bashrc\n' > ~/.bash_profile
  # shell-cfg.sh relies on zsh, as on macOS
  sudo dnf install -y zsh zsh-autosuggestions zsh-syntax-highlighting
  zsh=$(command -v zsh)
  if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh" ]; then
    # usermod instead of chsh: chsh is not installed by default
    sudo usermod -s "$zsh" "$USER"
    echo "Log out and back in for zsh to become the login shell"
  fi
  echo "Shell configured"
}

_configure_git() {
  # git-cfg.toml pipes git output through it
  sudo dnf install -y diff-so-fancy
  ln -fs ~/dotfiles/.gitattributes ~/.gitattributes
  # Don't break existing git config, if any
  if ! [ -e ~/.gitconfig ]; then
    printf '[include]\npath = ~/dotfiles/git-cfg.toml\n' > ~/.gitconfig
  fi
  echo "git configured"
}

test() {
  _configure_dnf_repos
  _install_mise
  _install_languages
}

configure() {
  _check_env

  # Group settings that require sudo together

  _configure_lid
  _clone_dotfiles
  _install_keyd
  _configure_keyd
  _configure_input_sources
  _install_kitty
  _configure_kitty
  _configure_dnf_repos
  _install_tailscale
  _configure_firewall
  _install_docker
  _install_k3s
  _install_vscode
  _configure_vscode
  _install_keepassxc
  _configure_keepassxc
  _install_chrome
  _install_doublecmd
  _install_flameshot
  _configure_flameshot
  _install_yq
  _install_claude_code
  _configure_claude
  _install_mise
  _configure_git
  _configure_shell
  _configure_ssh
  _switch_dotfiles_to_ssh
  _clone_knowledge_base
  _clone_skills
  _install_languages

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

  _configure_favorite_apps

  echo "✅ configuration complete"
}

if [ "$1" = "--test" ]; then
  test
else
  configure
fi
