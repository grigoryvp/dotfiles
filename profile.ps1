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
      $msg += "up to date; ";
    }
    else {
      $msg += "out of sync; ";
    }
    if ($ret[3].Contains($CLEAN_MARKER) -or $ret[4].Contains($CLEAN_MARKER)) {
      $msg += "clean; ";
    }
    else {
      $msg += "changes; ";
    }
    $msg += $dirName;
    Write-Host $msg;
    Set-Location ..;
  }
}
