class App {

  #region Instance properties
  $_isTest = $false;
  $_isFull = $false;
  $_isPublic = $false;
  $_POST_INSTALL_MSG = "";
  $_pass = $null;
  $_cfgDir = $null;
  $_psDir = $null;
  $_github = @{
    user = "foo";
    pass = "bar";
    token = "baz";
  };
  #endregion


  App($argList) {
    $this._isTest = ($argList.Contains("--test"));
    $this._isFull = ($argList.Contains("--full"));
    # Do not touch private info like passwords, personal kb etc.
    $this._isPublic = ($argList.Contains("--public"));
    # Version-controlled dir with scripts, powershell config, passwords etc.
    $this._cfgDir = "~/.box-cfg";
    $this._psDir = "~/Documents/PowerShell";
    $this._POST_INSTALL_MSG = @"
      Config complete. Manual things to do
      - Disable adaptive contrast for the built-in Intel GPU, if any
      - "Change Proxy Settings", Turn off "Automatically Detect Settings"
      - Add C-S-4-5-6 as en-ru-js hotkeys and copy settings
      - Disable autostart in Task Manager
      - Disable snap assist
      - Disable touchbar click
      - Add perfgraph toolbar
      - Login Edge
      - Pin files, vscode, edge, telegram, keepass, cmd
      - Make --full configuration
      - Reboot
"@;
  }


  configure() {

    # Required by Posh-Git, sudo etc.
    if ((Get-ExecutionPolicy -Scope CurrentUser) -ne "Unrestricted") {
      # scoop shims like sudo are executed via powershell.exe and it seems
      # that pwsh.exe and powershell.exe have separated execution policy
      # config
      & powershell.exe `
        -Command Set-ExecutionPolicy Unrestricted `
        -Scope CurrentUser;
    }

    if (!$this._isTest) {
      if (-not (Test-Path -Path "$this._cfgDir")) {
        New-Item -Path "$this._cfgDir" -ItemType Directory | Out-Null;
      }
    }

    # Auto-created by PowerShell 5.x until 6.x+ is a system default.
    # Create and set hidden attribute to exclude from 'ls'.
    if (!$this._isTest) {
      $oldPsDir = "$($env:USERPROFILE)/Documents/WindowsPowerShell";
      if (-not (Test-Path -Path $oldPsDir)) {
        $ret = & New-Item -Path $oldPsDir -ItemType Directory;
        $ret.Attributes = 'Hidden';
      }
    }

    # PowerShell config is loaded from this dir.
    # Create and set hidden attribute to exclude from 'ls'.
    if (!$this._isTest) {
      if (-not (Test-Path -Path $this._psDir)) {
        $ret = & New-Item -Path $this._psDir -ItemType Directory;
        $ret.Attributes = 'Hidden';
      }
    }

    # Used by '_mapCapsToF24'.
    $this._installApp("sudo");
    $this._installPowershellModule("posh-git");
    $this._installPowershellModule("WindowsCompatibility");
    $this._generateSshKey();
    $this._setPowerOptions();
    $this._setDebounceOptions();
    $this._setTouchpadOptions();
    $this._setInputMethodOptions();
    # Installed manually before running this script so scoop can manage pwsh
    # $this._installScoop();
    $this._installGit();
    $this._addScoopBuckets();
    # Clone without keys via HTTPS
    $this._getFilesFromGit();
    # After additional files are received
    $this._mapCapsToF24();
    # VCRUNTIME140_1.dll required for windows-terminal
    $this._installApp("extras/vcredist2019");
    $this._installApp("autohotkey");
    $this._installApp("keepassxc");
    $this._installApp("vscode");
    $this._configureVscode();
    $this._installApp("tray-monitor");
    $this._installApp("battery-info-view");
    $this._registerAutohotkeyStartup();
    $this._configureBatteryInfoView();
    $this._registerBatteryInfoViewStartup();
    $this._registerBatteryIconStartup();
    $this._registerCpuIconStartup();
    $this._registerRamIconStartup();

    # Symlink PowerShel config file into PowerShell config dir.
    if (!$this._isTest) {
      if (Test-Path -Path "$($this._psDir)/profile.ps1") {
        Remove-Item "$($this._psDir)/profile.ps1";
      }
      New-Item `
        -ItemType HardLink `
        -Path "$($this._psDir)" `
        -Name "profile.ps1" `
        -Value "$($this._cfgDir)/profile.ps1";
    }

    # Symlink git config.
    if (!$this._isTest) {
      if (Test-Path -Path "$($env:HOME)/.gitconfig") {
        Remove-Item "$($env:HOME)/.gitconfig";
      }
      New-Item `
        -ItemType HardLink `
        -Path "$($env:HOME)" `
        -Name ".gitconfig" `
        -Value "$($this._cfgDir)/shell/.gitconfig";
    }
    
    # TODO: symlink '~/AppData/Local/Microsoft/Windows Terminal/profiles.json'

    # Interactive.
    if (-not (Test-Path -Path .ssh/.uploaded_to_github)) {
      if (-not $this._isPublic) {
        $this._askForGithubCredentials();
      }
    }

    # Interactive.
    $this._installFonts();

    if (-not $this._isPublic) {
      $this._uploadSshKey();
    }

    if (-not $this._isPublic) {
      # Re-clone with SSH keys
      $this._getFilesFromGit();
    }

    $this._getXi();

    if (-not (Test-Path -Path ".editorconfig")) {
        $src = "$($this._cfgDir)/.editorconfig";
        Copy-Item -Path $src -Destination . -Force | Out-Null;
    }

    # Optional installs
    if ($this._isFull) {
      $this._installApp("grigoryvp/telegram");
      $this._installApp("foxit-reader");
      $this._installApp("doublecmd");
      # 'psexec' (required to start non-elevated apps), 'procexp' etc
      $this._installApp("sysinternals");
      # Need to restart terminal in order to apply env variables.
      $this._installApp("nodejs");
      $this._installApp("miniconda3");
      $this._installApp("obs-studio");
      $this._installApp("rufus");
      # TODO: configure to save position on exit
      $this._installApp("mpv");
      # TODO: unattended install for current user
      $this._installApp("perfgraph");
    }

    # Interactive.
    $this._startAutohotkey();

    if ($this._isTest) {
      Write-Host "Test complete";
    }
    else {
      Write-Host $this._POST_INSTALL_MSG;
    }
  }


