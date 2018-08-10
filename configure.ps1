cd $env:USERPROFILE

Write-Host "Configuring power options..."
powercfg -change -monitor-timeout-ac 120
powercfg -change -monitor-timeout-dc 120
powercfg -change -disk-timeout-ac 0
powercfg -change -disk-timeout-dc 0
powercfg -change -standby-timeout-ac 0
powercfg -change -standby-timeout-dc 0
powercfg -change -hibernate-timeout-ac 0
powercfg -change -hibernate-timeout-dc 0

if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
  Invoke-Expression (New-Object Net.WebClient).DownloadString('https://get.scoop.sh')
  if (!$?) { throw "Failed" }
}

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
  # Required for buckets
  scoop uninstall git
  scoop install git
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
}

if (!(Get-Command autohotkey -ErrorAction SilentlyContinue)) {
  # Required to install autohotkey
  scoop bucket add extras
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
  scoop uninstall autohotkey
  scoop install autohotkey
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
}

if (!(Get-Command keepass -ErrorAction SilentlyContinue)) {
  # Required to install kpscript
  scoop bucket add kpscript https://github.com/grigoryvp/scoop-kpscript.git
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
  scoop uninstall keepass
  scoop install keepass
  scoop uninstall kpscript
  scoop install kpscript
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
}

if (!(Get-Command sudo -ErrorAction SilentlyContinue)) {
  # Required for auto-start elevated autohotkey installed via scoop
  scoop uninstall sudo
  scoop install sudo
  if ($LASTEXITCODE -ne 0) { throw "Failed" }
}

if (!(Test-Path .ssh\id_rsa)) {
  if (!(Test-Path .ssh)) {
    New-Item -Path .ssh -ItemType Directory
  }
  Start-Process ssh-keygen -ArgumentList '-N "" -f .ssh/id_rsa' -Wait
}

# Modify keyboard
if (!(Test-Path keyboard.ahk)) {
  Write-Output "Downloading keyboard script"
  $uri = 'https://raw.githubusercontent.com/grigoryvp/my-win-box-cfg/master/keyboard.ahk'
  Invoke-WebRequest -OutFile keyboard.ahk -Uri $uri
  if (!$?) { throw "Failed" }
}

if (!(Get-Process "AutoHotkey" -ErrorAction SilentlyContinue)) {
  Write-Host -NoNewLine "Press any key to elevate the keyboard script..."
  [System.Console]::ReadKey("NoEcho,IncludeKeyDown") | Out-Null
  Write-Host ""
  sudo autohotkey keyboard.ahk
}

$startDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
if (!(Test-Path "$startDir\startup.bat")) {
  $content = 'sudo autohotkey "%USERPROFILE%\keyboard.ahk"'
  New-Item -path $startDir -Name "startup.bat" -Value "$content" -ItemType File
}
