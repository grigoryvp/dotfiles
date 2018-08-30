Import-Module posh-git;

function cdd() { Set-Location ~/Documents; }
function cdc() { Set-Location ~/Documents/PowerShell; }
function cdh() { Set-Location ~; }

function gst() {
  $dirNameList = Get-ChildItem -Name -Directory;
  foreach ($dirName in $dirNameList) {
    Set-Location $dirName;
    $ret = & git status;
    $UP_MARKER = "Your branch is up to date with";
    $CLEAN_MARKER = "nothing to commit, working tree clean";
    $msg = "";
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
      Write-Host "out of sync" -NoNewline -ForegroundColor Red;
      Write-Host "; " -NoNewline;
    }
    Write-Host $dirName;
    Set-Location ..;
  }
}
