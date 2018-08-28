class App {
  $_isTest = $false;
  $_pass = $null;
  $_cfgDir = $null;
  $_github = @{
    user = "foo";
    pass = "bar";
  };


  App($argList) {
    $this._isTest = ($argList.Contains("--test"));
  }


  configure() {
    Push-Location;

    # Required by Posh-Git, sudo etc.
    if ((Get-ExecutionPolicy -Scope CurrentUser) -ne "Unrestricted") {
      Set-ExecutionPolicy Unrestricted -Scope CurrentUser;
    }
    Set-Location $env:USERPROFILE

    # Version-controlled dir with scripts, powershell config, passwords etc.
    $this._cfgDir = "$($env:USERPROFILE)\Documents\PowerShell";
    if (!(Test-Path $this._cfgDir)) {
      New-Item -Path $this._cfgDir -ItemType Directory;
    }

    $this._installPowershellModule("posh-git");
    $this._generateSshKey();
    $this._setPowerOptions();
    $this._installScoop();
    $this._installGit();
    $this._addScoopBuckets();
    $this._getFilesNoClone();
    $this._installApp("autohotkey");
    $this._installApp("keepass");
    $this._copyToAppDir("KeePass.config.xml", "keepass");
    $this._installApp("kpscript");
    $this._installApp("doublecmd");
    # 'procexp' etc
    $this._installApp("sysinternals", "procexp");
    $this._registerAutohotkeyStartup();
    $this._registerKeepassStartup();

    # Interactive.
    if (!(Test-Path .ssh\.uploaded_to_github)) {
      $this._askForGithubCredentials();
    }
    # Interactive.
    $this._startAutohotkey();
    $this._startKeepass();

    $this._uploadSshKey();

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


  _installApp($name) {
    $this._installApp($name, $name);
  }


  _installApp($name, $testCmd) {
    if ($this._isTest) { return; }
    if ($this._hasCli($testCmd)) { return; }
    scoop uninstall $name;
    scoop install $name;
    if ($LASTEXITCODE -ne 0) { throw "Failed" }
  }


  _installPowershellModule($name) {
    if ($this._isTest) { return; }
    if (Get-InstalledModule | ? Name -eq $name) { return; }
    PowerShellGet\Install-Module `
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


  # Get minimum amount of files from repo without cloning it (GitHub do not
  # have SSH keys from this box yet for a proper clone).
  _getFilesNoClone() {
    if ($this._isTest) { return; }
    $repo = "https://raw.githubusercontent.com/grigoryvp/my-win-box-cfg";

    if (!(Test-Path "$($this._cfgDir)\passwords.kdbx")) {
      Write-Output "Downloading passwords storage"
      $uri = "$($repo)/master/passwords.kdbx"
      Invoke-WebRequest -OutFile "$($this._cfgDir)\passwords.kdbx" $uri
      if (!$?) { throw "Failed" }
    }

    if (!(Test-Path "$($this._cfgDir)\keyboard.ahk")) {
      Write-Output "Downloading keyboard script"
      $uri = "$($repo)/master/keyboard.ahk"
      Invoke-WebRequest -OutFile "$($this._cfgDir)\keyboard.ahk" $uri
      if (!$?) { throw "Failed" }
    }
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

  
  _startAutohotkey() {
    if ($this._isTest) { return; }
    if (Get-Process "AutoHotkey" -ErrorAction SilentlyContinue) { return; }
    Write-Host -NoNewLine "Press any key to elevate the keyboard script..."
    [System.Console]::ReadKey("NoEcho,IncludeKeyDown") | Out-Null
    Write-Host ""
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
    $content += ' -WindowStyle Hidden -Verb RunAs';
    New-Item `
      -path $startDir `
      -Name "keepass.bat" `
      -Value "$content" `
      -ItemType File;
  }
}

$app = [App]::new($args);
$app.configure();
