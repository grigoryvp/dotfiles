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
brew cask install keepassxc
brew install python node
git clone https://github.com/grigoryvp/box-cfg.git ~/.box-cfg
keepassxc-cli show ~/Documents/PowerShell/passwords.kdbx github
# Add ssh to github
rm -rf ~/.box-cfg
git clone git@github.com:grigoryvp/box-cfg.git ~/.box-cfg
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
