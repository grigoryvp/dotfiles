class App {
  $_isTest = $false;
  $_pass = $null;
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
    Set-ExecutionPolicy Unrestricted -Scope CurrentUser;
    Set-Location $env:USERPROFILE

    # Version-controlled dir with scripts, powershell config, passwords etc.
    $configDir = "$($env:USERPROFILE)\Documents";
    if (!(Test-Path $configDir)) {
      New-Item -Path $configDir -ItemType Directory;
    }

    $this._installPowershellModule("posh-git");
    $this._generateSshKey();
    $this._setPowerOptions();
    $this._installScoop();
    $this._installGit();
    $this._addScoopBuckets();
    $this._getFilesNoClone($configDir);
    $this._installApp("autohotkey");
    $this._installApp("keepass");
    $this._installApp("kpscript");
    $this._installApp("doublecmd");
    $this._registerAutohotkeyStartup();

    # Interactive.
    $this._askForGithubCredentials();
    # Interactive.
    $this._startAutohotkey();

    $this._uploadSshKey();

    Pop-Location;
    if ($this._isTest) {
      Write-Host "Test complete";
    }
  }


  [Boolean] _hasCli($name) {
    Get-Command $name -ErrorAction SilentlyContinue;
    return $?;
  }


  _installApp($name) {
    if ($this._isTest) { return; }
    if ($this._hasCli($name)) { return; }
    scoop uninstall $name;
    scoop install $name;
    if ($LASTEXITCODE -ne 0) { throw "Failed" }
  }


  _installPowershellModule($name) {
    if ($this._isTest) { return; }
      PowerShellGet\Install-Module `
      $name `
      -Scope CurrentUser `
      -AllowPrerelease -Force;
    if (!$?) { throw "Failed" }
  }


  # Get minimum amount of files from repo without cloning it (GitHub do not
  # have SSH keys from this box yet for a proper clone).
  _getFilesNoClone($configDir) {
    if ($this._isTest) { return; }
    $repo = "https://raw.githubusercontent.com/grigoryvp/my-win-box-cfg";

    if (!(Test-Path "$($configDir)\passwords.kdbx")) {
      Write-Output "Downloading passwords storage"
      $uri = "$($repo)/master/passwords.kdbx"
      Invoke-WebRequest -OutFile "$($configDir)\passwords.kdbx" $uri
      if (!$?) { throw "Failed" }
    }

    if (!(Test-Path "$($configDir)\keyboard.ahk")) {
      Write-Output "Downloading keyboard script"
      $uri = "$($repo)/master/keyboard.ahk"
      Invoke-WebRequest -OutFile "$($configDir)\keyboard.ahk" $uri
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
    Write-Host "Configuring power options..."
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

    $db = "passwords.kdbx";
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
    scoop bucket add extras;
    if ($LASTEXITCODE -ne 0) { throw "Failed" }
    # Required to install kpscript
    scoop bucket add kpscript https://github.com/grigoryvp/scoop-kpscript.git
    if ($LASTEXITCODE -ne 0) { throw "Failed" }
  }


  _uploadSshKey() {
    if ($this._isTest) { return; }
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
      }
      catch {
        if ($_.Exception.Response.StatusCode -eq 422) {
          Write-Host "SSH key already added to GitHub";
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
      -ArgumentList 'keyboard.ahk' `
      -WindowStyle Hidden `
      -Verb RunAs;
  }


  _registerAutohotkeyStartup() {
    if ($this._isTest) { return; }
    $startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path "$startDir\startup.bat") { return; }
    $content = 'pwsh -Command Start-Process autohotkey.exe';
    $content += ' -ArgumentList "%USERPROFILE%\keyboard.ahk"';
    $content += ' -WindowStyle Hidden -Verb RunAs';
    New-Item `
      -path $startDir `
      -Name "startup.bat" `
      -Value "$content" `
      -ItemType File;
  }
}

$app = [App]::new($args);
$app.configure();