  [Boolean] _hasCli($name) {
    if ($this._isTest) { return $false; }
    Get-Command $name -ErrorAction SilentlyContinue;
    return $?;
  }


  [Boolean] _isAppStatusInstalled($appName) {
    if ($this._isTest) { return $false; }
    $res = & scoop info $appName;
    if ($LASTEXITCODE -ne 0) { return $false; }
    return (-not ($res | Out-String).Contains("Installed: No"));
  }

  [Boolean] _hasApp($appName) {
    if ($this._isTest) { return $false; }
    if (-not $this._isAppStatusInstalled($appName)) { return $false; }
    $res = @(& scoop info $appName);
    $installMarkIdx = $res.IndexOf("Installed:");
    if ($installMarkIdx -eq -1) { return $false; }
    $installDir = $res[$installMarkIdx + 1];
    if (-not $installDir) { return $false; }
    $installDir = $installDir.Trim();
    # if install fails, scoop will treat app as installed, but install dir
    # is not created.
    if (-not (Test-Path -Path $installDir)) { return $false; }
    $content = Get-ChildItem $installDir;
    return ($content.Length -gt 0);
  }


  _installApp($appName) {
    if ($this._isTest) { return; }
    if ($this._hasApp($appName)) { return; }
    if ($this._isAppStatusInstalled($appName)) {
      # if install fails, scoop will treat app as installed.
      $this._prompt("'$appName' corrupted, press any key to reinstall");
      scoop uninstall $appName;
    }
    scoop install $appName;
    if ($LASTEXITCODE -ne 0) { throw "Failed" }
  }


