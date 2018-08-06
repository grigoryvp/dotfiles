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
  & ssh-keygen -N '""' -f .ssh/id_rsa
}

# Install AutoHotkey
$file = ".\ahk-install.exe"
echo "Downloading AutoHotkey"
curl -OutFile $file -Uri https://autohotkey.com/download/ahk-install.exe
& $file /S
echo "Waiting for installation to complete"
Start-Sleep 60
rm $file

# Modify keyboard
echo "Downloading keyboard script"
curl -OutFile keyboard.ahk -Uri https://raw.githubusercontent.com/grigoryvp/my-win-box-cfg/master/keyboard.ahk
start .\keyboard.ahk
