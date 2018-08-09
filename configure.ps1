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
}

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
  # Required for buckets
  scoop install git
}

if (!(Get-Command autohotkey -ErrorAction SilentlyContinue)) {
  # Required to install autohotkey
  scoop bucket add extras
  scoop install autohotkey
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
}

if (!(Get-Process "AutoHotkey" -ErrorAction SilentlyContinue)) {
  Write-Host -NoNewLine "Press any key to elevate the keyboard script..."
  [System.Console]::ReadKey()
  Write-Host ""
  Start-Process autohotkey.exe -ArgumentList '.\keyboard.ahk' -Verb RunAs -WindowStyle Hidden
}
