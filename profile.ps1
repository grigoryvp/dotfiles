try {
  # Very slow
  # Provides 'Write-Prompt'
  # Import-Module posh-git;
}
catch {
}

# Used for Elixir repl.
Remove-Alias -Force -Name iex

# For git to correctly show unicode files content.
$env:LANG = "en_US.UTF-8";
# Always install dependencies in .venv for pipenv.
$env:PIPENV_VENV_IN_PROJECT = 1
# Do not lock dependencies (very slow).
$env:PIPENV_SKIP_LOCK = 1
# Disable lockfile generation for pipenv (much faster install).
$env:PIPENV_SKIP_LOCK = 1
# Enable Python 2.7 apps to write into PowerShell console.
$env:PYTHONIOENCODING = "UTF-8"

$COLOR_DGRAY = ([ConsoleColor]::DarkGray);
$COLOR_DYELLOW = ([ConsoleColor]::DarkYellow);
$COLOR_GREEN = ([ConsoleColor]::Green);
$COLOR_BLUE = ([ConsoleColor]::Blue);
$COLOR_MAGENTA = ([ConsoleColor]::Magenta);

function cdd() { Set-Location ~/Documents; }
function cdc() { Set-Location ~/dotfiles; }
function cdx() { Set-Location ~/.xi; }
function cdh() { Set-Location ~; }
function g() { & git $Args }

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
  # Restart if already running
  # if (Get-Process "AutoHotkey" -ErrorAction SilentlyContinue) { return; }
  Start-Process `
    autohotkey.exe `
    -ArgumentList "$($env:USERPROFILE)\dotfiles\keyboard.ahk" `
    -WindowStyle Hidden `
    -Verb RunAs;
}

# ============================================================================
# Windows-OSX-Linux consistency
# ============================================================================

function rmf($dst) {
  Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
}

function ll($dst) {
  Get-ChildItem $dst
}

function grep() {
  Select-String -Path $Args[1] -Pattern $Args[0]
}

function vec() {
  python3 -m virtualenv .venv
}

function vea() {
  .\.venv\Scripts\activate.ps1
}

function ved() {
  deactivate
}