  _installPowershellModule($moduleName) {
    if ($this._isTest) { return; }
    if (Get-InstalledModule | Where-Object Name -eq $moduleName) { return; }
    Install-Module $moduleName -Scope CurrentUser;
    if (-not $?) { throw "Failed" }
  }


  _copyToAppDir($fileName, $appName) {
    if ($this._isTest) { return; }
    $srcPath = "$($this._cfgDir)/$fileName";
    $dstPath = "$($env:USERPROFILE)/scoop/apps/$appName/current/";
    Copy-Item -Path $srcPath -Destination $dstPath -Force;
  }


  _getFilesFromGit() {
    if ($this._isTest) { return; }
    $gitCfgFile = "$($this._cfgDir)/.git/config";
    if (Test-Path -Path $gitCfgFile) {
      $gitCfg = Get-Content $gitCfgFile | Out-String;
      # Already cloned with SSH?
      if ($gitCfg.Contains("git@github.com")) { return; }
    }

    # Have keys to clone with SSH?
    if (Test-Path -Path ".ssh/.uploaded_to_github") {
      $uri = "git@github.com:grigoryvp/box-cfg.git";
    }
    else {
      # Already cloned without keys?
      if (Test-Path -Path $gitCfgFile) { return; }
      # Clone with HTTPS
      $uri = "https://github.com/grigoryvp/box-cfg.git";
    }

    & git clone $uri "$($this._cfgDir).tmp";
    # Replace HTTP git config with SSH one, if any.
    Remove-Item `
      -Recurse -Force -ErrorAction SilentlyContinue `
      "$($this._cfgDir)/*";
    Move-Item -Force "$($this._cfgDir).tmp/*" "$($this._cfgDir)";
    Remove-Item "$($this._cfgDir).tmp";
  }


  _generateSshKey() {
    if ($this._isTest) { return; }
    if (Test-Path -Path .ssh/id_rsa) { return; }
    if (-not (Test-Path -Path .ssh)) {
      New-Item -Path .ssh -ItemType Directory | Out-Null;
    }
    Start-Process ssh-keygen -ArgumentList '-N "" -f .ssh/id_rsa' -Wait;
  }


  _setPowerOptions() {
    if ($this._isTest) { return; }
    powercfg -change -monitor-timeout-ac 120;
    powercfg -change -monitor-timeout-dc 120;
    powercfg -change -disk-timeout-ac 0;
    powercfg -change -disk-timeout-dc 0;
    powercfg -change -standby-timeout-ac 0;
    powercfg -change -standby-timeout-dc 0;
    powercfg -change -hibernate-timeout-ac 0;
    powercfg -change -hibernate-timeout-dc 0;
    #  Set 'plugged in' cooling policy to 'active'
    powercfg -setacvalueindex scheme_current 54533251-82be-4824-96c1-47b60b740d00 94d3a615-a899-4ac5-ae2b-e4d8f634367f 1
    #  Set 'on battery' cooling policy to 'active'
    #! If set to 'passive' will downclock cpu to minimum, unusable
    powercfg -setdcvalueindex scheme_current 54533251-82be-4824-96c1-47b60b740d00 94d3a615-a899-4ac5-ae2b-e4d8f634367f 1
  }


  _setDebounceOptions() {
    if ($this._isTest) { return; }

    $args = @{
      Path = "HKCU:\Control Panel\Accessibility\Keyboard Response"
      PropertyType = "String"
      Force = $true
    }

    # Ms before key is repeated
    $args.Name = 'AutoRepeatDelay';
    $args.Value = '400';
    New-ItemProperty @args;

    # Less is faster
    $args.Name = 'AutoRepeatRate';
    $args.Value = '30';
    New-ItemProperty @args;

    #  Milliseconds to supres bounce (with 30ms it RARELY bounces).
    #! On some laptops like Dell 5490 setting this value will result in fast
    #  double presses not handled.
    $args.Name = 'BounceTime';
    $args.Value = '35';
    New-ItemProperty @args;

    # Milliseconds to wait before accepting a keystroke
    $args.Name = 'DelayBeforeAcceptance';
    $args.Value = '0';
    New-ItemProperty @args;

    # Bit Flags:
    # 00000001 On
    # 00000010 Available
    # 00000100 Use shortcut
    # 00001000 Confirm activation
    # 00010000 Activation sound
    # 00100000 Show status
    # 01000000 Key click
    $args.Name = 'Flags';
    $args.Value = '1';
    New-ItemProperty @args;
  }


