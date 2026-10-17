<#
.SYNOPSIS
    Applies the verified "Gemini v1.0" Rock-Solid Multiplayer Gaming GPU Profile
    for the Gigabyte GeForce RTX 4080 (VBIOS 95.03.2b.40.3b) via mVolt+.
    - Power Cap : 400 W (117% VBIOS Maximum)
    - Core      : +60 MHz Dynamic Offset (Default Clock Range)
    - XBar      : +120 MHz Crossbar L2 Interconnect Offset
    - Memory    : +1000 MHz GDDR6X (12,201 MHz / 24.4 Gbps effective)
#>
param(
    [switch]$DryRun,
    [switch]$SkipGpuCheck
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# 1. Require Administrator privileges (NVAPI clock/power writes fail without elevation)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Apply-Gemini-v1.0-4080.ps1 must be run as Administrator."
    exit 1
}

# 2. Locate mVolt+ and verify it actually exists
. (Join-Path $RepoRoot "scripts\MvoltHelpers.ps1")
$mvolt = Find-Mvolt -RepoRoot $RepoRoot
if (-not $mvolt) {
    Write-Error "mVolt+.exe not found in tools\bin or C:\Program Files\mVolt+. Run .\scripts\Bootstrap-Tools.ps1 -DownloadMissing first."
    exit 1
}

# 3. Make sure this profile is only applied to the GPU it was validated on
if (-not $SkipGpuCheck) {
    $gpus = Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name
    if (-not ($gpus -match "RTX 4080")) {
        Write-Error ("This profile was validated on an RTX 4080 only. Detected GPU(s): " + ($gpus -join ", ") + ". Use -SkipGpuCheck to override.")
        exit 1
    }
}

$mArgs = @("--power-cap-watts", 400, "--core", 60, "--clock-range", "default", "--xbar-offset", 120, "--mem", 1000)
Write-Host "mVolt+: $mvolt" -ForegroundColor Cyan
Write-Host "Command: mVolt+ $($mArgs -join ' ')" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "Current state:" -ForegroundColor Gray
    [void](Show-MvoltStatus -MvoltPath $mvolt)
    Write-Host "[DRY RUN] All checks passed; no settings applied." -ForegroundColor Yellow
    exit 0
}

try {
    Invoke-Mvolt $mvolt $mArgs
} catch {
    Write-Error $_
    exit 1
}
Start-Sleep -Seconds 1
$st = Show-MvoltStatus -MvoltPath $mvolt
if ($st -and ($st.core_offset_mhz -ne 60 -or $st.xbar_offset_mhz -ne 120 -or $st.memory_offset_mhz -ne 1000 -or $st.power_limits.enforced_mw -ne 400000)) {
    Write-Error "Applied values do not match the Gemini v1.0 profile; check mVolt+."
    exit 1
}
Write-Host "[OK] Gemini v1.0 applied and verified." -ForegroundColor Green
