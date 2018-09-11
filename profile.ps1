# Todo: https://4sysops.com/archives/building-a-web-server-with-powershell/

Import-Module posh-git;

function cdd() { Set-Location ~/Documents; }
function cdc() { Set-Location ~/Documents/PowerShell; }
function cdh() { Set-Location ~; }
function cdx() { Set-Location ~/Documents/PowerShell/xi; }

function gst() {
  $dirNameList = Get-ChildItem -Name -Directory;
  foreach ($dirName in $dirNameList) {
    if (!(Test-Path "$dirName\.git")) {
      Write-Host "not a git repo; " -NoNewline -ForegroundColor DarkCyan;
      Write-Host $dirName;
      continue;
    }
    Set-Location $dirName;
    $ret = & git status;
    $UP_MARKER = "Your branch is up to date with";
    $CLEAN_MARKER = "nothing to commit, working tree clean";
    if ($ret[1].Contains($UP_MARKER)) {
      Write-Host "up to date; " -NoNewline;
    }
    else {
      Write-Host "out of sync" -NoNewline -ForegroundColor Green;
      Write-Host "; " -NoNewline;
    }
    if ($ret[3].Contains($CLEAN_MARKER) -or $ret[4].Contains($CLEAN_MARKER)) {
      Write-Host "clean; " -NoNewline;
    }
    else {
      Write-Host "working tree changes" -NoNewline -ForegroundColor Red;
      Write-Host "; " -NoNewline;
    }
    Write-Host $dirName;
    Set-Location ..;
  }
}


function ahk() {
  Start-Process `
    autohotkey.exe `
    -ArgumentList "$($env:USERPROFILE)\Documents\PowerShell\keyboard.ahk" `
    -WindowStyle Hidden `
    -Verb RunAs;
}


function Update-VscodeExt() {
  $cfgFileName = "package.json";
  if (-not (Test-Path $cfgFileName)) {
    Write-Error "$cfgFileName not found";
    return;
  }
  $cfg = Get-Content $cfgFileName | ConvertFrom-Json;

  $name = $cfg.name;
  if (-not $name) {
    Write-Error "'name' property not found in the $cfgFileName";
    return;
  }
  $publisher = $cfg.publisher;
  if (-not $publisher) {
    Write-Error "'publisher' property not found in the $cfgFileName";
    return;
  }
  $version = $cfg.version;
  if (-not $version) {
    Write-Error "'version' property not found in the $cfgFileName";
    return;
  }

  $extDir = "$env:USERPROFILE\.vscode\extensions\$publisher.$name-$version";
  if (-not (Test-Path $extDir)) {
    Write-Error "'$extDir' directory not found";
    return;
  }

  Copy-Item *.js $extDir;
  Copy-Item *.json $extDir;
}