  _mapCapsToF24() {
    if ($this._isTest) { return; }
    sudo pwsh "$($this._cfgDir)/map_caps_to_f24.ps1";
  }


  _setTouchpadOptions() {
    if ($this._isTest) { return; }
    $root = "HKCU:\Software\Microsoft\Windows\CurrentVersion";
    $uri = "$root\PrecisionTouchPad";
    $propName = "AAPThreshold";
    $prop = Get-ItemProperty $uri -Name $propName;
    if ($prop) {
      $val = $prop.AAPThreshold;
      if ($val -eq 0) { return; }
    }
    # Requires reboot.
    Set-ItemProperty $uri -Name $propName -Type Dword -Value 0;
  }


  _setInputMethodOptions() {
    if ($this._isTest) { return; }
    $current = & powershell.exe -Command Get-WinUserLanguageList | Out-String;
    if (-not $current.Contains("LanguageTag     : ru")) {
      $cmd = '' +
        '$list = Get-WinUserLanguageList;' +
        '$list.Add("ru");' +
        'Set-WinUserLanguageList -Force $list;';
      & powershell.exe -Command $cmd;
    }
    if (-not $current.Contains("LanguageTag     : ja")) {
      $cmd = '' +
        '$list = Get-WinUserLanguageList;' +
        '$list.Add("ja");' +
        'Set-WinUserLanguageList -Force $list;';
      & powershell.exe -Command $cmd;
    }
  }


  _askForGithubCredentials() {
    $pass = Read-Host -AsSecureString -Prompt "Enter password"

    $ptr = [Security.SecureStringMarshal]::SecureStringToCoTaskMemAnsi($pass);
    $str = [Runtime.InteropServices.Marshal]::PtrToStringAnsi($ptr);
    $this._pass = $str;

    $db = "$($this._cfgDir)/passwords.kdbx";
    # -s to show protected attribute (password) as clear text.
    $ret = & Write-Output $this._pass | keepassxc-cli show -s $db github;
    # Insert password to unlock ...:
    # Title: ...
    # UserName: ...
    # Password: ...
    # URL: ...
    # Notes: ...
    $this._github.user = $ret[2].Replace("UserName: ", "");
    $this._github.pass = $ret[3].Replace("Password: ", "");
    $this._github.token = $ret[5].Replace("Notes: ", "");
  }


  _installScoop() {
    if ($this._isTest) { return; }
    if ($this._hasCli("scoop")) { return; }
    $web = New-Object Net.WebClient;
    Invoke-Expression $web.DownloadString('https://get.scoop.sh');
    if (-not $?) { throw "Failed"; }
  }


  _installGit() {
    if ($this._isTest) { return; }
    if ($this._hasCli("git")) { return; }
    # Required for buckets
    scoop uninstall git;
    # Auto-installed with git
    scoop uninstall 7zip;
    scoop install git;
    if ($LASTEXITCODE -ne 0) { throw "Failed" }
    & git config --global core.autocrlf input;
    & git config --global user.name "Girogry Petrov";
    & git config --global user.email "grigoryvp@gmail.com";
  }