function ver() {
  Remove-Item .venv -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Tools
# ============================================================================

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

  $verPartList = $version.split(".");

  $extRoot = "$env:USERPROFILE\.vscode\extensions"
  $extDir = "";
  # Try current version and all older build semver since installed
  # extension is often older than the development one.
  for ($i = [int]$verPartList[-1]; $i -ge 0; $i --) {
    $verPartList[-1] = $i
    $curVer = [System.String]::Join(".", $verPartList);
    $extDir = "$extRoot\$publisher.$name-$curVer";
    if (Test-Path $extDir) {
      break;
    }
  }
  if (-not (Test-Path $extDir)) {
    Write-Error "'$extRoot\$publisher.$name-$version...0' dir not found";
    return;
  }

  if (-not (Test-Path -Path $extDir/src)) {
    New-Item -Path $extDir/src -ItemType Directory | Out-Null;
  }
  Copy-Item *.js $extDir;
  Copy-Item *.json $extDir;
  Write-Output "Copied into $extDir";
  if (Test-Path -Path src) {
    Copy-Item src/*.js $extDir/src;
    Copy-Item src/*.json $extDir/src;
    Write-Output "Copied ./src into $extDir/src";
  }
}

function Start-Srv() {
  $name = "srv";
  $job = Get-Job -Name $name -ErrorAction SilentlyContinue;
  if ($job) {
    Write-Host "Already started";
    return;
  }
  $job = {
    Set-Location $Args[0];
    $driveName = 'site';
    $Args = @{
      Name = $driveName
      PSProvider = 'FileSystem'
      Root = $PWD.Path
    };
    New-PSDrive @Args;
    $listener = New-Object System.Net.HttpListener;
    $listener.Prefixes.Add("http://localhost:8080/");
    $listener.Start();
    while($listener.IsListening) {
      $context = $listener.GetContext();
      $url = $Context.Request.Url.LocalPath;
      if ($url -eq '/favicon.ico') {
        $Context.Response.Close();
        continue;
      }
      if ($url -eq '/_stop') {
        $listener.Stop();
        Remove-PSDrive -Name $driveName;
        return;
      }
      $ext = [System.IO.Path]::GetExtension($url);
      $context.Response.ContentType = @{
        '.htm' = 'text/html'
        '.html' = 'text/html'
        '.css' = 'text/css'
        '.svg' = 'image/svg+xml'
        '.png' = 'image/png'
        '.jpg' = 'image/jpeg'
        '.jepg' = 'image/jpeg'
      }[$ext];
      try {
        $data = Get-Content -AsByteStream -Path "$($driveName):$url";
        $context.Response.OutputStream.Write($data, 0, $data.Length);
      }
      catch {
        $context.Response.StatusCode = 404;
      }
      $Context.Response.Close();
    }
  };
  $job = Start-Job -Name $name -ArgumentList $PWD -ScriptBlock $job;
  Write-Host "Server job started";
}

function Stop-Srv() {
  $name = "srv";
  $job = Get-Job -Name $name -ErrorAction SilentlyContinue;
  if ($job) {
    try {
      Invoke-WebRequest -Uri 'http://localhost:8080/_stop';
    }
    catch {
    }
    Stop-Job -Name $name;
    Remove-Job -Name $name;
    Write-Host "Server job stopped";
  }
  else {
    Write-Host "No server job found";
  }
}

$promptMsg = $null;

function Add-PromptMsg($msg) {
  Set-Variable -Name "promptMsg" -Value $msg -Scope Global;
  [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt();
  $timer = New-Object System.Timers.Timer
  $timer.AutoReset = $false
  $timer.Interval = 1000
  Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action {
    Set-Variable -Name "promptMsg" -Value $null -Scope Global;
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt();
  }
  $timer.Enabled = $true
}

# Without this, returns cleared screen after any input.
Set-PSReadlineKeyHandler -Key Ctrl+l -ScriptBlock {
  [Microsoft.PowerShell.PSConsoleReadLine]::ClearScreen();
}

Set-PSReadlineKeyHandler -Key Ctrl+d -ScriptBlock {
  Add-PromptMsg "dbg";
}

# Very slow
# if (Get-Command "conda.exe" -ErrorAction SilentlyContinue) {
#   (& conda.exe shell.powershell hook) | Out-String | Invoke-Expression
# }

# After conda, which tries to replace prompt.
function prompt {
  Write-Host "[" -NoNewLine -ForegroundColor $COLOR_DGRAY;
  if ($promptMsg) {
    Write-Host $promptMsg -NoNewLine -ForegroundColor $COLOR_GREEN;
  }
  else {
    Write-Host "..." -NoNewLine -ForegroundColor $COLOR_DYELLOW;
  }
  Write-Host "] " -NoNewLine -ForegroundColor $COLOR_DGRAY;
  if ($env:USERPROFILE) {
    $location = $(Get-Location).ToString().Replace($env:USERPROFILE, "~");
  }
  else {
    $location = $(Get-Location).ToString().Replace($env:HOME, "~");
  }
  $locationItemList = $location.Replace("\", "/").Split("/");
  foreach ($locationItem in $locationItemList) {
    Write-Host $locationItem -NoNewLine -ForegroundColor $COLOR_MAGENTA;
    Write-Host "/" -NoNewLine -ForegroundColor $COLOR_BLUE;
  }
  Write-Host " $" -NoNewLine -ForegroundColor $COLOR_DGRAY;
  # Return something to replace default prompt.
  return " ";
}

if ($IsMacOS) {
  # Homebrew will refuse to link Ruby 2.7 over os-provided 2.3 version.
  $Env:PATH = "/usr/local/opt/ruby/bin:$Env:PATH";
  # Homebrew can --link Python, but modify path for consistancy with Ruby.
  $Env:PATH = "/usr/local/opt/python@3.8/bin:$Env:PATH";
}
