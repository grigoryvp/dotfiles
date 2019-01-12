class App {

  #region Instance properties
  $_isTest = $false;
  $_isFull = $false;
  $_isPublic = $false;
  $_POST_INSTALL_MSG = "";
  $_pass = $null;
  $_cfgDir = $null;
  $_github = @{
    user = "foo";
    pass = "bar";
  };
  #endregion


  App($argList) {
    $this._isTest = ($argList.Contains("--test"));
    $this._isFull = ($argList.Contains("--full"));
    # Do not touch private info like passwords, personal kb etc.
    $this._isPublic = ($argList.Contains("--public"));
    $this._POST_INSTALL_MSG = @"
      Config complete. Manual things to do
      - Add C-S-4-5-6 as en-ru-js hotkeys and copy settings
      - Select tray icons: 'batteryicon', 'ramicon', 'cpuicon'
      - Disable autostart in Task Manager
      - Make --full configuration
      - Add perfgraph toolbar
      - Login Chromium
"@;
  }


  configure() {
    Push-Location;

    # Required by Posh-Git, sudo etc.
    if ((Get-ExecutionPolicy -Scope CurrentUser) -ne "Unrestricted") {
      # scoop shims like sudo are executed via powershell.exe and it seems
      # that pwsh.exe and powershell.exe have separated execution policy
      # config
      & powershell.exe `
        -Command Set-ExecutionPolicy Unrestricted `
        -Scope CurrentUser;
    }

    Set-Location -Path $env:USERPROFILE

    # Version-controlled dir with scripts, powershell config, passwords etc.
    $this._cfgDir = "$($env:USERPROFILE)\Documents\PowerShell";
    if (-not (Test-Path -Path $this._cfgDir)) {
      New-Item -Path $this._cfgDir -ItemType Directory | Out-Null;
    }

    # Auto-created by PowerShell 5.x until 6.x+ is a system default.
    # Create and set hidden attribute to exclude from 'ls'.
    $oldPsDir = "$($env:USERPROFILE)\Documents\WindowsPowerShell";
    if (-not (Test-Path -Path $oldPsDir)) {
      New-Item -Path $oldPsDir -ItemType Directory | Out-Null;
    }

    # Exclude dirs from 'ls' and 'explorer'
    $(Get-Item -Force $this._cfgDir).Attributes = 'Hidden';
    $(Get-Item -Force $oldPsDir).Attributes = 'Hidden';

    $this._installPowershellModule("posh-git");
    $this._installPowershellModule("WindowsCompatibility");
    $this._generateSshKey();
    $this._setPowerOptions();
    $this._setDebounceOptions();
    $this._setTouchpadOptions();
    $this._setInputMethodOptions();
    $this._installScoop();
    # Patch blocked 7zip URL.
    $this._patchScoopBucket();
    $this._installGit();
    $this._addScoopBuckets();
    # Patch blocked Telegram URL.
    $this._patchExtrasBucket();
    # Clone without keys via HTTPS
    $this._getFilesFromGit();
    $this._installApp("sudo");
    $this._installApp("autohotkey");
    $this._installApp("keepass");
    $this._installApp("kpscript");
    $this._installApp("hyper");
    $this._installApp("vscode");
    $this._configureVscode();
    $this._installApp("doublecmd");
    $this._installApp("tray-monitor");
    $this._registerAutohotkeyStartup();
    $this._registerKeepassStartup();

    # Interactive.
    if (-not (Test-Path -Path .ssh\.uploaded_to_github)) {
      if (-not $this._isPublic) {
        $this._askForGithubCredentials();
      }
    }
    # Interactive.
    $this._startAutohotkey();
    # Interactive.
    $this._installFonts();

    if (-not $this._isPublic) {
      $this._uploadSshKey();
    }

    if (-not $this._isPublic) {
      # Re-clone with SSH keys
      $this._getFilesFromGit();
    }
    $this._copyToAppDir("KeePass.config.xml", "keepass");
    $this._getXi();
    $this._startKeepass();

    if (-not (Test-Path -Path ".editorconfig")) {
        $src = "$($this._cfgDir)/.editorconfig";
        Copy-Item -Path $src -Destination . -Force | Out-Null;
    }

    # Optional installs
    if ($this._isFull) {
      # 'psexec' (required to start non-elevated apps), 'procexp' etc
      $this._installApp("sysinternals");
      # Need to restart terminal in order to apply env variables.
      $this._installApp("nodejs");
      $this._installApp("chromium");
      $this._installApp("foxit-reader");
      $this._installApp("obs-studio");
      $this._installApp("rufus");
      $this._installApp("smplayer");
      if (-not $this._hasCli("g")) {
        & npm i -g git-alias;
      }
      $this._installApp("telegram");
      # TODO: unattended install for current user
      $this._installApp("perfgraph");
    }

    Pop-Location;
    if ($this._isTest) {
      Write-Host "Test complete";
    }
    else {
      Write-Host $this._POST_INSTALL_MSG;
    }
  }


  [Boolean] _hasCli($name) {
    Get-Command $name -ErrorAction SilentlyContinue;
    return $?;
  }


  [Boolean] _isAppStatusInstalled($appName) {
    $res = & scoop info $appName;
    if ($LASTEXITCODE -ne 0) { return $false; }
    return (-not ($res | Out-String).Contains("Installed: No"));
  }

  [Boolean] _hasApp($appName) {
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
    Install-Module `
      $moduleName `
      -Scope CurrentUser `
      -AllowPrerelease -Force;
    if (-not $?) { throw "Failed" }
  }


  _copyToAppDir($fileName, $appName) {
    $srcPath = "$($this._cfgDir)\$fileName";
    $dstPath = "$($env:USERPROFILE)\scoop\apps\$appName\current\";
    Copy-Item -Path $srcPath -Destination $dstPath -Force;
  }


  _getFilesFromGit() {
    $gitCfgFile = "$($this._cfgDir)\.git\config";
    if (Test-Path -Path $gitCfgFile) {
      $gitCfg = Get-Content $gitCfgFile | Out-String;
      # Already cloned with SSH?
      if ($gitCfg.Contains("git@github.com")) { return; }
    }

    # Have keys to clone with SSH?
    if (Test-Path -Path .ssh\.uploaded_to_github) {
      $uri = "git@github.com:grigoryvp/my-win-box-cfg.git";
    }
    else {
      # Already cloned without keys?
      if (Test-Path -Path $gitCfgFile) { return; }
      # Clone with HTTPS
      $uri = "https://github.com/grigoryvp/my-win-box-cfg.git";
    }

    & git clone $uri "$($this._cfgDir).tmp";
    # Replace HTTP git config with SSH one, if any.
    $gitDir = "$($this._cfgDir)\.git";
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $gitDir;
    Move-Item -Force "$($this._cfgDir).tmp\*" "$($this._cfgDir)";
    Remove-Item "$($this._cfgDir).tmp";
  }


  _generateSshKey() {
    if ($this._isTest) { return; }
    if (Test-Path -Path .ssh\id_rsa) { return; }
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
    $args.Value = '600';
    New-ItemProperty @args;

    # Less is faster
    $args.Name = 'AutoRepeatRate';
    $args.Value = '30';
    New-ItemProperty @args;

    # Milliseconds to supres bounce (with 30ms it RARELY bounces).
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


  _setTouchpadOptions() {
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
    if ($this._isTest) { return; }
    $pass = Read-Host -AsSecureString -Prompt "Enter password"

    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass);
    $str = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr);
    $this._pass = $str;

    $db = "$($this._cfgDir)\passwords.kdbx";
    $verb = "GetEntryString";
    $cmd = "kpscript $db -c:$verb -pw:$($this._pass) -ref-Title:github";
    $ret = cmd /c "$cmd -Field:UserName";
    if ($LASTEXITCODE -ne 0) { throw "Failed" }
    $this._github.user = $ret[2];
    $ret = cmd /c "$cmd -Field:Password";
    if ($LASTEXITCODE -ne 0) { throw "Failed" }
    $this._github.pass = $ret[2];
  }


  _installScoop() {
    if ($this._isTest) { return; }
    if ($this._hasCli("scoop")) { return; }
    $web = New-Object Net.WebClient;
    Invoke-Expression $web.DownloadString('https://get.scoop.sh');
    if (-not $?) { throw "Failed"; }
  }


  _patchScoopBucket() {
    $bucketPath = "$($env:USERPROFILE)\scoop\apps\scoop\current\bucket";
    $filePath = "$bucketPath\7zip.json";
    $manifest = Get-Content $filePath | ConvertFrom-Json;
    $ROOT = "https://datapacket.dl.sourceforge.net/project/sevenzip/7-Zip";
    $URL32 = "$ROOT/18.06/7z1806.msi";
    $H32 = "E1E509FB1FC6C7B7C2F55B1831454084541EE0A6C0A3F67730CDC4CA6BDD443B";
    $manifest.architecture."32bit".url = $URL32;
    $manifest.architecture."32bit".hash = $H32;
    $URL64 = "$ROOT/18.06/7z1806-x64.msi";
    $H64 = "F00E1588ED54DDF633D8652EB89D0A8F95BD80CCCFC3EED362D81927BEC05AA5";
    $manifest.architecture."64bit".url = $URL64;
    $manifest.architecture."64bit".hash = $H64;
    $manifest | ConvertTo-Json > $filePath;
  }


  _patchExtrasBucket() {
    $bucketPath = "$($env:USERPROFILE)\scoop\buckets\extras";
    $filePath = "$bucketPath\telegram.json";
    $manifest = Get-Content $filePath | ConvertFrom-Json;
    $ROOT = "https://github.com/telegramdesktop/tdesktop/releases/download";
    $URL = "$ROOT/v1.5.4/tportable.1.5.4.zip";
    $H = "1BEFF93C0962F393751453E6B4C17F450FBE31D28808756E5B9761B26F1C3EA3";
    $manifest.url = $URL;
    $manifest.hash = $H;
    $manifest | ConvertTo-Json > $filePath;
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
    & git config --global user.email "grigory.v.p@gmail.com";
  }


  _addScoopBuckets() {
    if ($this._isTest) { return; }
    # Required to install autohotkey
    if (-not @(scoop bucket list).Contains("extras")) {
      scoop bucket add extras;
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    # Required to install DejaVu Sans Mono
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
    # Required to install smplayer
    if (-not @(scoop bucket list).Contains("jfut")) {
      $uri = "https://github.com/jfut/scoop-jfut";
      scoop bucket add jfut $uri;
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
  }


  _uploadSshKey() {
    if ($this._isTest) { return; }
    $marker = ".uploaded_to_github";
    if (Test-Path -Path .ssh\$marker) { return; }

    $pair = "$($this._github.user):$($this._github.pass)";
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair);
    $creds = [System.Convert]::ToBase64String($bytes)
    $headers = @{Authorization = "Basic $creds";}
    $body = ConvertTo-Json @{
      title = "box key $(Get-Date)";
      key = (Get-Content ".ssh/id_rsa.pub" | Out-String);
    }
    $url = "https://api.github.com/user/keys"
    if (-not $this._isTest) {
      try {
        Invoke-WebRequest -Method 'POST' -Headers $headers -Body $body $url;
        New-Item -path .ssh -Name $marker -ItemType File | Out-Null;
      }
      catch {
        if ($_.Exception.Response.StatusCode -eq 422) {
          Write-Host "SSH key already added to GitHub";
          New-Item -path .ssh -Name $marker -ItemType File | Out-Null;
        }
        else {
          throw "Failed";
        }
      }
    }
  }


  _prompt($msg) {
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
      ArgumentList = "$($this._cfgDir)\keyboard.ahk"
      WindowStyle = 'Hidden'
      Verb = 'RunAs'
    };
    Start-Process @args;
  }


  _startKeepass() {
    if ($this._isTest) { return; }
    if (Get-Process "KeePass" -ErrorAction SilentlyContinue) { return; }
    Start-Process  keepass.exe  -WindowStyle Hidden;
  }


  _registerAutohotkeyStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path "$startDir\autohotkey.bat") { return; }
    $content = 'pwsh -Command Start-Process autohotkey.exe';
    $content += ' -ArgumentList "' + $this._cfgDir + '\keyboard.ahk"';
    $content += ' -WindowStyle Hidden -Verb RunAs';
    New-Item `
      -path $startDir `
      -Name "autohotkey.bat" `
      -Value "$content" `
      -ItemType File | Out-Null;
  }


  _registerKeepassStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path -Path "$startDir\keepass.bat") { return; }
    $content = 'pwsh -Command Start-Process keepass.exe';
    $content += ' -WindowStyle Hidden';
    New-Item `
      -path $startDir `
      -Name "keepass.bat" `
      -Value "$content" `
      -ItemType File | Out-Null;
  }


  _installFonts() {
    $fileName = "DejaVu Sans Mono Nerd Font Complete Windows Compatible.ttf";
    if (Test-Path -Path "$env:windir\Fonts\$fileName") { return; }
    $appName = "DejaVuSansMono-NF";
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
    $dstDir = "$($env:USERPROFILE)\.xi";
    if (Test-Path -Path $dstDir) { return; }
    $uri = "git@github.com:grigoryvp/xi.git";
    & git clone $uri $dstDir;
    if ($LASTEXITCODE -ne 0) { throw "Failed" }
  }


  _configureVscode() {
    $dstDir = "$($env:APPDATA)\Code\User";
    if (-not (Test-Path -Path $dstDir)) {
      # Not created during install, only on first UI start.
      New-Item -Path $dstDir -ItemType Directory | Out-Null;
    }

    $srcPath = "$($this._cfgDir)\vscode_settings.json";
    $dstPath = "$dstDir\settings.json";
    Copy-Item -Path $srcPath -Destination $dstPath -Force;

    $srcPath = "$($this._cfgDir)\vscode_keybindings.json";
    $dstPath = "$dstDir\keybindings.json";
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

    $docCfgDir = "$($env:USERPROFILE)\Documents\.vscode";
    if (-not (Test-Path -Path $docCfgDir)) {
      New-Item -Path $docCfgDir -ItemType Directory | Out-Null;
    }

    $content = @'
      {
        "files.exclude": {
          "My Music/": true,
          "My Pictures": true,
          "My Videos": true,
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
}

# Stop on unhandled exceptions.
$ErrorActionPreference = "Stop";
$app = [App]::new($args);
$app.configure();
