# My windows box automatic configuration

```ps1
Set-ExecutionPolicy RemoteSigned -scope CurrentUser
curl -OutFile configure.ps1 -Uri https://raw.githubusercontent.com/grigoryvp/my-win-box-cfg/master/configure.ps1
& .\configure.ps1
```
