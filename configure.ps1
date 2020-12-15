function New-Hardlink() { New-Item -ItemType HardLink -Force @Args; }
function New-Dir() { New-Item -ItemType Directory -Force @Args; }
function New-File() { New-Item -ItemType File -Force @Args; }

class App {

  #region Instance properties
  $_isTest = $false;
  $_isFull = $false;
  $_isPublic = $false;
  $_POST_INSTALL_MSG = "";
  $_pass = $null;
  $_cfgDir = $null;
  $_psDir = $null;
  $_pathIntrinsics = $null;
  $_github = @{
    user = "foo";
    pass = "bar";
    token = "baz";
  };
  #endregion


  App($argList, $pathIntrinsics) {
    $this._pathIntrinsics = $pathIntrinsics;
    $this._isTest = ($argList.Contains("--test"));
    $this._isFull = ($argList.Contains("--full"));
    # Do not touch private info like passwords, personal kb etc.
    $this._isPublic = ($argList.Contains("--public"));
    # Version-controlled dir with scripts, powershell config, passwords etc.
    $this._cfgDir = $this._path(@("~", ".box-cfg"));
    $this._psDir = $this._path(@("~", "Documents", "PowerShell"));
    $this._POST_INSTALL_MSG = @"
      Config complete. Manual things to do
      - Reboot
      - Make --full configuration
      - "colortool.exe Dracula-ColorTool.itermcolors" and confirm cmd.exe cfg
      - Map Mouse4 => 'movement to scroll' via X-Mouse; turn off ScrollLock
      - Disable adaptive contrast for the built-in Intel GPU, if any
      - "Change Proxy Settings", Turn off "Automatically Detect Settings"
      - Add C-S-4-5-6 as en-ru-js hotkeys and copy settings
      - Disable autostart in Task Manager
      - Disable autostart in Task Scheduler
      - Disable snap assist
      - Disable touchpad click
      - Add perfgraph toolbar
      - Pin pwsh (+icon), vscode, browser, files, keepass, telegram
      - Uninstall 'OneDrive' and other software
      - Login and sync browser
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

    # For 'Install-Module'
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted;

    if (-not $this._isTest) {
      if (-not (Test-Path -Path "$($this._cfgDir)")) {
        New-Dir -Path "$($this._cfgDir)";
      }
    }

    # Auto-created by PowerShell 5.x until 6.x+ is a system default.
    # Create and set hidden attribute to exclude from 'ls'.
    if (-not $this._isTest) {
      $oldPsDir = $this._path(@("~", "Documents", "WindowsPowerShell"));
      if (-not (Test-Path -Path "$oldPsDir")) {
        Write-Host "Creating dir $oldPsDir";
        $ret = & New-Dir -Path "$oldPsDir";
        $ret.Attributes = 'Hidden';
      }
      else {
        Write-Host "$oldPsDir already exists";
      }
    }

    # PowerShell config is loaded from this dir.
    # Create and set hidden attribute to exclude from 'ls'.
    if (-not $this._isTest) {
      if (-not (Test-Path -Path "$($this._psDir)")) {
        Write-Host "Creating dir $($this._psDir)";
        $ret = & New-Dir -Path "$($this._psDir)";
        $ret.Attributes = 'Hidden';
      }
      else {
        Write-Host "$($this._psDir) already exists";
      }
    }

    # Used by '_mapCapsToF24'.
    $this._installApp("sudo");
    # Used for cmd.exe color scheme configuration
    $this._installApp("colortool");
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
    $this._installApp("autohotkey");
    $this._installApp("xmousebuttoncontrol");
    $this._installApp("keepassxc");
    $this._installApp("vscode");
    $this._installApp("lsd");
    $this._configureVscode();
    $this._installApp("tray-monitor");
    $this._installApp("battery-info-view");
    $this._copyToAppDir("BatteryInfoView.cfg", "battery-info-view");
    $this._registerAutohotkeyStartup();
    $this._registerBatteryInfoViewStartup();
    $this._registerBatteryIconStartup();
    $this._registerCpuIconStartup();
    $this._registerRamIconStartup();
    $this._registerXMouseButtonControlStartup();

    # Symlink PowerShel config file into PowerShell config dir.
    if (-not $this._isTest) {
      $src = $this._path(@($this._cfgDir, "profile.ps1"));
      $dst = $this._path(@($this._psDir, "profile.ps1"));
      if (Test-Path -Path "$dst") {
        Remove-Item "$dst";
      }
      Write-Host "Creating hardlink $src => $dst";
      New-Hardlink -Path "$($this._psDir)" -Name "profile.ps1" -Value "$src";
    }

    # Symlink git config.
    if (-not $this._isTest) {
      $src = $this._path(@($this._cfgDir, "shell", ".gitconfig"));
      $dst = $this._path(@("~", ".gitconfig"));
      if (Test-Path -Path "$dst") {
        Remove-Item "$dst";
      }
      Write-Host "Creating hardlink $src => $dst";
      New-Hardlink -Path "~" -Name ".gitconfig" -Value "$src";
    }
    
    # TODO: symlink '~/AppData/Local/Microsoft/Windows Terminal/profiles.json'

    # Interactive.
    $markerPath = $this._path(@("~", ".ssh", ".uploaded_to_github"));
    if (-not (Test-Path -Path "$markerPath")) {
      if (-not $this._isPublic) {
        $this._askForGithubCredentials();
      }
    }

    if (-not $this._isPublic) {
      $this._uploadSshKey();
    }

    if ($this._needMapCapsToF24() -or $this._needInstallFonst()) {
      $this._prompt("Press any key to begin elevation prompts...");
    }

    # After additional files are received
    # Interactive
    $this._mapCapsToF24();

    # Interactive.
    $this._installFonts();

    if (-not $this._isPublic) {
      # Re-clone with SSH keys
      $this._getFilesFromGit();
    }

    $this._getXi();

    if (-not (Test-Path -Path ".editorconfig")) {
        $src = $this._path(@($this._cfgDir, ".editorconfig"));
        Copy-Item -Path "$src" -Destination . -Force;
    }

    # Optional installs
    if ($this._isFull) {
      # General-purpose messaging.
      $this._installApp("grigoryvp/telegram");
      # PDF view.
      $this._installApp("foxit-reader");
      # 'psexec' (required to start non-elevated apps), 'procexp' etc
      $this._installApp("sysinternals");
      # Desktop recording.
      $this._installApp("obs-studio");
      # TODO: configure to save position on exit
      $this._installApp("mpc-hc-fork");
      # TODO: unattended install for current user
      $this._installApp("perfgraph");
    }

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
    if (-not (Test-Path -Path "$installDir")) { return $false; }
    $content = Get-ChildItem "$installDir";
    return ($content.Length -gt 0);
  }


