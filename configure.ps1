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
$file = ".\ahk-install.exe"
echo "Downloading AutoHotkey"
Invoke-WebRequest -OutFile $file -Uri https://autohotkey.com/download/ahk-install.exe
start-process $file -argumentList '/S' -verb RunAs -wait
rm $file

# Modify keyboard
echo "Downloading keyboard script"
Invoke-WebRequest -OutFile keyboard.ahk -Uri https://raw.githubusercontent.com/grigoryvp/my-win-box-cfg/master/keyboard.ahk
Start-Process .\keyboard.ahk
