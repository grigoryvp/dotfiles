class App {
  $_isTest = $false;
  $_isFull = $false;
  $_isPublic = $false;
  $_pass = $null;
  $_cfgDir = $null;
  $_github = @{
    user = "foo";
    pass = "bar";
  };


  App($argList) {
    $this._isTest = ($argList.Contains("--test"));
    $this._isFull = ($argList.Contains("--full"));
    # Do not touch private info like passwords, personal kb etc.
    $this._isPublic = ($argList.Contains("--public"));
  }


  configure() {
    Push-Location;

    # Required by Posh-Git, sudo etc.
    if ((Get-ExecutionPolicy -Scope CurrentUser) -ne "Unrestricted") {
      # scoop shims like sudo are executed via powershell.exe and it seems
      # that pwsh.exe and powershell.exe have separated execution policy
      # config
      powershell.exe `
        -Command Set-ExecutionPolicy Unrestricted `
        -Scope CurrentUser;
    }

    Set-Location $env:USERPROFILE

    # Version-controlled dir with scripts, powershell config, passwords etc.
    $this._cfgDir = "$($env:USERPROFILE)\Documents\PowerShell";
    if (!(Test-Path $this._cfgDir)) {
      New-Item -Path $this._cfgDir -ItemType Directory;
    }

    $this._installPowershellModule("posh-git");
    $this._installPowershellModule("WindowsCompatibility");
    $this._generateSshKey();
    $this._setPowerOptions();
    $this._installScoop();
    # Some URL's in scoop bucket are blocked in some countries.
    $this._patchScoopBucket();
    $this._installGit();
    $this._addScoopBuckets();
    # Clone without keys via HTTPS
    $this._getFilesFromGit();
    $this._installApp("sudo");
    $this._installApp("autohotkey");
    $this._installApp("keepass");
    $this._installApp("kpscript");
    $this._installApp("vscode");
    $this._installApp("doublecmd");
    $this._registerAutohotkeyStartup();
    $this._registerKeepassStartup();

    # Interactive.
    if (!(Test-Path .ssh\.uploaded_to_github)) {
      if (!$this._isPublic) {
        $this._askForGithubCredentials();
      }
    }
    # Interactive.
    $this._startAutohotkey();
    # Interactive.
    $this._installFonts();

    if (!$this._isPublic) {
      $this._uploadSshKey();
    }

    if (!$this._isPublic) {
      # Re-clone with SSH keys
      $this._getFilesFromGit();
    }
    $this._copyToAppDir("KeePass.config.xml", "keepass");
    $this._getXi();
    $this._startKeepass();

    # Optional installs
    if ($this._isFull) {
      # Need to restart terminal in order to apply env variables.
      $this._installApp("nodejs");
      $this._installApp("chromium");
      # 'procexp' etc
      $this._installApp("sysinternals");
      $this._installApp("foxit-reader");
      $this._installApp("obs-studio");
      $this._installApp("rufus");
      $this._installApp("telegram");
      if (!$this._hasCli("g")) {
        & npm i -g git-alias;
      }
      if (!$this._hasApp("openvpn")) {
        $this._prompt("Press any key to elevate OpenVpn install...");
        $this._installApp("openvpn");
      }
      if (!$this._hasApp("thunderbird")) {
        $this._prompt("Press any key to elevate Thunderbird install...");
        $this._installApp("thunderbird");
      }
    }

    Pop-Location;
    if ($this._isTest) {
      Write-Host "Test complete";
    }
    else {
      Write-Host "Config complete";
    }
  }


  [Boolean] _hasCli($name) {
    Get-Command $name -ErrorAction SilentlyContinue;
    return $?;
  }


  [Boolean] _hasApp($appName) {
    $res = & scoop info $appName;
    if ($LASTEXITCODE -ne 0) { return $false; }
    return !($res | Out-String).Contains("Installed: No");
  }


  _installApp($name) {
    if ($this._isTest) { return; }
    if ($this._hasApp($name)) { return; }
    scoop uninstall $name;
    scoop install $name;
    if ($LASTEXITCODE -ne 0) { throw "Failed" }
  }


  _installPowershellModule($name) {
    if ($this._isTest) { return; }
    if (Get-InstalledModule | ? Name -eq $name) { return; }
    Install-Module `
      $name `
      -Scope CurrentUser `
      -AllowPrerelease -Force;
    if (!$?) { throw "Failed" }
  }


  _copyToAppDir($fileName, $appName) {
    $srcPath = "$($this._cfgDir)\$fileName";
    $dstPath = "$($env:USERPROFILE)\scoop\apps\$appName\current\";
    Copy-Item $srcPath -Destination $dstPath -Force;
  }


  _getFilesFromGit() {
    $gitCfgFile = "$($this._cfgDir)\.git\config";
    if (Test-Path $gitCfgFile) {
      $gitCfg = Get-Content $gitCfgFile | Out-String;
      # Already cloned with SSH?
      if ($gitCfg.Contains("git@github.com")) { return; }
    }

    # Have keys to clone with SSH?
    if (Test-Path .ssh\.uploaded_to_github) {
      $uri = "git@github.com:grigoryvp/my-win-box-cfg.git";
    }
    else {
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
    if (Test-Path .ssh\id_rsa) { return; }
    if (!(Test-Path .ssh)) {
      New-Item -Path .ssh -ItemType Directory;
    }
    Start-Process ssh-keygen -ArgumentList '-N "" -f .ssh/id_rsa' -Wait;
  }


  _setPowerOptions() {
    if ($this._isTest) { return; }
    powercfg -change -monitor-timeout-ac 120
    powercfg -change -monitor-timeout-dc 120
    powercfg -change -disk-timeout-ac 0
    powercfg -change -disk-timeout-dc 0
    powercfg -change -standby-timeout-ac 0
    powercfg -change -standby-timeout-dc 0
    powercfg -change -hibernate-timeout-ac 0
    powercfg -change -hibernate-timeout-dc 0
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
    if (!$?) { throw "Failed"; }
  }


  _patchScoopBucket() {
    $bucketPath = "$($env:USERPROFILE)\scoop\apps\scoop\current\bucket";
    $filePath = "$bucketPath\7zip.json";
    $manifest = Get-Content $filePath | ConvertFrom-Json;
    $ROOT = "https://datapacket.dl.sourceforge.net/project/sevenzip/7-Zip";
    $URL32 = "$ROOT/18.05/7z1805.msi";
    $H32 = "C554238BEE18A03D736525E06D9258C9ECF7F64EAD7C6B0D1EB04DB2C0DE30D0";
    $manifest.architecture."32bit".url = $URL32;
    $manifest.architecture."32bit".hash = $H32;
    $URL64 = "$ROOT/18.05/7z1805-x64.msi";
    $H64 = "898C1CA0015183FE2BA7D55CACF0A1DEA35E873BF3F8090F362A6288C6EF08D7";
    $manifest.architecture."64bit".url = $URL64;
    $manifest.architecture."64bit".hash = $H64;
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
    if (!@(scoop bucket list).Contains("extras")) {
      scoop bucket add extras;
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    # Required to install DejaVu Sans Mono
    if (!@(scoop bucket list).Contains("nerd-fonts")) {
      scoop bucket add nerd-fonts;
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
    # Required to install kpscript
    if (!@(scoop bucket list).Contains("kpscript")) {
      $uri = "https://github.com/grigoryvp/scoop-kpscript.git";
      scoop bucket add kpscript $uri;
      if ($LASTEXITCODE -ne 0) { throw "Failed" }
    }
  }


  _uploadSshKey() {
    if ($this._isTest) { return; }
    $marker = ".uploaded_to_github";
    if (Test-Path .ssh\$marker) { return; }

    $pair = "$($this._github.user):$($this._github.pass)";
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair);
    $creds = [System.Convert]::ToBase64String($bytes)
    $headers = @{Authorization = "Basic $creds";}
    $body = ConvertTo-Json @{
      title = "box key $(Get-Date)";
      key = (Get-Content ".ssh/id_rsa.pub" | Out-String);
    }
    $url = "https://api.github.com/user/keys"
    if (!$this._isTest) {
      try {
        Invoke-WebRequest -Method 'POST' -Headers $headers -Body $body $url;
        New-Item -path .ssh -Name $marker -ItemType File;
      }
      catch {
        if ($_.Exception.Response.StatusCode -eq 422) {
          Write-Host "SSH key already added to GitHub";
          New-Item -path .ssh -Name $marker -ItemType File;
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
    Start-Process `
      autohotkey.exe `
      -ArgumentList "$($this._cfgDir)\keyboard.ahk" `
      -WindowStyle Hidden `
      -Verb RunAs;
  }


  _startKeepass() {
    if ($this._isTest) { return; }
    if (Get-Process "KeePass" -ErrorAction SilentlyContinue) { return; }
    Start-Process  keepass.exe  -WindowStyle Hidden;
  }


  _registerAutohotkeyStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path "$startDir\autohotkey.bat") { return; }
    $content = 'pwsh -Command Start-Process autohotkey.exe';
    $content += ' -ArgumentList "' + $this._cfgDir + '\keyboard.ahk"';
    $content += ' -WindowStyle Hidden -Verb RunAs';
    New-Item `
      -path $startDir `
      -Name "autohotkey.bat" `
      -Value "$content" `
      -ItemType File;
  }


  _registerKeepassStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path "$startDir\keepass.bat") { return; }
    $content = 'pwsh -Command Start-Process keepass.exe';
    $content += ' -WindowStyle Hidden';
    New-Item `
      -path $startDir `
      -Name "keepass.bat" `
      -Value "$content" `
      -ItemType File;
  }


  _installFonts() {
    $fileName = "DejaVu Sans Mono Nerd Font Complete Windows Compatible.ttf";
    if (Test-Path "$env:windir\Fonts\$fileName") { return; }
    & scoop uninstall DejaVuSansMono-NF;
    Start-Process scoop.cmd `
      -Wait `
      -Verb RunAs `
      -ArgumentList "install DejaVuSansMono-NF";
  }


  _getXi() {
    $dstDir = "$($this._cfgDir)\xi";
    if (Test-Path $dstDir) { return; }
    $uri = "git@github.com:grigoryvp/xi.git";
    & git clone $uri $dstDir;
    if ($LASTEXITCODE -ne 0) { throw "Failed" }
  }
}

$app = [App]::new($args);
$app.configure();
