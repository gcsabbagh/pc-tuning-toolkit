<#
.SYNOPSIS
    Applies the verified Option B "SmartHighPerf" CPU Power Plan settings for Intel i7-13700K:
    - Core Parking 100% Disabled (CPMINCORES = 100%, CPMINCORES1 = 100%)
    - Minimum Processor State = 5%, Speed Shift EPP = 60% (drops idle power from 67W -> 22.5W, 0.83V, 36°C)
#>
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
& (Join-Path $RepoRoot "scripts\Manage-CpuPowerPlan.ps1") -Action ApplySmartHighPerf
