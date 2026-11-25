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

CLAUDE_CODE_KEY_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

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
  file=$(mktemp)
  if ! curl -fsSL "$key" -o "$file"; then
    rm -f "$file"
    echo "❌ Failed to download Claude Code key, aborting" >&2
    exit 1
  fi
  # The fingerprint from the Claude Code setup docs
  fpr=$(gpg --show-keys --with-colons "$file" | grep '^fpr:')
  if [ "$fpr" != "fpr:::::::::$CLAUDE_CODE_KEY_FPR:" ]; then
    rm -f "$file"
    echo "❌ Unexpected Claude Code key, aborting" >&2
    exit 1
  fi
  sudo rpm --import "$file"
  rm -f "$file"
  printf '%s\n' \
    '[claude-code]' \
    'name=Claude Code' \
    'baseurl=https://downloads.claude.ai/claude-code/rpm/stable' \
    'enabled=1' \
    'gpgcheck=1' \
    "gpgkey=$key" \
    | sudo tee /etc/yum.repos.d/claude-code.repo >/dev/null
  # Fedora ships the Google Chrome repo disabled. Its /etc/default/google-chrome
  # also stops Chrome from adding a duplicate repo on install.
  sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub
  sudo dnf install -y fedora-workstation-repositories \
    'dnf-command(config-manager)'
  sudo dnf config-manager setopt google-chrome.enabled=1
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
  _install_vscode
  _configure_vscode
  _install_keepassxc
  _configure_keepassxc
  _install_chrome
  _install_doublecmd
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
