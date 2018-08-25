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

    # Required by Posh-Git, sudo etc
    Set-ExecutionPolicy Unrestricted -Scope CurrentUser;
    Set-Location $env:USERPROFILE
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
}

$app = [App]::new($args);
$app.configure();


if (!$app._isTest -and !(Get-Command scoop -ErrorAction SilentlyContinue)) {
  Invoke-Expression (New-Object Net.WebClient).DownloadString('https://get.scoop.sh')
  if (!$?) { throw "Failed" }
}

if (!$app._isTest -and !(Get-Command git -ErrorAction SilentlyContinue)) {
  # Required for buckets
  scoop uninstall git
  # Auto-installed with git
  scoop uninstall 7zip
  scoop install git
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
  & git config --global core.autocrlf input
  & git config --global user.name "Girogry Petrov"
  & git config --global user.email "grigory.v.p@gmail.com"
}

if (!$app._isTest -and !(Get-Command autohotkey -ErrorAction SilentlyContinue)) {
  # Required to install autohotkey
  scoop bucket add extras
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
  scoop uninstall autohotkey
  scoop install autohotkey
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
}

if (!$app._isTest -and !(Get-Command keepass -ErrorAction SilentlyContinue)) {
  # Required to install kpscript
  scoop bucket add kpscript https://github.com/grigoryvp/scoop-kpscript.git
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
  scoop uninstall keepass
  scoop install keepass
  scoop uninstall kpscript
  scoop install kpscript
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
}

if (!$app._isTest -and !(Get-Command doublecmd -ErrorAction SilentlyContinue)) {
  scoop uninstall doublecmd
  scoop install doublecmd
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
}

if (!$app._isTest -and !(Test-Path .ssh\id_rsa)) {
  if (!(Test-Path .ssh)) {
    New-Item -Path .ssh -ItemType Directory
  }
  Start-Process ssh-keygen -ArgumentList '-N "" -f .ssh/id_rsa' -Wait
}

if (!$app._isTest -and !(Test-Path passwords.kdbx)) {
  Write-Output "Downloading passwords storage"
  $uri = 'https://raw.githubusercontent.com/grigoryvp/my-win-box-cfg/master/passwords.kdbx'
  Invoke-WebRequest -OutFile passwords.kdbx $uri
  if (!$?) { throw "Failed" }
}

if (!$app._isTest) {
  PowerShellGet\Install-Module `
    posh-git `
    -Scope CurrentUser `
    -AllowPrerelease -Force
  if (!$?) { throw "Failed" }
}

if (!$app._isTest) {
  $pass = Read-Host -AsSecureString -Prompt "Enter password"

  $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass);
  $str = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr);
  $app._pass = $str;

  $db = "passwords.kdbx";
  $verb = "GetEntryString";
  $cmd = "kpscript $db -c:$verb -pw:$($app._pass) -ref-Title:github";
  $ret = cmd /c "$cmd -Field:UserName";
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
  $app._github.user = $ret[2];
  $ret = cmd /c "$cmd -Field:Password";
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
  $app._github.pass = $ret[2];
}
else {
  $app._pass = "keypass";
  $app._github.user = "ghuser";
  $app._github.pass = "ghpass";
}

function uploadSshKey() {
  $pair = "$($app._github.user):$($app._github.pass)";
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair);
  $creds = [System.Convert]::ToBase64String($bytes)
  $headers = @{Authorization = "Basic $creds";}
  $body = ConvertTo-Json @{
    title = "box key $(Get-Date)";
    key = (Get-Content ".ssh/id_rsa.pub" | Out-String);
  }
  $url = "https://api.github.com/user/keys"
  if (!$app._isTest) {
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
uploadSshKey;

if (!$app._isTest -and !(Test-Path keyboard.ahk)) {
  Write-Output "Downloading keyboard script"
  $uri = 'https://raw.githubusercontent.com/grigoryvp/my-win-box-cfg/master/keyboard.ahk'
  Invoke-WebRequest -OutFile keyboard.ahk $uri
  if (!$?) { throw "Failed" }
}

if (!$app._isTest -and !(Get-Process "AutoHotkey" -ErrorAction SilentlyContinue)) {
  Write-Host -NoNewLine "Press any key to elevate the keyboard script..."
  [System.Console]::ReadKey("NoEcho,IncludeKeyDown") | Out-Null
  Write-Host ""
  Start-Process autohotkey.exe -ArgumentList 'keyboard.ahk' -WindowStyle Hidden -Verb RunAs
}

$startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
if (!$app._isTest -and !(Test-Path "$startDir\startup.bat")) {
  $content = 'pwsh -Command Start-Process autohotkey.exe -ArgumentList "%USERPROFILE%\keyboard.ahk" -WindowStyle Hidden -Verb RunAs'
  New-Item -path $startDir -Name "startup.bat" -Value "$content" -ItemType File
}

if ($app._isTest) {
  Write-Host "Test complete";
}

Pop-Location;
