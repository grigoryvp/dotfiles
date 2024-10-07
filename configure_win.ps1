function New-Hardlink() { New-Item -ItemType HardLink -Force @args; }
function New-Softlink() { New-Item -ItemType SymbolicLink -Force @args; }
function New-Dir() { New-Item -ItemType Directory -Force @args; }
function New-File() { New-Item -ItemType File -Force @args; }

class App {

  #region Instance properties
  $_ver = "1.0.17";
  $_isTest = $false;
  $_isFull = $false;
  $_isPublic = $false;
  $_POST_INSTALL_MSG = "";
  $_keepassdb = $null;
  $_pass = $null;
  $_cfgDirLinux = $null;
  $_cfgDir = $null;
  $_psDir = $null;
  $_pathIntrinsics = $null;
  $_github = @{
    user = "foo";
    pass = "bar";
    token = "baz";
  };
  $_mqtt = @{
    url = $null;
    user = $null;
    pass = $null;
  };
  #endregion


  App($argList, $pathIntrinsics) {
    $this._pathIntrinsics = $pathIntrinsics;
    $this._isTest = ($argList.Contains("--test"));
    $this._isFull = ($argList.Contains("--full"));
    # Do not touch private info like passwords, personal kb etc.
    $this._isPublic = ($argList.Contains("--public"));
    # Version-controlled dir with scripts, powershell config, passwords etc.
    $this._cfgDirLinux = "~/dotfiles";
    $this._cfgDir = $this._path(@("~", "dotfiles"));
    $this._psDir = $this._path(@("~", "Documents", "PowerShell"));
    $this._POST_INSTALL_MSG = @"
      Config complete. Manual things to do
      - Reboot and make --full configuration
      - Load X-Mouse Button Control settings
        * Disable 'Settings/Pointer/Change cursor when move to scroll'
        * Map Mouse4 => 'change movement to scroll' with setings:
          * Sensitivity 1
          * Invert axis
      - Disable adaptive contrast for the built-in Intel GPU, if any
      - "Change Proxy Settings", Turn off "Automatically Detect Settings"
      - Add C-S-4-5-6 as en-ru-js hotkeys and copy via "Region/Administrative"
      - Disable autostart in Task Manager
      - Disable autostart in Task Scheduler
      - Disable snap assist
      - Disable touchpad click and set maximum speed
      - Add "gmail", "google calendar", "trello" as chrome apps and pin
      - Pin pwsh, vscode, web, files, keepass, telegram, mail, cal, slack
      - Uninstall 'OneDrive' and other software
      - Login and sync browser
      - Switch nVidia display mode to "optimus" and drag gpu activity icon
      - Set Settings/Accounts/Sign-in/Sign-in to "Every time"
      - Set Settings/System/Power/Saver/Auto to "Never"
      - Uncheck "Sniping tool" in Settings/Accessibility/Keyboard
      - Disable ASUS "lightingservice", if any
      - Disable G-Sync in the nVidia settings
      - Disable the "SSDP Discovery" service
      - Disable Battle.net launcher "gpu acceleration"
"@;
  }


