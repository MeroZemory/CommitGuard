# CommitGuard

A tiny Windows watchdog that catches **commit-memory (virtual memory) leaks before they freeze your desktop** — the kind of problem Task Manager's RAM % never shows you.

Windows PowerShell 5.1 and macOS zsh implementations, zero dependencies, no admin rights required.

## The problem it solves

One day my desktop started freezing for 3–8 seconds every few seconds: typing lagged in bursts, every window stopped repainting (even Task Manager), yet the mouse cursor kept moving. RAM looked fine — 18 GB free out of 64 GB.

The real cause: a leaked TypeScript language server had **committed 111 GB of virtual memory**, pushing the system commit charge to **98% of the commit limit**. Near that limit, every memory allocation stalls system-wide — window rendering, input handling, everything — while the (allocation-free) hardware mouse cursor glides along happily.

Task Manager's memory percentage tracks *physical RAM*, so it looked healthy the whole time. The number that mattered was **Committed** (Performance tab), and nothing was watching it.

CommitGuard watches it.

## What it does

Every 30 seconds it checks:

| Condition | Default threshold | Toast notification |
|---|---|---|
| System commit usage | ≥ 80% | Warning, with top 3 commit consumers |
| System commit usage | ≥ 90% | Critical — freeze imminent |
| Single process commit | ≥ 20 GB | Leak suspect, with process name and PID |

- Repeated alerts of the same type are muted for 15 minutes (no spam).
- A mutex guarantees only one instance runs.
- Activity is logged to `commit-guard.log` (hourly heartbeat, auto-rotates at 1 MB).

## Install on Windows

```powershell
git clone https://github.com/MeroZemory/CommitGuard.git
cd CommitGuard
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

The installer drops a hidden launcher into your per-user Startup folder (so it survives reboots) and starts the watchdog immediately. No admin prompt, no scheduled task, no service.

Verify notifications work:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File commit-guard.ps1 -TestToast
```

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
```

Removes the autostart entry and stops the running watchdog. Delete the folder afterwards if you like.

## Install on macOS

macOS does not expose a Windows-style system commit limit. The macOS watchdog
therefore watches the OS-reported free-memory percentage and per-process RSS
(resident memory), and sends Notification Center alerts when pressure is high.

```zsh
git clone https://github.com/MeroZemory/CommitGuard.git
cd CommitGuard
./install-macos.sh
```

It registers a per-user LaunchAgent, so no administrator password is required.
Verify the Notification Center integration with:

```zsh
./commit-guard-macos.sh --test-notification
```

Run one non-persistent health check (useful for verification) with:

```zsh
./commit-guard-macos.sh --once
```

To remove autostart without deleting the checkout or logs:

```zsh
./uninstall-macos.sh
```

macOS tuning options:

```zsh
./commit-guard-macos.sh --free-pct-warn 25 --free-pct-critical 12 --proc-rss-gb 6 --interval 15
```

| Option | Default | Meaning |
|---|---:|---|
| `--free-pct-warn` | 20 | Alert when system free memory reaches this percentage or below |
| `--free-pct-critical` | 10 | Critical alert threshold for free memory |
| `--proc-rss-gb` | 8 | Per-process resident-memory threshold |
| `--interval` | 30 | Seconds between checks |
| `--cooldown-min` | 15 | Minutes between repeated alerts |

## Tuning

All thresholds are script parameters — edit the defaults at the top of `commit-guard.ps1`, or run it manually with overrides:

```powershell
powershell -File commit-guard.ps1 -CommitPctWarn 75 -ProcCommitGB 10 -IntervalSec 15
```

| Parameter | Default | Meaning |
|---|---|---|
| `IntervalSec` | 30 | Seconds between checks |
| `CommitPctWarn` | 80 | System commit % for a warning toast |
| `CommitPctCritical` | 90 | System commit % for a critical toast |
| `ProcCommitGB` | 20 | Per-process committed GB to flag as a leak suspect |
| `CooldownMin` | 15 | Minutes between repeated alerts of the same type |

## How it works

- System commit charge comes from `Win32_OperatingSystem` (`TotalVirtualMemorySize` − `FreeVirtualMemory`).
- Per-process commit is `Get-Process` → `PagedMemorySize64` (committed private bytes).
- Notifications use the Windows Runtime toast API directly — no BurntToast or other modules.
- Autostart is a `.vbs` launcher in `shell:startup` that runs PowerShell fully hidden (no console flash at logon).

## Requirements

- Windows 10/11
- Windows PowerShell 5.1 (preinstalled)

## License

MIT
