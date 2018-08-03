iex (new-object net.webclient).downloadstring('https://get.scoop.sh')
scoop install git
scoop update
cd $env:USERPROFILE
& ssh-keygen -N '""' -f .ssh/id_rsa

# Install AutoHotkey
$file = ".\ahk-install.exe"
echo "Downloading AutoHotkey"
curl -OutFile $file -Uri https://autohotkey.com/download/ahk-install.exe
& $file /S
rm $file

# Modify keyboard
echo "Downloading keyboard script"
curl -OutFile keyboard.ahk -Uri https://raw.githubusercontent.com/grigoryvp/my-win-box-cfg/master/keyboard.ahk
start .\keyboard.ahk