  configure() {
    Write-Host "Running configuration script v$($this._ver)";
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
  
    Write-Host "Downloading let's encrypt root certificate..."
    $url = "https://letsencrypt.org/certs/isrgrootx1.pem";
    $certFile = $this._path(@("~", "isrgrootx1.pem"));
    Invoke-WebRequest $url -OutFile $certFile
    $this._setEnv("MQTT_CERT", $certFile);

    # Game compatibility
    $this._setEnv("OPENSSL_ia32cap", "~0x20000000");

    # Requires reboot for a second stage install
    $this._installWsl();
    $this._installPowershellModule("posh-git");
    $this._installPowershellModule("WindowsCompatibility");
    $this._generateSshKey();
    $this._setPowerOptions();
    $this._setDebounceOptions();
    $this._setTouchpadOptions();
    $this._setInputMethodOptions();
    $this._installBinApp("Git.Git", $this._path(
      @(${env:ProgramFiles}, "Git", "cmd")));
    # Clone without keys via HTTPS
    $this._getFilesFromGit();
    $this._installLocationApp("AutoHotkey.AutoHotkey", "");
    $this._uninstallApp("Microsoft.OneDrive");
    $this._uninstallApp("Microsoft.Teams");
    $this._uninstallApp("Copilot");
    # TODO: Need version 2.20.4, in 2.20.5 "{WAITMS:100}{LMB}" does not work.
    # https://dvps.highrez.co.uk/downloads/XMouseButtonControlSetup.2.20.4.exe
    $this._installApp("Highresolution.X-MouseButtonControl");
    $this._installApp("Microsoft.VCRedist.2015+.x64");
    $this._installBinApp("KeePassXCTeam.KeePassXC", $this._path(
      @($env:ProgramFiles, "KeePassXC")));
    $this._installBinApp("Microsoft.VisualStudioCode", $this._path(
      @($env:LOCALAPPDATA, "Programs", "Microsoft VS Code", "bin")));
    $this._configureVscode();
    # Better ls
    $this._installApp("lsd-rs.lsd");
    $this._configureLsd();
    # TODO: install batteryinfoview via winget like "NirSoft.WifiInfoView"
    # this._installLocationApp("NirSoft.BatteryInfoView", "")
    # $name = "BatteryInfoView.cfg";
    # $srcPath = $this._path(@($this._cfgDir, $name));
    # $dstDir = $this._path(@("~", "apps", "NirSoft.BatteryInfoView"));
    # New-Hardlink -Path "$dstDir" -Name $name -Value "$srcPath";
    $dirname = "strayge.tray-monitor_Microsoft.Winget.Source_8wekyb3d8bbwe";
    $this._installApp("strayge.tray-monitor");
    # TODO: wait for https://github.com/microsoft/winget-pkgs/pull/178129
    # $this._installApp("EFLFE.PingoMeter");
    $this._registerAutohotkeyStartup();
    $this._registerXMouseButtonControlStartup();
    # TODO: wait for BatteryInfoView install
    # $this._registerBatteryInfoViewStartup();
    # TODO: wait for https://github.com/microsoft/winget-pkgs/pull/178129
    # $this._registerPingometerStartup();

    # Symlink PowerShel config file into PowerShell config dir.
    if (-not $this._isTest) {
      $src = $this._path(@($this._cfgDir, "profile.ps1"));
      $dst = $this._path(@($this._psDir, "profile.ps1"));
      if (Test-Path -Path "$dst") {
        Remove-Item "$dst" -Recurse -Force;
      }
      Write-Host "Creating hardlink $src => $dst";
      New-Hardlink -Path "$($this._psDir)" -Name "profile.ps1" -Value "$src";
    }

    # Create git config with link to the git-cfg.toml
    if (-not $this._isTest) {
      $src = $this._path(@($this._cfgDir, ".gitconfig"));
      $dst = $this._path(@("~", ".gitconfig"));
      if (Test-Path -Path "$dst") {
        Remove-Item "$dst" -Recurse -Force;
      }
      $content = "[include]`npath = `"$($this._cfgDirLinux)/git-cfg.toml`"`n";
      New-File -Path "~" -Name ".gitconfig" -Value "$content";
    }
    
    if (-not $this._isPublic) {
      $markerPath = $this._path(@("~", ".ssh", ".uploaded_to_github"));
      # Interactive.
      if (-not (Test-Path -Path "$markerPath")) {
        $this._askForCredentials();
        $this._setEnv("MQTT_URL", $this._mqtt.url);
        $this._setEnv("MQTT_USER", $this._mqtt.user);
        $this._setEnv("MQTT_PASS", $this._mqtt.pass);
        $this._uploadSshKey();
      }
      # Re-clone with SSH keys
      $this._getFilesFromGit();
    }

    # After additional files are received
  
    # Interactive
    $this._mapKeyboard();

    # Interactive.
    $this._installFonts();

    $this._getXiWindows();

    if (-not (Test-Path -Path ".editorconfig")) {
        $src = $this._path(@($this._cfgDir, ".editorconfig"));
        Copy-Item -Path "$src" -Destination . -Force;
    }

    # Optional installs after reboot
    if ($this._isFull) {
      # for diff-so-fancy
      $this._installBinApp("StrawberryPerl.StrawberryPerl",
        "C:\Strawberry\perl\bin\");
      # nvm command
      $this._installBinAppWithVer(
        "CoreyButler.NVMforWindows",
        $this._path(@($env:APPDATA, "nvm")),
        # version 1.1.12 fails "non-terminal" execution
        "1.1.11");
      # For nvm command to work in an existing terminal
      $env:NVM_HOME = $this._path(@($env:APPDATA, "nvm"));
      # Node.js
      Write-Host "Installing latest nodejs"
      & nvm install latest
      & nvm use latest
      $nodePath = $this._path(@($env:ProgramFiles, "nodejs"));
      if (-not $env:PATH.Contains($nodePath)) {
        $env:PATH = "${env:PATH};$nodePath";
      }
      Write-Host "Updating npm"
      & npm install -g npm@latest
      # Better diff
      & npm install -g diff-so-fancy
      # General-purpose messaging.
      $this._installApp("Telegram.TelegramDesktop");
      # "Offline" google apps support and no telemetry delays line in "Edge".
      $this._installApp("Google.Chrome");
      # PDF view.
      $this._installApp("Foxit.FoxitReader");
      # Better process maangement
      $this._installApp("Microsoft.Sysinternals.ProcessExplorer");
      # Desktop recording.
      $this._installApp("OBSProject.OBSStudio");
      # TODO: configure to save position on exit
      $this._installApp("clsid2.mpc-hc");
      # ag command, "the silver searcher"
      $this._installApp("JFLarvoire.Ag");
      # screenshot tool, "sniping tool" corrupts colors
      $this._installApp("Flameshot.Flameshot");
      # for g-helper
      $this._installApp("Microsoft.DotNet.DesktopRuntime.7");
      # for mosquitto_pub
      $this._installBinApp("EclipseFoundation.Mosquitto", $this._path(
        @($env:ProgramFiles, "mosquitto")));
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
    $res = & winget list
    if ($LASTEXITCODE -ne 0) { return $false; }
    return ($res | Out-String).Contains($appName);
  }


  [String] _path([array] $pathList) {
    return $this._pathIntrinsics.GetUnresolvedProviderPathFromPSPath(
      [io.path]::combine([string[]]$pathList));
  }


  _installApp($appName) {
    if ($this._isTest) { return; }
    if ($this._isAppStatusInstalled($appName)) {
      Write-Host "$appName is already installed";
      return;
    }
    Write-Host "Installing $appName"
    winget install --silent $appName;
    if ($LASTEXITCODE -ne 0) { throw "Failed to install $appName" }
  }


  _uninstallApp($appName) {
    if ($this._isTest) { return; }
    if (-not $this._isAppStatusInstalled($appName)) {
      Write-Host "$appName is already uninstalled";
      return;
    }
    Write-Host "Uninstalling $appName"
    winget uninstall --silent $appName;
    if ($LASTEXITCODE -ne 0) { throw "Failed to uninstall $appName" }
  }


  # For installers that add something to PATH (requires terminal restart)
  _installBinApp($appName, $binPath) {
    $this._installBinAppWithVer($appName, $binPath, $null);
  }

  _installBinAppWithVer($appName, $binPath, $ver) {
    if ($this._isTest) { return; }
    if ($this._isAppStatusInstalled($appName)) {
      Write-Host "$appName is already installed";
      if (-not $env:PATH.Contains($binPath)) {
        $env:PATH = "${env:PATH};$binPath";
      }
      return;
    }
    if ($ver) {
      Write-Host "Installing $appName with binary in path, version $ver"
      winget install --silent $appName --version $ver --no-upgrade --exact;
    }
    else {
      Write-Host "Installing $appName with binary in path"
      winget install --silent $appName;
    }
    if ($LASTEXITCODE -ne 0) { throw "Failed to install $appName" }
    if (-not $env:PATH.Contains($binPath)) {
      $env:PATH = "${env:PATH};$binPath";
    }
    $this._addToPath($binPath);
  }


  # For installers that require install location to be specified
  _installLocationApp($appName, $binSubpath) {
    $location = $this._path(@("~", "apps", $appName));
    $binPath = $this._path(@($location, $binSubpath));
    if ($this._isTest) { return; }
    if ($this._isAppStatusInstalled($appName)) {
      Write-Host "$appName is already installed";
      if (-not $env:PATH.Contains($binPath)) {
        $env:PATH = "${env:PATH};$binPath";
      }
      return;
    }
    Write-Host "Installing $appName into $location"
    winget install --silent --location $location $appName;
    if ($LASTEXITCODE -ne 0) { throw "Failed to install $appName" }
    if (-not $env:PATH.Contains($binPath)) {
      $env:PATH = "${env:PATH};$binPath";
    }
    $this._addToPath($binPath);
  }


  _installPowershellModule($moduleName) {
    Write-Host "Installing $moduleName";
    if ($this._isTest) { return; }
    if (Get-InstalledModule | Where-Object Name -eq $moduleName) { return; }
    Install-Module $moduleName -Scope CurrentUser;
    if (-not $?) { throw "Failed" }
  }


  _installWsl() {
    Write-Host "Installing WSL";
    if ($this._isTest) { return; }

    & wsl --status;
    if ($LASTEXITCODE -eq 0) {
      if (Test-Path -Path "\\wsl$\Ubuntu") {
        Write-Host "WSL is already installed";
        $wslSshDir = "\\wsl$\Ubuntu\home\user\.ssh"
        if (Test-Path -Path "$wslSshDir" ) {
          Write-Host "Keys are already copied to WSL"
          return;
        }
        else {
          Write-Host "Creating wsl://~/.ssh";
          New-Dir -Path "$wslSshDir";
          Write-Host "Copying keys to wsl://~/.ssh";
          $srcPath = $this._path(@("~", ".ssh", "id_rsa"))
          Copy-Item -Path "$srcPath" -Destination "$wslSshDir" -Force;
          $srcPath = $this._path(@("~", ".ssh", "id_rsa.pub"))
          Copy-Item -Path "$srcPath" -Destination "$wslSshDir" -Force;
          & wsl chmod 600 ~/.ssh/id_rsa
          return;
        }
      }
      else {
        # Need to be install two times: before and after reboot
        Write-Host "Installing WSL. Create a 'user' user with a password";
        Start-Process wsl -ArgumentList "--install" -Wait;
        return;
      }
    }
    else {
      Start-Process wsl -ArgumentList "--install" -Wait;
      return;
    }
  }


  _getFilesFromGit() {
    if ($this._isTest) { return; }
    $gitCfgFile = $this._path(@($this._cfgDir, ".git", "config"));
    if (Test-Path -Path "$gitCfgFile") {
      $gitCfg = Get-Content "$gitCfgFile" | Out-String;
      # Already cloned with SSH?
      if ($gitCfg.Contains("git@github.com")) {
        Write-Host "dotfiles already cloned via ssh";
        return;
      }
    }

    # Have keys to clone with SSH?
    $markerPath = $this._path(@("~", ".ssh", ".uploaded_to_github"));
    if (Test-Path -Path "$markerPath") {
      $uri = "git@github.com:grigoryvp/dotfiles.git";
    }
    else {
      # Already cloned without keys?
      if (Test-Path -Path "$gitCfgFile") {
        Write-Host "dotfiles already cloned via https";
        return;
      }
      # Clone with HTTPS
      $uri = "https://github.com/grigoryvp/dotfiles.git";
    }

    $tmpDirName = $this._path(@("~", "dotfiles-tmp"));
    if (Test-Path -Path "$tmpDirName") {
      Write-Host "Removing existing temp dir $tmpDirName"
      Remove-Item "$tmpDirName" -Recurse -Force;
    }
    Write-Host "Cloning into temp dir $tmpDirName"
    & git clone --quiet "$uri" "$tmpDirName";
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
    if (Test-Path -Path $this._path(@("~", ".ssh", "id_rsa"))) {
      Write-Host "ssh key already generated";
      return;
    }
    $sshDir = $this._path(@("~", ".ssh"));
    if (-not (Test-Path -Path "$sshDir" )) {
      Write-Host "Creating ~/.ssh";
      New-Dir -Path "$sshDir";
    }
    Write-Host "Generating ssh key";
    Start-Process ssh-keygen -ArgumentList '-N "" -f .ssh/id_rsa' -Wait;
  }


  _setPowerOptions() {
    if ($this._isTest) { return; }
    Write-Host "Setting power policy";
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
    Write-Host "Setting touchpad debounce options";

    $argmap = @{
      Path = "HKCU:\Control Panel\Accessibility\Keyboard Response"
      PropertyType = "String"
      Force = $true
    }

    # Ms before key is repeated
    $argmap.Name = 'AutoRepeatDelay';
    $argmap.Value = '400';
    New-ItemProperty @argmap;

    # Less is faster
    $argmap.Name = 'AutoRepeatRate';
    $argmap.Value = '30';
    New-ItemProperty @argmap;

    #  Milliseconds to supres bounce (with 30ms it RARELY bounces).
    #! On some laptops like Dell 5490 setting this value will result in fast
    #  double presses not handled.
    $argmap.Name = 'BounceTime';
    $argmap.Value = '35';
    New-ItemProperty @argmap;

    # Milliseconds to wait before accepting a keystroke
    $argmap.Name = 'DelayBeforeAcceptance';
    $argmap.Value = '0';
    New-ItemProperty @argmap;

    # Bit Flags:
    # 00000001 On
    # 00000010 Available
    # 00000100 Use shortcut
    # 00001000 Confirm activation
    # 00010000 Activation sound
    # 00100000 Show status
    # 01000000 Key click
    $argmap.Name = 'Flags';
    $argmap.Value = '1';
    New-ItemProperty @argmap;
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


  # Remapped via RandyRants.SharpKeys
  _mapKeyboard() {
    if (-not $this._needMapCapsToF24()) {
      Write-Host "caps already mapped to F24";
      return;
    }

    Write-Host "mapping caps to F24";
    # caps to F24 for autohotkey meta
    # tab to lctrl (autohotkey changes single key back to tab)
    # enter to rctrl (autohotkey change single key back to enter)
    # left alt to esc for left-hand keypad gaming
    # right alt for enter (so enter key is available for login screen)
    # left ctrl to left win for left-hand keypad gaming (no win key)
    $val = ([byte[]](
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x07, 0x00, 0x00, 0x00, 0x6F, 0x00, 0x3A, 0x00,
        0x1D, 0xE0, 0x1C, 0x00, 0x01, 0x00, 0x38, 0x00,
        0x5B, 0xE0, 0x1D, 0x00, 0x1C, 0x00, 0x38, 0xE0,
        0x1D, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x00, 0x00
    ));
    New-ItemProperty `
      -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout" `
      -Name "Scancode Map" `
      -PropertyType "Binary" `
      -Value $val `
      -Force
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
    $current = & pwsh -Command Get-WinUserLanguageList | Out-String;
    if (-not $current.Contains("Russian")) {
      Write-Host "Adding Russian language";
      $cmd = '' +
        '$list = Get-WinUserLanguageList;' +
        '$list.Add("ru");' +
        'Set-WinUserLanguageList -Force $list;';
      & pwsh -Command $cmd;
    }
    if (-not $current.Contains("Japanese")) {
      Write-Host "Adding Japanese language";
      $cmd = '' +
        '$list = Get-WinUserLanguageList;' +
        '$list.Add("ja");' +
        'Set-WinUserLanguageList -Force $list;';
      & pwsh -Command $cmd;
    }
  }


  [String] _attrFromKeepass($record, $attr) {
    # -s to show protected attribute (password) as clear text.
    $ret = & Write-Output $this._pass | keepassxc-cli `
      show -s $this._keepassdb $record --attributes $attr;
    return $ret;
  }


  _askForCredentials() {
    $pass = Read-Host -AsSecureString -Prompt "Enter password"

    $ptr = [Security.SecureStringMarshal]::SecureStringToCoTaskMemAnsi($pass);
    $pass = [Runtime.InteropServices.Marshal]::PtrToStringAnsi($ptr);
    $this._pass = $pass;
    $this._keepassdb = $this._path(@($this._cfgDir, "passwords.kdbx"));

    $this._github.user = $this._attrFromKeepass("github", "username");
    $this._github.pass = $this._attrFromKeepass("github", "password");
    $this._github.token = $this._attrFromKeepass("github", "auto-cfg-token");

    $this._mqtt.url = $this._attrFromKeepass("hivemq", "login_url");
    $this._mqtt.user = $this._attrFromKeepass("hivemq", "login_user");
    $this._mqtt.pass = $this._attrFromKeepass("hivemq", "login_pass");
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
          Write-Host "ssh key already added to GitHub";
          New-File -Path .ssh -Name $marker;
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
      New-File -Path "~/.ssh" -Name $marker;
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

    $name = "autohotkey";
  
    $argmap = @{
      Execute = $this._path(@(
        "~", "apps", "AutoHotkey.AutoHotkey", "v2", "autohotkey.exe"))
      Argument = $this._path(@($this._cfgDir, "keyboard.ahk"))
    }
    $action = New-ScheduledTaskAction @argmap;
    $trigger = New-ScheduledTaskTrigger -AtLogOn;
    # Delay for a few seconds, otherwise Windows will not display tray icon
    $trigger.Delay = 'PT5S'

    $task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue;
    if (-not $task) {
      Write-Host "Creating new AutoHotkey scheduled task";
      Register-ScheduledTask -TaskName $name `
        -Action $action -Trigger $trigger -RunLevel Highest;
    }
    else {
      Write-Host "Modifying existing AutoHotkey scheduled task";
    }

    Set-ScheduledTask -TaskName $name -Action $action;

    Set-ScheduledTask -TaskName $name -Trigger $trigger;

    $settings = New-ScheduledTaskSettingsSet `
      -ExecutionTimeLimit 0 `
      -AllowStartIfOnBatteries;
    Set-ScheduledTask -TaskName $name -Settings $settings;
  }


  [Boolean] _needInstallFonst() {
    $path = $this._path(@("~", "apps", "nerd-fonts"));
    if (Test-Path -Path $path) { return $false; }
    return $true;
  }


  _installFonts() {
    if (-not $this._needInstallFonst()) {
      Write-Host "Fonts are already installed";
      return;
    }

    $path = $this._path(@("~", "apps", "nerd-fonts"));
    $uri = "https://github.com/ryanoasis/nerd-fonts.git";
    $fontName = "JetBrainsMono";
    Write-Host "Cloning nerd-fonts into $path";
    & git clone --quiet --depth 1 --filter=blob:none --sparse $uri $path;
    Set-Location $path;
    Write-Host "Checking out files for $fontName";
    & git sparse-checkout add "patched-fonts/$fontName";
    Write-Host "Installing $fontName";
    & "./install.ps1" $fontName;
  }


  _getXiWindows() {
    if ($this._isTest) { return; }
    $uri = "git@github.com:grigoryvp/xi.git";
    $dstDir = $this._path(@("~", ".xi"));
    if (Test-Path -Path "$dstDir") {
      Write-Host "xi already cloned";
      return;
    }
    Write-Host "cloning xi into $dstDir";
    & git clone $uri $dstDir;
    return;
  }


  # Not used since VSCode always opens host dir even if remoting WSL.
  _getXiWSL() {
    if ($this._isTest) { return; }
    $dstDir = "\\wsl$\Ubuntu\home\user\.xi"
    if (Test-Path -Path "$dstDir") {
      Write-Host "xi already cloned";
      return;
    }
    Write-Host "cloning xi into $dstDir";
    $uri = "git@github.com:grigoryvp/xi.git";
    & wsl git clone $uri $dstDir;
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
    New-Hardlink -Path "$dstDir" -Name "settings.json" -Value "$srcPath";

    $srcPath = $this._path(@($this._cfgDir, "vscode_keybindings.json"));
    New-Hardlink -Path "$dstDir" -Name "keybindings.json" -Value "$srcPath";

    $srcPath = $this._path(@($this._cfgDir, "vscode_tasks.json"));
    New-Hardlink -Path "$dstDir" -Name "tasks.json" -Value "$srcPath";

    $srcPath = $this._path(@($this._cfgDir, "vscode_snippets/"));
    $dstPath = $this._path(@($dstDir, "vscode_snippets/"));
    if (Test-Path -Path "$dstPath") {
        Remove-Item "$dstPath" -Recurse -Force;
    }
    New-Softlink -Path "$dstDir" -Name "vscode_snippets/" -Value "$srcPath";

    $extList = @(& code --list-extensions);
    if (-not $extList.Contains("grigoryvp.language-xi")) {
      & code --install-extension "grigoryvp.language-xi";
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    if (-not $extList.Contains("grigoryvp.memory-theme")) {
      & code --install-extension "grigoryvp.memory-theme";
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    if (-not $extList.Contains("grigoryvp.goto-link-provider")) {
      & code --install-extension "grigoryvp.goto-link-provider";
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    if (-not $extList.Contains("vscodevim.vim")) {
      & code --install-extension "vscodevim.vim";
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    if (-not $extList.Contains("EditorConfig.EditorConfig")) {
      & code --install-extension "editorConfig.editorConfig";
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    if (-not $extList.Contains("esbenp.prettier-vscode")) {
      & code --install-extension "esbenp.prettier-vscode";
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    if (-not $extList.Contains("formulahendry.auto-close-tag")) {
      & code --install-extension "formulahendry.auto-close-tag";
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
          "Sound Recordings/": true,
          "Diablo IV/": true,
          "PowerShell": true,
          "WindowsPowerShell": true,
          "desktop.ini": true,
          ".vscode/": true
        }
      }
'@;

    New-File -Path $docCfgDir -Name "settings.json" -Value "$content";

    ##  Exclude from 'ls'.
    $(Get-Item -Force $docCfgDir).Attributes = 'Hidden';
  }


  _configureLsd() {
    $dstDir = $this._path(@($env:APPDATA, "lsd"));
    if (-not (Test-Path -Path "$dstDir")) {
      New-Dir -Path "$dstDir";
    }
    $srcPath = $this._path(@($this._cfgDir, "lsd.config.yaml"));
    New-Hardlink -Path "$dstDir" -Name "config.yaml" -Value "$srcPath";
  }


  _registerBatteryInfoViewStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path "$startDir\battery-info-view.bat") {
      Remove-Item "$startDir\battery-info-view.bat" -Recurse -Force;
    }
    $content = "pwsh -Command Start-Process BatteryInfoView.exe";
    $content += " -WindowStyle Hidden";
    $name = "battery-info-view.bat"
    New-File -Path $startDir -Name $name -Value "$content";
  }


  _registerXMouseButtonControlStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path "$startDir\x-mouse-button-control.bat") {
      Remove-Item "$startDir\x-mouse-button-control.bat" -Recurse -Force;
    }
    $content = "pwsh -Command Start-Process XMouseButtonControl.exe";
    $content += " -WindowStyle Hidden";
    $name = "x-mouse-button-control.bat";
    New-File -path $startDir -Name $name -Value "$content" `
  }


  _registerPingometerStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path "$startDir\pingometer.bat") {
      Remove-Item "$startDir\pingometer.bat" -Recurse -Force;
    }
    $content = "pwsh -Command Start-Process Pingometer.exe";
    $content += " -WindowStyle Hidden";
    $name = "pingometer.bat";
    New-File -path $startDir -Name $name -Value "$content";
  }


  _addToPath($subpath) {
    $root = "HKLM:\SYSTEM\CurrentControlSet\Control";
    $uri = "$root\Session Manager\Environment";
    $name = "Path";
    $ret = Get-ItemProperty -Path $uri -Name $name `
      -ErrorAction SilentlyContinue;
    if ($ret) {
      $path = $ret.Path;
      if (-not $path.Contains($subpath)) {
        $path = "${path};$subpath";
        # Requires reboot
        Set-ItemProperty $uri -Name $name -Value $path;
      }
    }
  }


  _setEnv($name, $val) {
    $root = "HKLM:\SYSTEM\CurrentControlSet\Control";
    $uri = "$root\Session Manager\Environment";
    $ret = Get-ItemProperty -Path $uri -Name $name `
      -ErrorAction SilentlyContinue;
    if ($ret) {
      # Requires reboot
      Set-ItemProperty $uri -Name $name -Value $val;
    }
    else {
      New-ItemProperty `
        -Path $uri `
        -PropertyType String `
        -Name $name `
        -Value $val `
        -Force;
    }
  }

  # Apps that are not used anymore but have non-trivial install instructions
  _notUsed() {
    $this._InstallBinApp("Chocolatey.Chocolatey", $this._path(
      @($env:ProgramData, "chocolatey", "bin")));
    # Windows 11 now has sudo under "developer settings". It's worse than
    # this one, since it spawns new terminal windows instead of resuing
    # the current one.
    $this._installApp("gerardog.gsudo");
  }
}

# Stop on unhandled exceptions.
$ErrorActionPreference = "Stop";
$pathIntrinsics = $ExecutionContext.SessionState.Path;
$app = [App]::new($args, $pathIntrinsics);
$app.configure();
