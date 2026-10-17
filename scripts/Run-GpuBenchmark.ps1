<#
.SYNOPSIS
    Applies optional mVolt+ GPU tuning parameters, runs one or more FurMark 2 Knot (Vulkan)
    benchmark passes with the artifact scanner enabled, and reports per-run and aggregate
    scores (mean / min / max / spread) plus per-second GPU telemetry.

.NOTES
    FurMark is a steady-state heavy load: it measures performance and catches artifacts at
    heavy load, but it does NOT prove gaming stability (see docs/methodology.md). Validate the
    final profile with OCCT 3D Adaptive and a real multiplayer session.

    Scores come from FurMark's own _scores.csv (written next to furmark.exe after each
    --benchmark --duration-ms run). Per-run telemetry is written to tools\bin\fm_<Label>[_runN].csv
    and a summary to tools\bin\fm_<Label>_summary.csv.
#>
param(
    [string]$Label = "benchmark",
    [string]$Demo = "furmark-knot-vk",
    [int]$Width = 2560,
    [int]$Height = 1440,
    [int]$DurationMs = 30000,
    [ValidateRange(1, 10)]
    [int]$Runs = 1,
    [int]$CooldownSec = 15,
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
$scoresCsv = Join-Path $fmDir "_scores.csv"
$fmLog = Join-Path $fmDir "_furmark_log.txt"

# Returns the newest _scores.csv row written at or after $Since, or $null.
function Get-FurMarkScore([datetime]$Since) {
    if (-not (Test-Path -LiteralPath $scoresCsv)) { return $null }
    $row = Import-Csv -LiteralPath $scoresCsv | Select-Object -Last 1
    if (-not $row) { return $null }
    $when = [datetime]::ParseExact($row.date, "yyyy.MM.dd@HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
    if ($when -lt $Since.AddSeconds(-1)) { return $null }
    [PSCustomObject]@{
        Time   = $when
        Score  = [int]$row.score
        MinFps = [int]$row.min_fps
        AvgFps = [int]$row.avg_fps
        MaxFps = [int]$row.max_fps
    }
}

# Summarizes the discrete GPU's rows from a FurMark --log-gpu-data CSV.
# The log also contains iGPU / virtual adapter rows (temperature -1), which are skipped.
function Get-FurMarkTelemetry([string]$CsvPath) {
    if (-not (Test-Path -LiteralPath $CsvPath)) { return $null }
    $lines = Get-Content -LiteralPath $CsvPath
    $cols = $lines[0] -split "," | ForEach-Object { $_.Trim() }
    $rows = $lines | Select-Object -Skip 1 | ForEach-Object {
        $v = $_ -split "," | ForEach-Object { $_.Trim() }
        $o = @{}
        for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $v[$i] }
        [PSCustomObject]$o
    } | Where-Object { [double]$_.gpu_temp -ge 0 -and [double]$_.gpu_core_clock -gt 0 -and [double]$_.fps -gt 0 }
    if (-not $rows) { return $null }
    [PSCustomObject]@{
        AvgCoreMHz = [math]::Round(($rows | Measure-Object { [double]$_.gpu_core_clock } -Average).Average)
        MaxCoreMHz = ($rows | Measure-Object { [double]$_.gpu_core_clock } -Maximum).Maximum
        VramMHz    = ($rows | Measure-Object { [double]$_.vram_clock } -Maximum).Maximum
        MaxTempC   = ($rows | Measure-Object { [double]$_.gpu_temp } -Maximum).Maximum
        MaxVramC   = ($rows | Measure-Object { [double]$_.vram_temp } -Maximum).Maximum
    }
}

$results = @()
for ($run = 1; $run -le $Runs; $run++) {
    $suffix = if ($Runs -gt 1) { "_run$run" } else { "" }
    $csvOut = Join-Path $BinDir "fm_$Label$suffix.csv"
    Remove-Item -LiteralPath $csvOut -ErrorAction SilentlyContinue

    if ($run -gt 1 -and $CooldownSec -gt 0) {
        Write-Host "Cooling down for $CooldownSec s..." -ForegroundColor Gray
        Start-Sleep -Seconds $CooldownSec
    }

    # Record the tuning state actually active for this run (XBar etc. are not in FurMark's telemetry).
    $gpuState = if ($mvolt) { Get-MvoltStatus -MvoltPath $mvolt } else { $null }

    Write-Host "`n[$Label] Run $run/${Runs}: $Demo $($Width)x$($Height), $($DurationMs / 1000)s, artifact scanner ON" -ForegroundColor Yellow
    $start = Get-Date
    Push-Location $fmDir
    try {
        # Piping forces PowerShell to wait for furmark.exe to exit.
        & $fmExe --demo $Demo --width $Width --height $Height --benchmark --duration-ms $DurationMs --no-score-box --artifact-scanner --log-gpu-data --log-gpu-data-filename $csvOut | Out-Host
    } finally {
        Pop-Location
    }

    $score = Get-FurMarkScore -Since $start
    if (-not $score) {
        Write-Warning "Run ${run}: no new score in $scoresCsv (FurMark crashed, was closed early, or the GPU reset). Check .\scripts\Diagnose-Crashes.ps1 -HoursBack 1."
        continue
    }
    $tele = Get-FurMarkTelemetry -CsvPath $csvOut

    # FurMark overwrites _furmark_log.txt each launch; surface any scanner lines beyond its startup banner.
    $scanLines = @()
    if (Test-Path -LiteralPath $fmLog) {
        $scanLines = @(Select-String -LiteralPath $fmLog -Pattern "artifact" |
            Where-Object { $_.Line -notmatch "Artifact scanner for GPU stability checking" -and $_.Line -notmatch "command line:" } |
            ForEach-Object { $_.Line })
    }

    $results += [PSCustomObject]@{
        Label      = $Label
        Run        = $run
        Time       = $score.Time.ToString("yyyy-MM-dd HH:mm:ss")
        Demo       = $Demo
        Profile    = $gpuState.active_profile
        PowerW     = if ($gpuState) { $gpuState.power_limits.enforced_mw / 1000 } else { $null }
        CoreOff    = $gpuState.core_offset_mhz
        XbarOff    = $gpuState.xbar_offset_mhz
        MemOff     = $gpuState.memory_offset_mhz
        Score      = $score.Score
        MinFps     = $score.MinFps
        AvgFps     = $score.AvgFps
        MaxFps     = $score.MaxFps
        AvgCoreMHz = $tele.AvgCoreMHz
        MaxCoreMHz = $tele.MaxCoreMHz
        VramMHz    = $tele.VramMHz
        MaxTempC   = $tele.MaxTempC
        MaxVramC   = $tele.MaxVramC
        ScannerLog = ($scanLines -join " | ")
    }
    if ($scanLines) {
        Write-Host "  [ARTIFACT SCANNER] $($scanLines -join ' | ')" -ForegroundColor Red
    }
}

if (-not $results) {
    Write-Error "No benchmark runs completed."
    return
}

Write-Host "`n=== FURMARK 2 RESULTS ($Label) ===" -ForegroundColor Green
$results | Format-Table Run, Time, PowerW, CoreOff, XbarOff, MemOff, Score, MinFps, AvgFps, MaxFps, AvgCoreMHz, MaxCoreMHz, VramMHz, MaxTempC, MaxVramC -AutoSize | Out-Host

if ($results.Count -gt 1) {
    $scores = $results | ForEach-Object { [double]$_.Score }
    $mean = ($scores | Measure-Object -Average).Average
    $min = ($scores | Measure-Object -Minimum).Minimum
    $max = ($scores | Measure-Object -Maximum).Maximum
    $stdev = [math]::Sqrt((($scores | ForEach-Object { ($_ - $mean) * ($_ - $mean) }) | Measure-Object -Sum).Sum / ($scores.Count - 1))
    $avgFps = ($results | Measure-Object AvgFps -Average).Average
    Write-Host ("Score: mean {0:N0} | min {1:N0} | max {2:N0} | stdev {3:N1} | spread {4:N1}% ({5} runs) | avg FPS {6:N1}" -f `
        $mean, $min, $max, $stdev, (($max - $min) / $mean * 100), $results.Count, $avgFps) -ForegroundColor Green
    Write-Host "  Treat score differences smaller than the spread as noise." -ForegroundColor Gray
}
if (@($results | ForEach-Object { "$($_.PowerW)|$($_.CoreOff)|$($_.XbarOff)|$($_.MemOff)" } | Select-Object -Unique).Count -gt 1) {
    Write-Warning "mVolt+ settings changed between runs; these runs are not comparable."
}

$summaryCsv = Join-Path $BinDir "fm_$($Label)_summary.csv"
$results | Export-Csv -LiteralPath $summaryCsv -NoTypeInformation
Write-Host "Summary saved to: $summaryCsv" -ForegroundColor Cyan
if ($results.Count -lt $Runs) {
    Write-Warning "$($Runs - $results.Count) of $Runs runs produced no score."
}
