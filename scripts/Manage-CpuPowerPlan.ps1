<#
.SYNOPSIS
    Inspects, backs up, or optimizes the active Windows Processor Power Plan.
    "SmartHighPerf" mode keeps Core Parking 100% disabled (zero core wake-up stutter in games)
    while setting Minimum Processor State to 5% and Speed Shift / CPPC EPP to 60% so the CPU
    drops voltage/wattage at idle and snaps to max boost in <1ms under load.
#>
param(
    [ValidateSet("Status", "ApplySmartHighPerf", "Lock100Percent", "Backup", "Restore")]
    [string]$Action = "Status",
    [string]$BackupFile = ""
)

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $BackupFile) {
    $BackupFile = Join-Path $RepoRoot "tools\bin\ActivePowerPlan_Backup.pow"
}

$activeLine = powercfg /getactivescheme
Write-Host "Active Power Scheme: $activeLine" -ForegroundColor Cyan

if ($Action -eq "Backup") {
    if ($activeLine -match "([0-9a-fA-F\-]{36})") {
        $guid = $Matches[1]
        powercfg /export $BackupFile $guid
        Write-Host "Exported backup to: $BackupFile" -ForegroundColor Green
    }
    return
}

if ($Action -eq "Restore") {
    if (-not (Test-Path -LiteralPath $BackupFile)) {
        Write-Error "Backup file not found: $BackupFile"
        return
    }
    # powercfg /import only adds the scheme; it must be activated explicitly.
    $importOut = powercfg /import $BackupFile 2>&1 | Out-String
    if ($importOut -match "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})") {
        $newGuid = $Matches[1]
        powercfg /setactive $newGuid
        Write-Host "Restored and activated power plan $newGuid from: $BackupFile" -ForegroundColor Green
        Write-Host "Active Power Scheme: $(powercfg /getactivescheme)" -ForegroundColor Cyan
    } else {
        Write-Error "powercfg /import did not return a scheme GUID. Output: $importOut"
    }
    return
}

# Writes a processor power setting for both AC (plugged in) and DC (battery).
function Set-ProcSetting([string]$Alias, [int]$Value) {
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR $Alias $Value
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR $Alias $Value
}

if ($Action -eq "ApplySmartHighPerf") {
    Write-Host "Applying Smart High-Performance (Core Parking OFF + Dynamic Idle Scaling via EPP 60%)..." -ForegroundColor Yellow
    # Keep all cores 100% unparked (both Class 0 and Class 1)
    Set-ProcSetting CPMINCORES 100
    Set-ProcSetting CPMINCORES1 100
    # Allow minimum processor state to scale down to 5% when idle
    Set-ProcSetting PROCTHROTTLEMIN 5
    Set-ProcSetting PROCTHROTTLEMIN1 5
    Set-ProcSetting HETEROCLASS0FLOORPERF 5
    # Set Speed Shift / CPPC Energy Performance Preference (EPP) to 60%
    Set-ProcSetting PERFEPP 60
    Set-ProcSetting PERFEPP1 60
    powercfg /setactive SCHEME_CURRENT
    Write-Host "  [OK] Smart High-Performance applied (AC + DC)." -ForegroundColor Green
}

if ($Action -eq "Lock100Percent") {
    Write-Host "Locking all cores to 100% minimum state (EPP 5%)..." -ForegroundColor Yellow
    Set-ProcSetting CPMINCORES 100
    Set-ProcSetting CPMINCORES1 100
    Set-ProcSetting PROCTHROTTLEMIN 100
    Set-ProcSetting PROCTHROTTLEMIN1 100
    Set-ProcSetting HETEROCLASS0FLOORPERF 100
    Set-ProcSetting PERFEPP 5
    Set-ProcSetting PERFEPP1 5
    powercfg /setactive SCHEME_CURRENT
    Write-Host "  [OK] Locked 100% processor state applied (AC + DC)." -ForegroundColor Green
}

Write-Host "`n--- Current Processor Power Settings ---" -ForegroundColor Yellow
powercfg /qh SCHEME_CURRENT SUB_PROCESSOR | Select-String -Pattern "GUID Alias: (CPMINCORES|PROCTHROTTLEMIN|PROCTHROTTLEMAX|PERFEPP|HETEROCLASS0FLOORPERF)" -Context 0,5
