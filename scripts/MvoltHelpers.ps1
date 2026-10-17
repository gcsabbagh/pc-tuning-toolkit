<#
.SYNOPSIS
    Shared helpers for calling mVolt+.exe from PowerShell. Dot-source this file.

.NOTES
    mVolt+.exe is a GUI-subsystem binary. Invoked bare (`& $mvolt --core 60`), PowerShell
    does NOT wait for it, discards its stdout/stderr, and never sets $LASTEXITCODE, so CLI
    errors (e.g. `{"success":false,"error":"Unknown option ..."}`) are silently lost.
    Piping its output forces PowerShell to wait and capture the exit code.
#>

function Find-Mvolt {
    param([string]$RepoRoot)
    @(
        (Join-Path $RepoRoot "tools\bin\mVolt+.exe"),
        "C:\Program Files\mVolt+\mVolt+.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

function Invoke-Mvolt {
    <# Runs mVolt+ synchronously, echoes its output, and throws on a non-zero exit code.
       Usage: Invoke-Mvolt $mvolt @("--core", 60, "--mem", 1000) #>
    param(
        [Parameter(Mandatory, Position = 0)][string]$MvoltPath,
        [Parameter(Mandatory, Position = 1)][object[]]$Arguments
    )
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"   # stderr lines must not become terminating errors
    try {
        $out = & $MvoltPath @Arguments 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
    if ($out) { $out | ForEach-Object { Write-Host "  [mVolt+] $_" } }
    if ($code -ne 0) {
        throw "mVolt+ $($Arguments -join ' ') failed (exit code $code): $($out -join ' ')"
    }
}

function Get-MvoltStatus {
    <# Returns the parsed `mVolt+ --status` JSON object, or $null if unavailable. #>
    param([Parameter(Mandatory)][string]$MvoltPath)
    $json = & $MvoltPath --status 2>$null | Out-String
    if ($LASTEXITCODE -ne 0 -or -not $json.Trim()) { return $null }
    try { return $json | ConvertFrom-Json } catch { return $null }
}

function Show-MvoltStatus {
    <# Prints a one-line summary of the current GPU tuning state and returns the status object. #>
    param([Parameter(Mandatory)][string]$MvoltPath)
    $st = Get-MvoltStatus -MvoltPath $MvoltPath
    if (-not $st) { Write-Warning "Could not read 'mVolt+ --status'."; return $null }
    Write-Host ("GPU: {0} | Profile: {1} | Power: {2}% ({3} W enforced) | Core: {4:+0;-0;0} MHz | XBar: {5:+0;-0;0} MHz | Mem: {6:+0;-0;0} MHz" -f `
        $st.gpu, $st.active_profile, $st.power_limit_percent, ($st.power_limits.enforced_mw / 1000),
        $st.core_offset_mhz, $st.xbar_offset_mhz, $st.memory_offset_mhz) -ForegroundColor Cyan
    return $st
}
