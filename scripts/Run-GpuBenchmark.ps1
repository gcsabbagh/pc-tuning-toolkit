<#
.SYNOPSIS
    Applies optional mVolt+ GPU tuning parameters, runs a FurMark 2 Vulkan Knot benchmark
    with the artifact scanner enabled, and logs per-second GPU telemetry + benchmark scores.
#>
param(
    [string]$Label = "benchmark",
    [int]$Width = 2560,
    [int]$Height = 1440,
    [int]$DurationMs = 20000,
    [int]$PowerWatts = 0,
    [int]$CoreOffset = -9999,
    [int]$XbarOffset = -9999,
    [int]$MemOffset = -9999,
    [switch]$ResetToDefault,
    [string]$FurMarkPath = ""
)

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BinDir = Join-Path $RepoRoot "tools\bin"
. (Join-Path $PSScriptRoot "MvoltHelpers.ps1")
$mvolt = Find-Mvolt -RepoRoot $RepoRoot

$fmPaths = @(
    $FurMarkPath,
    $env:FURMARK_EXE,
    (Join-Path $BinDir "FurMark2\{app}\furmark.exe"),
    (Join-Path $BinDir "FurMark2\furmark.exe"),
    "C:\Program Files\Geeks3D\FurMark2_x64\furmark.exe",
    "C:\Program Files (x86)\Geeks3D\FurMark2_x64\furmark.exe"
)
$fmExe = $fmPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

if ($mvolt) {
    try {
        if ($ResetToDefault) {
            # mVolt+ has no single "--reset" switch; write stock values explicitly.
            # --return-to-percentage and --power are mutually exclusive, so this takes two calls.
            Write-Host "Resetting GPU to factory defaults via mVolt+..." -ForegroundColor Cyan
            Invoke-Mvolt $mvolt @("--return-to-percentage", "--core", 0, "--mem", 0, "--xbar-offset", 0, "--sys-offset", 0, "--video-offset", 0, "--boost", 0, "--clock-range", "default")
            Invoke-Mvolt $mvolt @("--power", 100)
        } else {
            $mArgs = @()
            if ($PowerWatts -gt 0) { $mArgs += @("--power-cap-watts", $PowerWatts) }
            if ($CoreOffset -ne -9999) { $mArgs += @("--core", $CoreOffset, "--clock-range", "default") }
            if ($XbarOffset -ne -9999) { $mArgs += @("--xbar-offset", $XbarOffset) }
            if ($MemOffset -ne -9999) { $mArgs += @("--mem", $MemOffset) }
            if ($mArgs.Count -gt 0) {
                Write-Host "Applying mVolt+ settings: $($mArgs -join ' ')" -ForegroundColor Cyan
                Invoke-Mvolt $mvolt $mArgs
            }
        }
    } catch {
        Write-Error $_
        return
    }
    Start-Sleep -Seconds 2
    $st = Show-MvoltStatus -MvoltPath $mvolt
    if ($ResetToDefault -and $st -and ($st.core_offset_mhz -ne 0 -or $st.xbar_offset_mhz -ne 0 -or $st.memory_offset_mhz -ne 0 -or $st.power_limit_percent -ne 100)) {
        Write-Error "GPU is NOT at stock after reset; refusing to record a misleading baseline."
        return
    }
} elseif ($ResetToDefault -or $PowerWatts -gt 0 -or $CoreOffset -ne -9999 -or $XbarOffset -ne -9999 -or $MemOffset -ne -9999) {
    Write-Error "mVolt+.exe not found but GPU settings were requested. Run .\scripts\Bootstrap-Tools.ps1 -DownloadMissing."
    return
}

if (-not $fmExe) {
    Write-Warning "FurMark 2 executable not found. Skipping benchmark run."
    return
}

$fmDir = Split-Path -Parent $fmExe
$csvOut = Join-Path $RepoRoot "tools\bin\fm_$Label.csv"
Remove-Item $csvOut -ErrorAction SilentlyContinue

Write-Host "`nRunning FurMark 2 Vulkan Knot ($($Width)x$($Height), $($DurationMs)ms, artifact scanner ON)..." -ForegroundColor Yellow
Push-Location $fmDir
try {
    & $fmExe --demo furmark-vk --width $Width --height $Height --Windowed --benchmark --max-time $DurationMs --artifact-scanner --log-gpu-data --log-gpu-data-polling-factor 1 --log-score -o $csvOut
} finally {
    Pop-Location
}

$resultsTxt = Join-Path $fmDir "_furmark_results.txt"
if (Test-Path $resultsTxt) {
    Write-Host "`n=== FURMARK 2 SCORE RESULTS ($Label) ===" -ForegroundColor Green
    Get-Content $resultsTxt | Select-Object -Last 6
}
if (Test-Path $csvOut) {
    Write-Host "`n=== GPU TELEMETRY SAMPLES ($Label) ===" -ForegroundColor Green
    Get-Content $csvOut | Select-Object -Last 8
}
