#
# install.ps1 — Set up auto-launch for ThrottleStop on every boot
#
# What this does:
#   1. Asks for the path to ThrottleStop.exe
#   2. Imports a Task Scheduler task that auto-launches ThrottleStop with
#      highest privileges on user logon (no UAC prompt every boot)
#
# Run with: PowerShell as Administrator
#   Right-click install.ps1 → "Run with PowerShell" (will elevate via UAC)
#

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════"
Write-Host "  lenovo-pl-unlock — Windows installer"
Write-Host "═══════════════════════════════════════════════════════════"
Write-Host ""
Write-Host "Before running this:"
Write-Host "  1. ThrottleStop must be downloaded and configured (see ../windows/README.md)"
Write-Host "  2. Inside ThrottleStop, save your unlock profile and tick"
Write-Host "     'Save as default' so it auto-applies on launch"
Write-Host ""

# Find ThrottleStop
$defaultPath = "C:\Program Files\ThrottleStop\ThrottleStop.exe"
if (Test-Path $defaultPath) {
    $tsPath = $defaultPath
    Write-Host "Found ThrottleStop at: $tsPath"
    $confirm = Read-Host "Use this path? [Y/n]"
    if ($confirm -eq "n" -or $confirm -eq "N") {
        $tsPath = Read-Host "Enter the full path to ThrottleStop.exe"
    }
} else {
    $tsPath = Read-Host "Enter the full path to ThrottleStop.exe"
}

if (-not (Test-Path $tsPath)) {
    Write-Host "ERROR: ThrottleStop.exe not found at: $tsPath" -ForegroundColor Red
    Write-Host "Download it from https://www.techpowerup.com/download/techpowerup-throttlestop/"
    exit 1
}

# Build the Task Scheduler task in code (more portable than importing XML)
$taskName = "LPL-ThrottleStop-AutoLaunch"

# If task already exists, remove it
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Write-Host "Removing existing scheduled task..."
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

Write-Host ""
Write-Host "Creating scheduled task: $taskName"

$action = New-ScheduledTaskAction `
    -Execute $tsPath `
    -WorkingDirectory (Split-Path $tsPath -Parent)

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
    -RestartCount 0 `
    -DisallowDemandStart:$false `
    -DisallowHardTerminate:$false

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Auto-launch ThrottleStop with highest privileges on logon, applies saved Lenovo PL Unlock profile"

Write-Host ""
Write-Host "✓ Scheduled task created: $taskName"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Reboot your machine"
Write-Host "  2. Verify ThrottleStop launches automatically and applies your unlock profile"
Write-Host "  3. Open Task Manager → Performance → CPU and confirm CPU hits 4 GHz under load"
Write-Host ""
Write-Host "If something goes wrong:"
Write-Host "  - Check Task Scheduler → Library → '$taskName' → History tab"
Write-Host "  - Re-run this installer to recreate the task"
Write-Host "  - To uninstall: Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false"
Write-Host ""
Write-Host "Don't forget the Windows-side optimizations in ../windows/README.md:"
Write-Host "  - Set Power Plan to Ultimate Performance"
Write-Host "  - Set Lenovo Vantage to highest tier"
Write-Host "  - Add ThrottleStop + benchmark dirs to Defender exclusions"
