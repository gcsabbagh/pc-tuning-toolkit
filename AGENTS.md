# AGENTS.md — Autonomous AI Agent Playbook for PC Tuning

Welcome, Agent. This repository is an **Agentic PC Tuning & Stability Toolkit** designed to let an AI coding assistant safely inspect, diagnose, benchmark, and optimize a user's **GPU, CPU, RAM, and OS Scheduler** with **100% multiplayer gaming stability** as the primary objective.

---

## 1. Golden Rules & Safety Guardrails

1. **Multiplayer Gaming Stability > Synthetic Peak Scores:**
   - A 1% synthetic benchmark gain is worthless if a game crashes (`nvlddmkm` Event ID 153/14 or `WHEA-Logger` Event ID 18) 90 minutes into a multiplayer match with friends.
   - Always leave a **15–30 MHz safety buffer** below the synthetic benchmark instability point on GPU Core/XBar, and a **150–250 MHz buffer** on GDDR6X/GDDR7 VRAM.
2. **Never Bypass Hardware Silicon Protection Limits:**
   - **Intel 13th/14th Gen K-Series (`13700K`/`13900K`/`14700K`/`14900K`):** Verify Microcode is `>= 0x12B` / `0x12F`. **Never** exceed Intel Default limits (`PL1/PL2 <= 253W`, `IccMax <= 307A` or `400A` depending on SKU).
   - **AMD Ryzen X3D (`7800X3D` / `9800X3D` / `9850X3D` / `9950X3D`):** **Never** exceed `VSOC = 1.30V` (target `1.18V–1.25V` for DDR5-6000/6400). Use negative **Curve Optimizer (CO)** / **Curve Shaper** offsets rather than fixed manual Vcore.
3. **Always Back Up Before Touching Any Setting:**
   - Back up existing MSI Afterburner profiles (`C:\Program Files (x86)\MSI Afterburner\Profiles`), `mVolt+` profiles (`%LOCALAPPDATA%\mVolt+\profiles`), and Windows Power Plans (`.\scripts\Manage-CpuPowerPlan.ps1 -Action Backup`) before applying any changes.
4. **Prevent Software Conflicts:**
   - Never let **MSI Afterburner** and **mVolt+** fight over the NVIDIA VF curve simultaneously. Clear/neutralize Afterburner's per-point VF curve before tuning with `mVolt+`.

---

## 2. Step-by-Step Agent Workflow

### Phase 1: Bootstrap & Privilege Check
1. Verify if your shell is running with **Administrator privileges**:
   ```powershell
   ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
   ```
   - *If `False`:* Ask the user to relaunch the agent/IDE as Administrator, or use an elevated scheduled task / UAC prompt (`Start-Process powershell -Verb RunAs`). Hardware telemetry (`PawnIO` / `LibreHardwareMonitorLib`) and `mVolt+` require Administrator rights.
2. Run the bootstrap script to ensure `.NET 8+ SDK`, `.NET 10 Runtime`, `LibreHardwareMonitorLib.dll` (`PawnIO`), `mVolt+.exe`, `SensorCli.exe`, and `FurMark 2` are ready (see [`docs/prerequisites-and-setup.md`](docs/prerequisites-and-setup.md) for full details):
   ```powershell
   .\scripts\Bootstrap-Tools.ps1 -DownloadMissing
   ```

### Phase 2: Hardware Discovery & Crash Forensics
1. Inspect the system hardware, BIOS, microcode/AGESA, VBS status, RAM XMP/EXPO, and GPU VBIOS:
   ```powershell
   .\scripts\Inspect-System.ps1
   ```
2. Scan Windows Event Logs for recent GPU TDRs, DirectX crashes, or CPU/RAM WHEA hardware errors:
   ```powershell
   .\scripts\Diagnose-Crashes.ps1 -HoursBack 72
   ```
   - Consult [`docs/crash-diagnostics-guide.md`](docs/crash-diagnostics-guide.md) to interpret any findings.

### Phase 3: Baseline Telemetry & Stress Testing
1. **GPU Baseline:** Reset GPU to factory stock (`-ResetToDefault` writes 0 offsets + 100% power via mVolt+ and verifies with `--status`; mVolt+ has no `--reset` flag) and run a 20-second FurMark 2 Vulkan Knot benchmark with the artifact scanner enabled:
   ```powershell
   .\scripts\Run-GpuBenchmark.ps1 -Label "baseline" -ResetToDefault
   ```
2. **CPU & Thermal Baseline:** Run the native multi-threaded Scalar + AVX2+FMA stress test in `SensorCli.exe`:
   ```powershell
   .\tools\SensorCli\bin\Release\net8.0\SensorCli.exe --stress 18
   ```
   - Check idle vs. load **Package Power (W)**, **Vcore / VSOC (V)**, **Core & Package Temperatures (°C)**, **Per-Core Boost Clocks (MHz)**, and **DDR5 DIMM Temperatures (°C)**.

### Phase 4: Iterative GPU & CPU Tuning
1. Follow [`docs/gpu-tuning-guide.md`](docs/gpu-tuning-guide.md) to tune the GPU via `mVolt+` (Power Limit $\rightarrow$ VRAM ECC sweet spot $\rightarrow$ Core & Crossbar `XBar` sweep $\rightarrow$ back off to the Rock-Solid Gaming profile).
2. Follow [`docs/cpu-tuning-guide.md`](docs/cpu-tuning-guide.md) to optimize CPU power management (`.\scripts\Manage-CpuPowerPlan.ps1 -Action ApplySmartHighPerf`), Process Lasso hybrid/CCD affinities, and BIOS PBO Curve Optimizer / undervolt recommendations.

### Phase 5: Persistence & Real-World Gaming Validation
1. To launch `mVolt+.exe` on the user's interactive desktop so they can save the profile and toggle **Start with Windows**, use:
   ```powershell
   .\scripts\Launch-InteractiveGui.ps1 -ExecutablePath "$PWD\tools\bin\mVolt+.exe"
   ```
   *(Never use plain `Start-Process` for GUI apps if your agent shell runs in a detached/non-interactive session—the window will be invisible to the user!)*
2. After the user plays a real multiplayer session (30–90 minutes), run `.\scripts\Diagnose-Crashes.ps1 -HoursBack 3` to confirm `0` driver resets, `0` WHEA errors, and `0` application faults.
3. Document the hardware, baseline, tuning steps, and final profile in `docs/case-studies/` and `profiles/<hardware-slug>/`.

---

## 3. Modifying Scripts & Running Regression Smoke Tests

Whenever you modify any PowerShell script in [`scripts/`](scripts/), profile script in [`profiles/`](profiles/), or C# code in [`tools/SensorCli/`](tools/SensorCli/), always run the non-destructive smoke test suite before finishing (see [`docs/testing-and-verification.md`](docs/testing-and-verification.md) for full details):

```powershell
# Full verification (AST syntax + static guards + SensorCli build + live read-only telemetry)
.\tests\Invoke-SmokeTests.ps1

# Static-only verification (if running without Admin rights or supported hardware)
.\tests\Invoke-SmokeTests.ps1 -SkipHardwareTests
```

