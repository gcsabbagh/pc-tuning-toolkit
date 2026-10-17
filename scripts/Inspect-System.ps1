<#
.SYNOPSIS
    Hardware & OS Discovery Script for AI Agents.
    Detects CPU (Intel Hybrid vs AMD Ryzen X3D), BIOS & Microcode/AGESA, VBS status,
    DDR5 configuration, GPU VBIOS/TGP limits, active Power Scheme, and running tuning software.
#>

$ErrorActionPreference = "SilentlyContinue"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$BinDir = Join-Path $RepoRoot "tools\bin"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "================ SYSTEM & HARDWARE INSPECTION ================" -ForegroundColor Cyan
Write-Host "Running as Administrator : $isAdmin"

# 1. CPU & Microcode
$cpu = Get-CimInstance Win32_Processor
$board = Get-CimInstance Win32_BaseBoard
$bios = Get-CimInstance Win32_BIOS
$regCpu = Get-ItemProperty "HKLM:\HARDWARE\Description\System\CentralProcessor\0"
# 'Update Revision' is an 8-byte REG_BINARY; the revision is the little-endian DWORD in bytes 4-7
# (e.g. bytes 00 00 00 00 2F 01 00 00 => 0x12F).
$ucodeRaw = [byte[]]$regCpu.'Update Revision'
$ucodeRev = if ($ucodeRaw -and $ucodeRaw.Length -ge 8) { [BitConverter]::ToUInt32($ucodeRaw, 4) } else { $null }
$ucode = if ($null -ne $ucodeRev) { "0x{0:X}" -f $ucodeRev } else { "unknown" }

Write-Host "`n--- CPU & MOTHERBOARD ---" -ForegroundColor Yellow
Write-Host "CPU Name                 : $($cpu.Name)"
Write-Host "Cores / Logical Threads  : $($cpu.NumberOfCores) Cores / $($cpu.NumberOfLogicalProcessors) Threads"
Write-Host "Max Clock Speed (Spec)   : $($cpu.MaxClockSpeed) MHz"
Write-Host "Microcode Revision       : $ucode"
Write-Host "Motherboard              : $($board.Manufacturer) $($board.Product)"
Write-Host "BIOS Version & Date      : $($bios.SMBIOSBIOSVersion) ($($bios.ReleaseDate.ToString('yyyy-MM-dd')))"

# Architecture Classification
if ($cpu.Name -match "X3D") {
    Write-Host "Architecture Profile     : AMD Ryzen 3D V-Cache (X3D) -- Prioritize Curve Optimizer (CO), VSOC <= 1.25V, DDR5 6000-6400 1:1 UCLK=MCLK" -ForegroundColor Green
} elseif ($cpu.Name -match "13th Gen|14th Gen") {
    Write-Host "Architecture Profile     : Intel 13th/14th Gen Hybrid (Raptor Lake) -- Verify Microcode >= 0x12B/0x12F, PL1/PL2 <= 253W, IccMax <= 307A" -ForegroundColor Green
    if ($null -eq $ucodeRev) {
        Write-Host "  [WARN] Could not read microcode revision; verify manually before any tuning." -ForegroundColor Yellow
    } elseif ($ucodeRev -lt 0x12B) {
        Write-Host "  [DANGER] Microcode $ucode is below 0x12B (Vmin Shift fix). Update BIOS BEFORE any tuning." -ForegroundColor Red
    } else {
        Write-Host "  [OK] Microcode $ucode includes the Vmin Shift mitigation (>= 0x12B)." -ForegroundColor Green
    }
}

# 2. Windows VBS / HVCI Status
$dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard
Write-Host "`n--- VIRTUALIZATION-BASED SECURITY (VBS) ---" -ForegroundColor Yellow
Write-Host "VBS Status               : $($dg.VirtualizationBasedSecurityStatus) (0=Off, 1=Configured, 2=Running)"
if ($dg.VirtualizationBasedSecurityStatus -eq 2) {
    Write-Host "  [NOTE] VBS is RUNNING: OS-level CPU voltage offset writes (XTU/ThrottleStop/Ryzen Master) are blocked by Windows Hypervisor. Use SensorCli (PawnIO) for telemetry and BIOS for Curve Optimizer / Undervolting." -ForegroundColor Gray
}

# 3. Memory (RAM)
Write-Host "`n--- MEMORY (RAM) ---" -ForegroundColor Yellow
Write-Host ((Get-CimInstance Win32_PhysicalMemory | Select-Object BankLabel, Manufacturer, PartNumber, @{N="CapacityGB";E={$_.Capacity/1GB}}, ConfiguredClockSpeed, ConfiguredVoltage | Format-Table -AutoSize | Out-String).Trim())

# 4. GPU Inspection (nvidia-smi + mVolt+)
Write-Host "`n--- GPU & VBIOS TELEMETRY ---" -ForegroundColor Yellow
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    Write-Host ((nvidia-smi --query-gpu=name,vbios_version,driver_version,power.default_limit,power.max_limit,clocks.max.graphics,clocks.max.memory --format=csv | Out-String).Trim())
}
. (Join-Path $PSScriptRoot "MvoltHelpers.ps1")
$mvolt = Find-Mvolt -RepoRoot $RepoRoot
if ($mvolt) {
    Write-Host "`n[mVolt+ --status]" -ForegroundColor Cyan
    [void](Show-MvoltStatus -MvoltPath $mvolt)
}

# 5. Active Power Plan & Tuning Processes
Write-Host "`n--- POWER PLAN & ACTIVE TUNING UTILITIES ---" -ForegroundColor Yellow
Write-Host ((powercfg /getactivescheme | Out-String).Trim())
Write-Host ((Get-Process | Where-Object { $_.Name -match "mvolt|afterburner|rtss|processlasso|parkcontrol|xtu|ryzen|fancontrol|hwinfo|lhm" } | Select-Object Name, Id, Path | Format-Table -AutoSize | Out-String).Trim())
