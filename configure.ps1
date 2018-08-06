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
  & ssh-keygen -N '""' -f .ssh/id_rsa | out-null
}

# Install AutoHotkey
$file = ".\ahk-install.exe"
echo "Downloading AutoHotkey"
Invoke-WebRequest -OutFile $file -Uri https://autohotkey.com/download/ahk-install.exe
& $file /S | out-null
rm $file

# Modify keyboard
echo "Downloading keyboard script"
Invoke-WebRequest -OutFile keyboard.ahk -Uri https://raw.githubusercontent.com/grigoryvp/my-win-box-cfg/master/keyboard.ahk
Start-Process .\keyboard.ahk
