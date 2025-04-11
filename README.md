# MLDS Server Access Script

Choose a script based on your OS/access method and paste it into the terminal on your computer.

## macOS

```bash
bash <(curl -s https://raw.githubusercontent.com/meowteusz/mlds-access/refs/heads/main/access.sh)
```

## WSL2

```bash
bash <(curl -s https://raw.githubusercontent.com/meowteusz/mlds-access/refs/heads/main/wsl2.sh)
```

## PowerShell

```powershell
iwr -useb https://raw.githubusercontent.com/meowteusz/mlds-access/refs/heads/main/access.bat -OutFile $env:TEMP\mlds-setup.bat; Start-Process cmd -ArgumentList "/c $env:TEMP\mlds-setup.bat" -Wait
```