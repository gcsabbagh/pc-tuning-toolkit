# Applies the verified Option B "Smart High-Performance" Power Plan for Intel Core i7-13700K
# Keeps all 24 threads 100% unparked while lowering idle power from 67W -> 22W (0.83V, 36C) via Speed Shift EPP 60%
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
& (Join-Path $RepoRoot "scripts\Manage-CpuPowerPlan.ps1") -Action ApplySmartHighPerf
