<#
.SYNOPSIS
    Forensic Crash & Instability Scanner for GPU, CPU, and Memory.
    Scans Windows Event Logs (System & Application) over a specified window for:
    - GPU Driver TDRs & Faults (nvlddmkm Event IDs 13, 14, 153; Display Event ID 4101; LiveKernelEvent 141/117)
    - CPU / Cache / Interconnect Hardware Errors (WHEA-Logger Event IDs 1, 18, 19, 46)
    - Application / Game Faults (Application Error Event ID 1000, Windows Error Reporting 1001)
    - Unexpected Reboots & BSODs (Kernel-Power Event ID 41, BugCheck 1001)
#>
param(
    [int]$HoursBack = 24
)

$StartTime = (Get-Date).AddHours(-$HoursBack)
Write-Host "================ CRASH & STABILITY FORENSICS (Last $HoursBack Hours) ================" -ForegroundColor Cyan
Write-Host "Window Start: $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))`n"

# 1. GPU TDR & Driver Errors (nvlddmkm / Display / amduw23g)
Write-Host "=== 1. GPU DRIVER & TDR EVENTS (nvlddmkm / Display) ===" -ForegroundColor Yellow
$gpuEvents = Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$StartTime} -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match "^(nvlddmkm|Display|amdkmdag|amduw\w*)$" }

if ($gpuEvents) {
    foreach ($e in $gpuEvents | Select-Object -First 25) {
        $msg = $e.Message
        if (-not $msg) { $msg = "(no message template) data: " + (($e.Properties | ForEach-Object { "$($_.Value)" } | Where-Object { $_ }) -join "; ") }
        Write-Host ("[{0}] Provider={1} ID={2} Level={3}: {4}" -f $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $e.ProviderName, $e.Id, $e.LevelDisplayName, ($msg -replace "\r?\n"," ")) -ForegroundColor Red
    }
} else {
    Write-Host "  [CLEAN] 0 GPU driver resets or TDR events found." -ForegroundColor Green
}

# 2. CPU / Cache / PCIe Hardware Errors (WHEA-Logger)
Write-Host "`n=== 2. CPU / CACHE / INTERCONNECT HARDWARE ERRORS (WHEA-Logger) ===" -ForegroundColor Yellow
$wheaEvents = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$StartTime} -ErrorAction SilentlyContinue
if ($wheaEvents) {
    foreach ($e in $wheaEvents | Select-Object -First 20) {
        Write-Host ("[{0}] WHEA ID={1}: {2}" -f $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $e.Id, ($e.Message -replace "\r\n"," ")) -ForegroundColor Red
    }
} else {
    Write-Host "  [CLEAN] 0 WHEA hardware errors found." -ForegroundColor Green
}

# 3. Unexpected Reboots / BSODs
Write-Host "`n=== 3. UNEXPECTED REBOOTS & BUGCHECKS ===" -ForegroundColor Yellow
$powerEvents = Get-WinEvent -FilterHashtable @{LogName='System'; Id=@(41, 1001); StartTime=$StartTime} -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match "Kernel-Power|WER-SystemErrorReporting|BugCheck" }
if ($powerEvents) {
    foreach ($e in $powerEvents) {
        Write-Host ("[{0}] {1} (ID {2}): {3}" -f $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $e.ProviderName, $e.Id, ($e.Message -replace "\r\n"," ")) -ForegroundColor Red
    }
} else {
    Write-Host "  [CLEAN] 0 unexpected reboots or BSODs found." -ForegroundColor Green
}

# 4. Application Crashes & LiveKernelEvents
Write-Host "`n=== 4. APPLICATION CRASHES & LIVEKERNELEVENTS ===" -ForegroundColor Yellow
$appEvents = Get-WinEvent -FilterHashtable @{LogName='Application'; Id=@(1000, 1001); StartTime=$StartTime} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -notmatch "svchost\.exe_LocalService" }
if ($appEvents) {
    foreach ($e in $appEvents | Select-Object -First 20) {
        $msg = ($e.Message -split "\r?\n" | Select-Object -First 6) -join " | "
        Write-Host ("[{0}] ID={1}: {2}" -f $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $e.Id, $msg)
    }
} else {
    Write-Host "  [CLEAN] 0 application crashes found." -ForegroundColor Green
}
