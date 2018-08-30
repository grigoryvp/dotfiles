# My windows box automatic configuration

Install PowerShell Core from [releases](https://github.com/PowerShell/PowerShell/releases) page.

```ps1
cd ~; Invoke-WebRequest -OutFile configure.ps1 -Uri https://raw.githubusercontent.com/grigoryvp/my-win-box-cfg/master/configure.ps1; & .\configure.ps1
```
