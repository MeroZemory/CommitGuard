# CommitGuard - commit-memory leak watchdog for Windows
# https://github.com/MeroZemory/CommitGuard
#
# Monitors system commit charge and per-process commit; raises a Windows toast
# notification when thresholds are crossed. Designed to run hidden at logon.
#
# Why commit charge and not RAM %: a leaked language server once committed
# 111 GB of virtual memory, pushing system commit to 98% of the limit. The
# whole desktop froze every few seconds while Task Manager's RAM % still
# looked fine (18 GB physical free). Near the commit limit, every memory
# allocation stalls - windows freeze, yet the mouse cursor keeps moving.
# This tool watches the metric that actually mattered.

param(
    [int]$IntervalSec = 30,
    [int]$CommitPctWarn = 80,       # system commit usage % -> warning
    [int]$CommitPctCritical = 90,   # system commit usage % -> critical
    [int]$ProcCommitGB = 20,        # single-process commit GB -> leak suspect
    [int]$CooldownMin = 15,         # min minutes between same-type alerts
    [switch]$TestToast              # show a test notification and exit
)

$ErrorActionPreference = 'SilentlyContinue'
$LogPath = Join-Path $PSScriptRoot 'commit-guard.log'

function Write-Log([string]$msg) {
    $line = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $msg
    Add-Content -Path $LogPath -Value $line -Encoding utf8
    # rotate: keep log under ~1 MB
    if ((Get-Item $LogPath).Length -gt 1MB) {
        $tail = Get-Content $LogPath -Tail 200
        Set-Content $LogPath $tail -Encoding utf8
    }
}

function Show-Toast([string]$title, [string]$body) {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $texts = $xml.GetElementsByTagName('text')
        $texts.Item(0).AppendChild($xml.CreateTextNode($title)) | Out-Null
        $texts.Item(1).AppendChild($xml.CreateTextNode($body)) | Out-Null
        $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
        return $true
    } catch {
        Write-Log "toast failed: $($_.Exception.Message)"
        return $false
    }
}

if ($TestToast) {
    $ok = Show-Toast 'CommitGuard test' 'Notifications are working.'
    Write-Log "test toast shown: $ok"
    exit
}

# singleton: exit quietly if another instance already runs
$mutex = New-Object System.Threading.Mutex($false, 'Global\CommitGuardWatchdog')
if (-not $mutex.WaitOne(0)) { exit }

Write-Log "CommitGuard started (interval=${IntervalSec}s warn=${CommitPctWarn}% crit=${CommitPctCritical}% proc=${ProcCommitGB}GB)"

$lastAlert = @{}   # alert-key -> last DateTime
function Should-Alert([string]$key) {
    $now = Get-Date
    if ($lastAlert.ContainsKey($key) -and ($now - $lastAlert[$key]).TotalMinutes -lt $CooldownMin) { return $false }
    $lastAlert[$key] = $now
    return $true
}

$lastHeartbeat = Get-Date
while ($true) {
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os) {
        $limitGB  = $os.TotalVirtualMemorySize * 1KB / 1GB
        $usedGB   = ($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) * 1KB / 1GB
        $pct      = [math]::Round(100 * $usedGB / $limitGB)

        # top commit consumers (PagedMemorySize64 = committed private bytes)
        $top = Get-Process | Sort-Object PagedMemorySize64 -Descending | Select-Object -First 3
        $topStr = ($top | ForEach-Object { "{0}(PID {1}) {2:N1}GB" -f $_.ProcessName, $_.Id, ($_.PagedMemorySize64/1GB) }) -join ', '

        if ($pct -ge $CommitPctCritical) {
            if (Should-Alert 'critical') {
                Show-Toast "Commit memory CRITICAL: ${pct}%" "System freeze imminent. Top: $topStr" | Out-Null
                Write-Log "CRITICAL commit=${pct}% ($([math]::Round($usedGB))GB/$([math]::Round($limitGB))GB) top: $topStr"
            }
        }
        elseif ($pct -ge $CommitPctWarn) {
            if (Should-Alert 'warn') {
                Show-Toast "Commit memory warning: ${pct}%" "Top: $topStr" | Out-Null
                Write-Log "WARN commit=${pct}% top: $topStr"
            }
        }

        # single-process leak suspect
        $leaker = $top | Where-Object { $_.PagedMemorySize64 -ge $ProcCommitGB * 1GB } | Select-Object -First 1
        if ($leaker) {
            $key = "proc-$($leaker.Id)"
            if (Should-Alert $key) {
                $gb = [math]::Round($leaker.PagedMemorySize64/1GB, 1)
                Show-Toast "Possible memory leak: $($leaker.ProcessName)" "PID $($leaker.Id) has committed ${gb}GB (threshold ${ProcCommitGB}GB). Check Task Manager." | Out-Null
                Write-Log "LEAK-SUSPECT $($leaker.ProcessName) PID=$($leaker.Id) commit=${gb}GB (system=${pct}%)"
            }
        }

        # hourly heartbeat so the log shows it is alive
        if (((Get-Date) - $lastHeartbeat).TotalMinutes -ge 60) {
            Write-Log "heartbeat commit=${pct}% top: $topStr"
            $lastHeartbeat = Get-Date
        }
    }
    Start-Sleep -Seconds $IntervalSec
}
