cd $env:USERPROFILE

if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
  Invoke-Expression (New-Object Net.WebClient).DownloadString('https://get.scoop.sh')
  scoop bucket add extras
}

scoop install autohotkey

if (!(Test-Path .ssh\id_rsa)) {
  if (!(Test-Path .ssh)) {
    New-Item -Path .ssh -ItemType Directory
  }
  Start-Process ssh-keygen -ArgumentList '-N "" -f .ssh/id_rsa' -Wait
}

# Modify keyboard
Write-Output "Downloading keyboard script"
$uri = 'https://raw.githubusercontent.com/grigoryvp/my-win-box-cfg/master/keyboard.ahk'
Invoke-WebRequest -OutFile keyboard.ahk -Uri $uri

Write-Host -NoNewLine "Press any key to elevate the keyboard script..."
[System.Console]::ReadKey()
Start-Process autohotkey.exe -ArgumentList '.\keyboard.ahk' -Verb RunAs -WindowStyle Hidden
