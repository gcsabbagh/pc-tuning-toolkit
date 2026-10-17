<#
.SYNOPSIS
    Bootstraps and verifies all required runtimes, libraries, drivers, and binaries for the Agentic PC Tuning Toolkit:
    1. Administrator privilege check
    2. .NET 8+ SDK & .NET 10 Runtime (required to build and run SensorCli with LibreHardwareMonitorLib)
    3. LibreHardwareMonitorLib.dll + PawnIO VBS-compatible kernel driver (via FanControl)
    4. SensorCli.exe (CPU/Motherboard/DDR5 telemetry & native Scalar/AVX2 stress tool)
    5. mVolt+.exe (NVIDIA Ada/Blackwell VF & XBar CLI tuner from b00nz/mVolt)
    6. FurMark 2 CLI (Vulkan GPU benchmark & artifact scanner)
#>
param(
    [switch]$DownloadMissing
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$BinDir = Join-Path $RepoRoot "tools\bin"
New-Item -ItemType Directory -Path $BinDir -Force | Out-Null

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "=== 0. Checking Administrator Privileges ===" -ForegroundColor Cyan
if ($isAdmin) {
    Write-Host "  [OK] Running with Administrator privileges." -ForegroundColor Green
} else {
    Write-Host "  [WARN] Not running as Administrator! Hardware sensors (PawnIO) and mVolt+ require Admin rights." -ForegroundColor Yellow
}

Write-Host "`n=== 1. Checking .NET SDK & .NET 10 Runtime ===" -ForegroundColor Cyan
$hasSdk = (Get-Command dotnet -ErrorAction SilentlyContinue) -and ((dotnet --list-sdks 2>$null) -match "^(8|9|10)\.")
$hasNet10 = (Get-Command dotnet -ErrorAction SilentlyContinue) -and ((dotnet --list-runtimes 2>$null) -match "Microsoft\.NETCore\.App 10\.")

if (-not $hasSdk -and $DownloadMissing) {
    Write-Host "  Installing .NET 8 SDK via winget..."
    winget install --id Microsoft.DotNet.SDK.8 -e --accept-source-agreements --accept-package-agreements
}
if (-not $hasNet10 -and $DownloadMissing) {
    Write-Host "  Installing .NET 10 Desktop Runtime via winget..."
    winget install --id Microsoft.DotNet.DesktopRuntime.10 -e --accept-source-agreements --accept-package-agreements
}
if ($hasSdk) { Write-Host "  [OK] .NET 8+ SDK found." -ForegroundColor Green }
else { Write-Host "  [WARN] .NET 8+ SDK not found (SensorCli cannot be built). Re-run with -DownloadMissing." -ForegroundColor Yellow }
if ($hasNet10) { Write-Host "  [OK] .NET 10 Runtime found." -ForegroundColor Green }
else { Write-Host "  [WARN] .NET 10 Runtime not found (needed to load newer LibreHardwareMonitorLib builds). Re-run with -DownloadMissing." -ForegroundColor Yellow }

Write-Host "`n=== 2. Checking LibreHardwareMonitorLib + PawnIO & Building SensorCli ===" -ForegroundColor Cyan
$fcDirs = @(
    "C:\Program Files (x86)\FanControl",
    "C:\Program Files\FanControl"
)
$fcDir = $fcDirs | Where-Object { Test-Path "$_\LibreHardwareMonitorLib.dll" } | Select-Object -First 1
$lhmLocalDir = Join-Path $BinDir "lhm"

if (-not $fcDir -and $DownloadMissing) {
    Write-Host "  Installing FanControl + PawnIO via winget for VBS-compatible hardware telemetry..."
    winget install --id Rem0o.FanControl -e --accept-source-agreements --accept-package-agreements
    $fcDir = $fcDirs | Where-Object { Test-Path "$_\LibreHardwareMonitorLib.dll" } | Select-Object -First 1
}

if ($fcDir) {
    New-Item -ItemType Directory -Path $lhmLocalDir -Force | Out-Null
    Copy-Item "$fcDir\*.dll" $lhmLocalDir -Force
    Write-Host "  [OK] Copied VBS-compatible LibreHardwareMonitorLib.dll to tools\bin\lhm" -ForegroundColor Green
} else {
    Write-Host "  [WARN] LibreHardwareMonitorLib.dll not found. Run with -DownloadMissing or install Rem0o.FanControl." -ForegroundColor Yellow
}

$sensorProj = Join-Path $RepoRoot "tools\SensorCli\SensorCli.csproj"
if (Test-Path $sensorProj) {
    dotnet build $sensorProj -c Release --nologo -v q
    Write-Host "  [OK] Built SensorCli.exe successfully." -ForegroundColor Green
}

Write-Host "`n=== 3. Checking mVolt+ (NVIDIA GPU Tuner) ===" -ForegroundColor Cyan
$mvoltPaths = @(
    (Join-Path $BinDir "mVolt+.exe"),
    "C:\Program Files\mVolt+\mVolt+.exe"
)
$mvoltExe = $mvoltPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $mvoltExe -and $DownloadMissing) {
    Write-Host "  Downloading latest mVolt+ release from GitHub (b00nz/mVolt)..."
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/b00nz/mVolt/releases/latest"
    $asset = $rel.assets | Where-Object { $_.name -match "\.exe$|\.zip$" } | Select-Object -First 1
    if ($asset) {
        $dest = Join-Path $BinDir $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dest
        if ($dest -match "\.zip$") {
            Expand-Archive -Path $dest -DestinationPath $BinDir -Force
        }
        $mvoltExe = Join-Path $BinDir "mVolt+.exe"
    }
}
if ($mvoltExe -and (Test-Path $mvoltExe)) {
    if ($mvoltExe -ne (Join-Path $BinDir "mVolt+.exe")) {
        Copy-Item $mvoltExe (Join-Path $BinDir "mVolt+.exe") -Force
    }
    Write-Host "  [OK] mVolt+ ready at: $(Join-Path $BinDir 'mVolt+.exe')" -ForegroundColor Green
} else {
    Write-Host "  [WARN] mVolt+.exe not found. Re-run with -DownloadMissing or download from https://github.com/b00nz/mVolt" -ForegroundColor Yellow
}

Write-Host "`n=== 4. Checking FurMark 2 CLI (GPU Benchmark & Artifact Scanner) ===" -ForegroundColor Cyan
$fmPaths = @(
    $env:FURMARK_EXE,
    (Join-Path $BinDir "FurMark2\{app}\furmark.exe"),
    (Join-Path $BinDir "FurMark2\furmark.exe"),
    "C:\Program Files\Geeks3D\FurMark2_x64\furmark.exe",
    "C:\Program Files (x86)\Geeks3D\FurMark2_x64\furmark.exe"
)
$fmExe = $fmPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $fmExe -and $DownloadMissing) {
    Write-Host "  Installing Geeks3D FurMark 2 via winget..."
    winget install --id Geeks3D.FurMark.2 -e --accept-source-agreements --accept-package-agreements
    $fmExe = $fmPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}
if ($fmExe) {
    Write-Host "  [OK] FurMark 2 CLI found at: $fmExe" -ForegroundColor Green
} else {
    Write-Host "  [WARN] FurMark 2 not found. Run with -DownloadMissing or install Geeks3D.FurMark.2 via winget." -ForegroundColor Yellow
}
