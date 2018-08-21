$app = @{
  isTest = ($args.Contains("--test"));
  pass = $null;
};

$app.github = @{
  user = "foo";
  pass = "bar";
};

cd $env:USERPROFILE

if (!$app.isTest) {
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

if (!$app.isTest -and !(Get-Command scoop -ErrorAction SilentlyContinue)) {
  Invoke-Expression (New-Object Net.WebClient).DownloadString('https://get.scoop.sh')
  if (!$?) { throw "Failed" }
}

if (!$app.isTest -and !(Get-Command git -ErrorAction SilentlyContinue)) {
  # Required for buckets
  scoop uninstall git
  scoop install git
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
  & git config --global core.autocrlf input
  & git config --global user.name "Girogry Petrov"
  & git config --global user.email "grigory.v.p@gmail.com"
}

if (!$app.isTest -and !(Get-Command autohotkey -ErrorAction SilentlyContinue)) {
  # Required to install autohotkey
  scoop bucket add extras
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
  scoop uninstall autohotkey
  scoop install autohotkey
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
}

if (!$app.isTest -and !(Get-Command keepass -ErrorAction SilentlyContinue)) {
  # Required to install kpscript
  scoop bucket add kpscript https://github.com/grigoryvp/scoop-kpscript.git
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
  scoop uninstall keepass
  scoop install keepass
  scoop uninstall kpscript
  scoop install kpscript
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
}

if (!$app.isTest -and !(Get-Command doublecmd -ErrorAction SilentlyContinue)) {
  scoop uninstall doublecmd
  scoop install doublecmd
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
}

if (!$app.isTest -and !(Test-Path .ssh\id_rsa)) {
  if (!(Test-Path .ssh)) {
    New-Item -Path .ssh -ItemType Directory
  }
  Start-Process ssh-keygen -ArgumentList '-N "" -f .ssh/id_rsa' -Wait
}

if (!$app.isTest -and !(Test-Path passwords.kdbx)) {
  Write-Output "Downloading passwords storage"
  $uri = 'https://raw.githubusercontent.com/grigoryvp/my-win-box-cfg/master/passwords.kdbx'
  Invoke-WebRequest -OutFile passwords.kdbx $uri
  if (!$?) { throw "Failed" }
}

if (!$app.isTest) {
  $pass = Read-Host -AsSecureString -Prompt "Enter password"

  $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass);
  $str = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr);
  $app.pass = $str;

  $db = "passwords.kdbx";
  $verb = "GetEntryString";
  $cmd = "kpscript $db -c:$verb -pw:$($app.pass) -ref-Title:github";
  $ret = cmd /c "$cmd -Field:UserName";
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
  $app.github.user = $ret[2];
  $ret = cmd /c "$cmd -Field:Password";
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
  $app.github.pass = $ret[2];
}
else {
  $app.pass = "keypass";
  $app.github.user = "ghuser";
  $app.github.pass = "ghpass";
}

function uploadSshKey() {
  $pair = "$($app.github.user):$($app.github.pass)";
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair);
  $creds = [System.Convert]::ToBase64String($bytes)
  $headers = @{Authorization = "Basic $creds";}
  $body = ConvertTo-Json @{
    title = "box key $(Get-Date)";
    key = (Get-Content ".ssh/id_rsa.pub" | Out-String);
  }
  $url = "https://api.github.com/user/keys"
  if (!$app.isTest) {
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

if (!$app.isTest -and !(Test-Path keyboard.ahk)) {
  Write-Output "Downloading keyboard script"
  $uri = 'https://raw.githubusercontent.com/grigoryvp/my-win-box-cfg/master/keyboard.ahk'
  Invoke-WebRequest -OutFile keyboard.ahk $uri
  if (!$?) { throw "Failed" }
}

if (!$app.isTest -and !(Get-Process "AutoHotkey" -ErrorAction SilentlyContinue)) {
  Write-Host -NoNewLine "Press any key to elevate the keyboard script..."
  [System.Console]::ReadKey("NoEcho,IncludeKeyDown") | Out-Null
  Write-Host ""
  Start-Process autohotkey.exe -ArgumentList 'keyboard.ahk' -WindowStyle Hidden -Verb RunAs
}

$startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
if (!$app.isTest -and !(Test-Path "$startDir\startup.bat")) {
  $content = 'pwsh -Command Start-Process autohotkey.exe -ArgumentList "%USERPROFILE%\keyboard.ahk" -WindowStyle Hidden -Verb RunAs'
  New-Item -path $startDir -Name "startup.bat" -Value "$content" -ItemType File
}

if ($app.isTest) {
  Write-Host "Test complete";
}
