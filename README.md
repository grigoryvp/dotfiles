# My windows and OSX box automatic configuration

## Windows

Install PowerShell Core from [releases](https://github.com/PowerShell/PowerShell/releases) page.

```ps1
cd ~; Invoke-WebRequest -OutFile configure.ps1 -Uri https://raw.githubusercontent.com/grigoryvp/box-cfg/master/configure.ps1; & .\configure.ps1
```

Follow instructions for post-configuration.

## OSX

```ps1
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
brew cask install keepassxc spectacle karabiner-elements slimbatterymonitor yujitach-menumeters itsycal short-menu chatty vk-messenger telegram transmission visual-studio-code powershell obs nordvpn mucommander
brew install exa python node
git clone https://github.com/grigoryvp/box-cfg.git ~/.box-cfg
keepassxc-cli show ~/.box-cfg/passwords.kdbx github
# Add ssh to github
rm -rf ~/.box-cfg
git clone git@github.com:grigoryvp/box-cfg.git ~/.box-cfg
git clone git@github.com:grigoryvp/xi.git ~/.xi
# Menu bar, from right to left:
# spectacle, wifi, bt, clock, itsycal, short-menu, slimbatterymonitor, menumeters
curl -Ls https://raw.githubusercontent.com/daipeihust/im-select/master/install_mac.sh | sh
ln ~/.box-cfg/shell/.bashrc ~/.bashrc
ln ~/.box-cfg/shell/.screenrc ~/.screenrc
ln ~/.box-cfg/vscode_keybindings.json ~/Library/Application\ Support/Code/User/keybindings.json
ln ~/.box-cfg/vscode_settings.json ~/Library/Application\ Support/Code/User/settings.json
cp ~/.box-cfg/karabiner.json ~/.config/karabiner/karabiner.json
# Install tampermonkey for safari.
```

## Todo

* Ignore subsequent "down" events on buttons that emulate mouse buttons.
* Implement "go-to-background" Ctrl-D via PS keyboard hook.
* Install "7+ Taskbar Tweaker".

## License

The following licensing applies to My windows box automatic configuration:
Attribution-NonCommercial-NoDerivatives 4.0 International
(CC BY-NC-ND 4.0). For more information go to
[https://creativecommons.org/licenses/by-nc-nd/4.0/](https://creativecommons.org/licenses/by-nc-nd/4.0/)
