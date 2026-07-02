# CommitGuard uninstaller - stops the watchdog and removes autostart.
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1

$ErrorActionPreference = 'SilentlyContinue'

$vbsPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'CommitGuard.vbs'
if (Test-Path $vbsPath) {
    Remove-Item $vbsPath -Force
    Write-Host "Autostart removed: $vbsPath"
} else {
    Write-Host "Autostart entry not found (already removed)."
}

$killed = 0
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'commit-guard\.ps1' -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force; $killed++ }
Write-Host "Stopped $killed running instance(s)."
Write-Host "Done. The CommitGuard folder itself was left in place - delete it if you no longer need it."