  _addScoopBuckets() {
    if ($this._isTest) { return; }
    # Required to install autohotkey
    if (-not @(scoop bucket list).Contains("extras")) {
      scoop bucket add extras;
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    # Required to install Monoid font.
    if (-not @(scoop bucket list).Contains("nerd-fonts")) {
      scoop bucket add nerd-fonts;
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    # Required to install kpscript
    if (-not @(scoop bucket list).Contains("grigoryvp")) {
      $uri = "https://github.com/grigoryvp/scoop-grigoryvp";
      scoop bucket add grigoryvp $uri;
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
  }


  _uploadSshKey() {
    $marker = ".uploaded_to_github";
    if (Test-Path -Path ".ssh/$marker") { return; }

    $pair = "$($this._github.user):$($this._github.token)";
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair);
    $creds = [System.Convert]::ToBase64String($bytes)
    $headers = @{Authorization = "Basic $creds";}
    $body = ConvertTo-Json @{
      title = "box key $(Get-Date)";
      key = (Get-Content "~/.ssh/id_rsa.pub" | Out-String);
    }
    $url = "https://api.github.com/user/keys"
    if (-not $this._isTest) {
      try {
        Invoke-WebRequest -Method 'POST' -Headers $headers -Body $body $url;
      }
      catch {
        if ($_.Exception.Response.StatusCode -eq 422) {
          Write-Host "SSH key already added to GitHub";
          New-Item -path .ssh -Name $marker -ItemType File | Out-Null;
        }
        elseif ($_.Exception.Response.StatusCode -eq 401) {
          # TODO: try to upload via auth token.
          Write-Host "Failed to add key to GitHub";
          Write-Host "Upload manually and touch .ssh/${marker}";
          Write-Host "Login: '$($this._github.user)'";
          Write-Host "Pass: '$($this._github.pass)'";
          throw "Failed";
        }
        else {
          throw "Failed $($_.Exception)";
        }
      }
      New-Item -path "~/.ssh" -Name $marker -ItemType File | Out-Null;
    }
  }


  _prompt($msg) {
    if ($this._isTest) { return; }
    Write-Host -NoNewLine $msg;
    [System.Console]::ReadKey("NoEcho,IncludeKeyDown") | Out-Null;
    Write-Host "";
  }

  
  _startAutohotkey() {
    if ($this._isTest) { return; }
    if (Get-Process "AutoHotkey" -ErrorAction SilentlyContinue) { return; }
    $this._prompt("Press any key to elevate the keyboard script...");
    $args = @{
      FilePath = 'autohotkey.exe'
      ArgumentList = "$($this._cfgDir)/keyboard.ahk"
      WindowStyle = 'Hidden'
      Verb = 'RunAs'
    };
    Start-Process @args;
  }


  _registerAutohotkeyStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path "$startDir\autohotkey.bat") {
      Remove-Item "$startDir\autohotkey.bat";
    }
    $content = "pwsh -Command Start-Process autohotkey.exe";
    $content += " -ArgumentList `"$($this._cfgDir)\keyboard.ahk`"";
    $content += " -WindowStyle Hidden -Verb RunAs";
    New-Item `
      -path $startDir `
      -Name "autohotkey.bat" `
      -Value "$content" `
      -ItemType File | Out-Null;
  }


  _installFonts() {
    if ($this._isTest) { return; }
    $fileName = "Monoid Regular Nerd Font Complete Mono Windows Compatible.ttf";
    if (Test-Path -Path "$env:windir\Fonts\$fileName") { return; }
    $appName = "Monoid-NF";
    if ($this._isAppStatusInstalled($appName)) {
      # if install fails, scoop will treat app as installed.
      & scoop uninstall $appName;
    }
    Start-Process scoop.cmd `
      -Wait `
      -Verb RunAs `
      -ArgumentList "install $appName";
  }


  _getXi() {
    if ($this._isTest) { return; }
    $dstDir = "$($env:USERPROFILE)/.xi";
    if (Test-Path -Path $dstDir) { return; }
    $uri = "git@github.com:grigoryvp/xi.git";
    & git clone $uri $dstDir;
    if ($LASTEXITCODE -ne 0) { throw "Failed" }
  }