  [String] _path([array] $pathList) {
    $joined = [io.path]::combine([string[]]$pathList)
    return $this._pathIntrinsics.GetUnresolvedProviderPathFromPSPath($joined);
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
    $srcFilePath = $this._path(@($this._cfgDir, $fileName));
    $dstPath = $this._path(@("~", "scoop", "apps", $appName, "current"));
    $dstFilePath = $this._path(@($dstPath, $fileName));
    if (Test-Path -Path "$dstFilePath" ) {
      Remove-Item "$dstFilePath";
    }
    Copy-Item -Path "$srcFilePath" -Destination "$dstPath" -Force;
  }


  _linkToAppDir($fileName, $appName) {
    if ($this._isTest) { return; }
    $srcFilePath = $this._path(@($this._cfgDir, $fileName));
    $dstPath = $this._path(@("~", "scoop", "apps", $appName, "current"));
    $dstFilePath = $this._path(@($dstPath, $fileName));
    if (Test-Path -Path "$dstFilePath" ) {
      Remove-Item "$dstFilePath";
    }
    New-Hardlink -Path "$dstPath" -Name "$fileName" -Value "$srcFilePath";
  }


  _getFilesFromGit() {
    if ($this._isTest) { return; }
    $gitCfgFile = $this._path(@($this._cfgDir, ".git", "config"));
    if (Test-Path -Path "$gitCfgFile") {
      $gitCfg = Get-Content "$gitCfgFile" | Out-String;
      # Already cloned with SSH?
      if ($gitCfg.Contains("git@github.com")) { return; }
    }

    # Have keys to clone with SSH?
    $markerPath = $this._path(@("~", ".ssh", ".uploaded_to_github"));
    if (Test-Path -Path "$markerPath") {
      $uri = "git@github.com:grigoryvp/box-cfg.git";
    }
    else {
      # Already cloned without keys?
      if (Test-Path -Path "$gitCfgFile") { return; }
      # Clone with HTTPS
      $uri = "https://github.com/grigoryvp/box-cfg.git";
    }

    $tmpDirName = $this._path(@("~", ".box-cfg-tmp"));
    if (Test-Path -Path "$tmpDirName") {
      Write-Host "Removing existing temp dir $tmpDirName"
      Remove-Item "$tmpDirName" -Recurse -Force;
    }
    Write-Host "Cloning into temp dir $tmpDirName"
    & git clone "$uri" "$tmpDirName";
    # Replace HTTP git config with SSH one, if any.
    Write-Host "Removing current dir $($this._cfgDir)"
    Remove-Item "$($this._cfgDir)" -Recurse -Force;
    Write-Host "Recreating config dir $($this._cfgDir)"
    New-Dir -Path $this._cfgDir;
    Write-Host "Moving files $tmpDirName => $($this._cfgDir)";
    Move-Item -Force "$tmpDirName/*" "$($this._cfgDir)";
    Write-Host "Removing temp dir $tmpDirName";
    Remove-Item "$tmpDirName" -Recurse -Force;
  }


