function isInstalled($appname) {
  $keyList = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall")
  foreach($key in $keyList) {
    $appList = get-childItem $key | where-object {
      $_.getValue("DisplayName") -like "*$appname*"
    }
    if ($appList.length -gt 0) {
      return $true
    }
  }
  return $false
}

cd $env:USERPROFILE

if (!(get-command scoop -errorAction SilentlyContinue)) {
  iex (new-object net.webclient).downloadstring('https://get.scoop.sh')
  scoop install git
  scoop update
}

if (!(test-path .ssh\id_rsa)) {
  if (!(test-path .ssh)) {
    mkdir .ssh
  }
  start-process ssh-keygen -argumentList '-N "" -f .ssh/id_rsa' -wait
}

# Install AutoHotkey
if (!isInstalled("autohotkey")) {
  $file = ".\ahk-install.exe"
  write-output "Downloading AutoHotkey"
  invoke-webRequest -OutFile $file -Uri https://autohotkey.com/download/ahk-install.exe
  start-process $file -argumentList '/S' -verb RunAs -wait
  rm $file
}

# Modify keyboard
write-output "Downloading keyboard script"
Invoke-WebRequest -OutFile keyboard.ahk -Uri https://raw.githubusercontent.com/grigoryvp/my-win-box-cfg/master/keyboard.ahk
Start-Process .\keyboard.ahk
