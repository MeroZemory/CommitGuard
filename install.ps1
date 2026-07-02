# CommitGuard installer - registers autostart at logon and starts the watchdog.
# No admin rights required (uses the per-user Startup folder).
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'commit-guard.ps1'
if (-not (Test-Path $scriptPath)) { throw "commit-guard.ps1 not found next to install.ps1" }

$startup = [Environment]::GetFolderPath('Startup')
$vbsPath = Join-Path $startup 'CommitGuard.vbs'

# VBS launcher runs the watchdog fully hidden (no console flash)
$vbs = @"
' CommitGuard autostart launcher - runs the watchdog hidden at logon
CreateObject("Wscript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$scriptPath""", 0, False
"@
Set-Content -Path $vbsPath -Value $vbs -Encoding ASCII
Write-Host "Autostart registered: $vbsPath"

# start it now (mutex in the script prevents duplicates)
Start-Process wscript.exe -ArgumentList "`"$vbsPath`""
Write-Host "CommitGuard started. Log: $(Join-Path $PSScriptRoot 'commit-guard.log')"
Write-Host "Test the notification with:"
Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -TestToast"