  _generateSshKey() {
    if ($this._isTest) { return; }
    if (Test-Path -Path $this._path(@("~", ".ssh", "id_rsa"))) { return; }
    $sshDir = $this._path(@("~", ".ssh"));
    if (-not (Test-Path -Path "$sshDir" )) {
      New-Dir -Path "$sshDir";
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


  [Boolean] _needMapCapsToF24() {
    if ($this._isTest) { return $false; }
    $val = Get-ItemProperty `
      -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout" `
      -Name "Scancode Map" `
      -ErrorAction SilentlyContinue;
    if ($val) {
      $len = $val.'Scancode Map'.Length;
      # Already set?
      if ($len -eq 20) { return $false; }
    }
    return $true;
  }

  _mapCapsToF24() {
    if (-not $this._needMapCapsToF24()) { return; }
    & sudo pwsh $this._path(@($this._cfgDir, "map_caps_to_f24.ps1"));
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

    $db = $this._path(@($this._cfgDir, "passwords.kdbx"));
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
  }


  _addScoopBuckets() {
    if ($this._isTest) { return; }
    # Required to install autohotkey
    if (-not @(scoop bucket list).Contains("extras")) {
      scoop bucket add extras;
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    # Required to install fonts.
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
    if (Test-Path -Path $this._path(@("~", ".ssh", "$marker"))) { return; }

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
          New-File -path .ssh -Name $marker;
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
      New-File -path "~/.ssh" -Name $marker;
    }
  }


  _prompt($msg) {
    if ($this._isTest) { return; }
    Write-Host -NoNewLine $msg;
    [System.Console]::ReadKey("NoEcho,IncludeKeyDown");
    Write-Host "";
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
    New-File -path $startDir -Name "autohotkey.bat" -Value "$content";
  }


  [Boolean] _needInstallFonst() {
    if ($this._isTest) { return $false; }
    $name =
      "JetBrains Mono Regular Nerd Font Complete Windows Compatible.ttf";
    if (Test-Path -Path "$env:windir\Fonts\$name") { return $false; }
    return $true;
  }

  _installFonts() {
    if (-not $this._needInstallFonst()) { return; }
    $appName = "JetBrainsMono-NF";
    if ($this._isAppStatusInstalled($appName)) {
      # if install fails, scoop will treat app as installed.
      & scoop uninstall $appName;
    }
    & sudo scoop install "$appName";
  }


  _getXi() {
    if ($this._isTest) { return; }
    $dstDir = $this._path(@("~", ".xi"));
    if (Test-Path -Path "$dstDir") { return; }
    $uri = "git@github.com:grigoryvp/xi.git";
    & git clone $uri $dstDir;
    if ($LASTEXITCODE -ne 0) { throw "Failed" }
  }


  _configureVscode() {
    if ($this._isTest) { return; }
    $dstDir = $this._path(@($env:APPDATA, "Code", "User"));
    if (-not (Test-Path -Path "$dstDir")) {
      # Not created during install, only on first UI start.
      New-Dir -Path "$dstDir";
    }

    $srcPath = $this._path(@($this._cfgDir, "vscode_settings.json"));
    $dstPath = $this._path(@($dstDir, "settings.json"));
    Copy-Item -Path "$srcPath" -Destination $dstPath -Force;

    $srcPath = $this._path(@($this._cfgDir, "vscode_keybindings.json"));
    $dstPath = $this._path(@($dstDir, "keybindings.json"));
    Copy-Item -Path "$srcPath" -Destination $dstPath -Force;

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

    $docCfgDir = $this._path(@("~", "Documents", ".vscode"));
    if (-not (Test-Path -Path "$docCfgDir")) {
      New-Dir -Path "$docCfgDir";
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

    New-File -path $docCfgDir -Name "settings.json" -Value "$content";

    ##  Exclude from 'ls'.
    $(Get-Item -Force $docCfgDir).Attributes = 'Hidden';
  }


  _registerBatteryInfoViewStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path "$startDir\battery-info-view.bat") {
      Remove-Item "$startDir\battery-info-view.bat";
    }
    $content = "pwsh -Command Start-Process BatteryInfoView.exe";
    $content += " -WindowStyle Hidden";
    $name = "battery-info-view.bat"
    New-File -Path $startDir -Name $name -Value "$content";
  }


  _registerBatteryIconStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path "$startDir\battery-icon.bat") {
      Remove-Item "$startDir\battery-icon.bat";
    }
    $content = "pwsh -Command Start-Process BatteryIcon.exe";
    $content += " -WindowStyle Hidden";
    $name = "battery-icon.bat";
    New-File -Path $startDir -Name $name -Value "$content";
  }


  _registerCpuIconStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path "$startDir\cpu-icon.bat") {
      Remove-Item "$startDir\cpu-icon.bat";
    }
    $content = "pwsh -Command Start-Process CpuIcon.exe";
    $content += " -WindowStyle Hidden";
    $name = "cpu-icon.bat";
    New-File -path $startDir -Name $name -Value "$content";
  }


  _registerRamIconStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path "$startDir\ram-icon.bat") {
      Remove-Item "$startDir\ram-icon.bat";
    }
    $content = "pwsh -Command Start-Process RamIcon.exe";
    $content += " -WindowStyle Hidden";
    $name = "ram-icon.bat";
    New-File -path $startDir -Name $name -Value "$content";
  }


  _registerXMouseButtonControlStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path "$startDir\x-mouse-button-control.bat") {
      Remove-Item "$startDir\x-mouse-button-control.bat";
    }
    $content = "pwsh -Command Start-Process XMouseButtonControl.exe";
    $content += " -WindowStyle Hidden";
    $name = "x-mouse-button-control.bat";
    New-File -path $startDir -Name $name -Value "$content" `
  }
}

# Stop on unhandled exceptions.
$ErrorActionPreference = "Stop";
$pathIntrinsics = $ExecutionContext.SessionState.Path;
$app = [App]::new($args, $pathIntrinsics);
$app.configure();