  _configureVscode() {
    if ($this._isTest) { return; }
    $dstDir = "$($env:APPDATA)/Code/User";
    if (-not (Test-Path -Path $dstDir)) {
      # Not created during install, only on first UI start.
      New-Item -Path $dstDir -ItemType Directory | Out-Null;
    }

    $srcPath = "$($this._cfgDir)/vscode_settings.json";
    $dstPath = "$dstDir/settings.json";
    Copy-Item -Path $srcPath -Destination $dstPath -Force;

    $srcPath = "$($this._cfgDir)/vscode_keybindings.json";
    $dstPath = "$dstDir/keybindings.json";
    Copy-Item -Path $srcPath -Destination $dstPath -Force;

    $extList = @(& code --list-extensions);
    if (-not $extList.Contains("grigoryvp.language-xi")) {
      & code --install-extension grigoryvp.language-xi;
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    if (-not $extList.Contains("grigoryvp.memory-theme")) {
      & code --install-extension grigoryvp.memory-theme;
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    if (-not $extList.Contains("vscodevim.vim")) {
      & code --install-extension vscodevim.vim;
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    if (-not $extList.Contains("EditorConfig.EditorConfig")) {
      & code --install-extension EditorConfig.EditorConfig;
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    if (-not $extList.Contains("vscode-icons-team.vscode-icons")) {
      & code --install-extension vscode-icons-team.vscode-icons;
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }

    $docCfgDir = "$($env:USERPROFILE)/Documents/.vscode";
    if (-not (Test-Path -Path $docCfgDir)) {
      New-Item -Path $docCfgDir -ItemType Directory | Out-Null;
    }

    $content = @'
      {
        "files.exclude": {
          "My Music/": true,
          "My Pictures/": true,
          "My Videos/": true,
          "My Games/": true,
          "PowerShell": true,
          "WindowsPowerShell": true,
          "desktop.ini": true,
          ".vscode/": true
        }
      }
'@;

    New-Item `
      -path $docCfgDir `
      -Name "settings.json" `
      -Value "$content" `
      -ItemType File `
      -Force | Out-Null;

    ##  Exclude from 'ls'.
    $(Get-Item -Force $docCfgDir).Attributes = 'Hidden';
  }


  _configureBatteryInfoView() {
    if ($this._isTest) { return; }
    $appPath = "$($env:HOME)/scoop/apps/battery-info-view/current";
    $appCfgPath = "$($appPath)/BatteryInfoView.cfg";
    if (Test-Path -Path "$appCfgPath" ) {
      Remove-Item "$appCfgPath";
    }
    New-Item `
      -ItemType HardLink `
      -Path "$appPath" `
      -Name "BatteryInfoView.cfg" `
      -Value "$($this._cfgDir)/BatteryInfoView.cfg"
  }


  _registerBatteryInfoViewStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path "$startDir\battery-info-view.bat") {
      Remove-Item "$startDir\battery-info-view.bat";
    }
    $content = "pwsh -Command Start-Process BatteryInfoView.exe";
    $content += " -WindowStyle Hidden";
    New-Item `
      -path $startDir `
      -Name "battery-info-view.bat" `
      -Value "$content" `
      -ItemType File | Out-Null;
  }


  _registerBatteryIconStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path "$startDir\battery-icon.bat") {
      Remove-Item "$startDir\battery-icon.bat";
    }
    $content = "pwsh -Command Start-Process BatteryIcon.exe";
    $content += " -WindowStyle Hidden";
    New-Item `
      -path $startDir `
      -Name "battery-icon.bat" `
      -Value "$content" `
      -ItemType File | Out-Null;
  }


  _registerCpuIconStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path "$startDir\cpu-icon.bat") {
      Remove-Item "$startDir\cpu-icon.bat";
    }
    $content = "pwsh -Command Start-Process CpuIcon.exe";
    $content += " -WindowStyle Hidden";
    New-Item `
      -path $startDir `
      -Name "cpu-icon.bat" `
      -Value "$content" `
      -ItemType File | Out-Null;
  }


  _registerRamIconStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path "$startDir\ram-icon.bat") {
      Remove-Item "$startDir\ram-icon.bat";
    }
    $content = "pwsh -Command Start-Process RamIcon.exe";
    $content += " -WindowStyle Hidden";
    New-Item `
      -path $startDir `
      -Name "ram-icon.bat" `
      -Value "$content" `
      -ItemType File | Out-Null;
  }
}

# Stop on unhandled exceptions.
$ErrorActionPreference = "Stop";
$app = [App]::new($args);
$app.configure();
