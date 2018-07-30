iex (new-object net.webclient).downloadstring('https://get.scoop.sh')
scoop install git
scoop update
$url = 'https://autohotkey.com/download/ahk-install.exe'
$file = "$env:temp\ahk-install.exe"
$client = (new-object net.webclient)
$client.headers.add('User-Agent', 'curl/7.55.1')
# $client.downloadfile($url, $file)
& $file /S
start keyboard.ahk
