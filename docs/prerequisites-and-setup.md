# Prerequisites, Libraries & Tool Setup Guide

This document lists every runtime, kernel driver, library, and benchmarking tool used by the **Agentic PC Tuning & Stability Toolkit**, why each one is needed, and how to install them automatically or manually on a fresh Windows 11/10 PC.

---

## 1. Complete Dependency Matrix

| Component / Tool | Required? | Purpose in Toolkit | Source / `winget` ID |
| :--- | :--- | :--- | :--- |
| **Administrator Privileges** | **Yes** | Required to read ring-0 CPU/motherboard/DDR5 sensors (`PawnIO`) and apply NVAPI GPU clock/power offsets (`mVolt+`). | Launch IDE / PowerShell with **Run as Administrator** |
| **.NET 8 SDK + .NET 10 Runtime** | **Yes** | Compiles and executes [`tools/SensorCli/SensorCli.csproj`](../tools/SensorCli/SensorCli.csproj) (`dotnet build` + `.NET 10` runtime roll-forward for `LibreHardwareMonitorLib.dll`). | `winget install Microsoft.DotNet.SDK.8`<br>`winget install Microsoft.DotNet.DesktopRuntime.10` |
| **FanControl (`LibreHardwareMonitorLib.dll` + `PawnIO`)** | **Yes** | Provides the VBS-compatible **`PawnIO` kernel driver** and `LibreHardwareMonitorLib.dll` (`v0.9.6+`). Unlike older `WinRing0` tools that Windows Defender / VBS blocks, `PawnIO` works with **Memory Integrity (HVCI / VBS) ON** to read Intel & AMD Ryzen X3D per-core temps, clocks, `Vcore`/`VSOC`, Package Power, and DDR5 DIMM temps. | `winget install Rem0o.FanControl` |
| **`mVolt+` (`v0.50.4+`)** | **Yes (NVIDIA)** | Lightweight NVAPI CLI + GUI tuner for NVIDIA RTX 30/40/50-series GPUs. Gives programmatic CLI control over Power Cap (`--power-cap-watts`), Core offset (`--core`), Crossbar L2 interconnect offset (`--xbar-offset`), and GDDR6X/GDDR7 Memory offset (`--mem`). | GitHub: [`b00nz/mVolt`](https://github.com/b00nz/mVolt/releases/latest) *(Auto-downloaded by `Bootstrap-Tools.ps1`)* |
| **FurMark 2 (`v2.10+` x64)** | **Yes (GPU Bench)** | Provides a fully scriptable Vulkan CLI benchmark (`furmark.exe --demo furmark-vk --benchmark`) with a built-in **real-time GPU Artifact Scanner (`--artifact-scanner`)** and per-second CSV sensor logger (`--log-gpu-data`). | `winget install Geeks3D.FurMark.2` *(or portable extraction via `Bootstrap-Tools.ps1`)* |
| **NVIDIA Driver (`nvidia-smi`)** | **Yes (NVIDIA)** | Included with standard NVIDIA Game Ready / Studio drivers (`C:\Windows\System32\nvidia-smi.exe`). Used to query VBIOS versions and default/max power limits. | Included with NVIDIA Display Driver |
| **OCCT Personal** | *Optional* | Useful for extended per-core AMD Curve Optimizer (CO) core-cycling validation and 3D Adaptive transient tests. | `winget install OCBase.OCCT.Personal` |
| **Process Lasso** | *Optional* | Used to pin background apps (`discord.exe`, browsers, OBS) to Intel E-cores or AMD secondary CCDs while keeping games on primary P-cores / 3D V-Cache CCDs. | `winget install Bitsum.ProcessLasso` |

---

## 2. One-Command Automated Setup (Recommended)

On a brand-new PC, open **PowerShell as Administrator** inside the repository root and run:

```powershell
.\scripts\Bootstrap-Tools.ps1 -DownloadMissing
```

### What `Bootstrap-Tools.ps1 -DownloadMissing` Does Automatically:
1. **Verifies Administrator Rights:** Warns immediately if the terminal is not elevated.
2. **Checks `.NET SDK` & `.NET 10 Runtime`:** Installs `Microsoft.DotNet.SDK.8` and `Microsoft.DotNet.DesktopRuntime.10` via `winget` if missing.
3. **Checks `LibreHardwareMonitorLib.dll` + `PawnIO`:**
   - Looks for `C:\Program Files (x86)\FanControl\LibreHardwareMonitorLib.dll` (and `PawnIO`).
   - If missing, installs `Rem0o.FanControl` via `winget` and copies the required `.dll` dependencies into `tools\bin\lhm\`.
4. **Builds `SensorCli.exe`:** Compiles [`tools/SensorCli/SensorCli.csproj`](../tools/SensorCli/SensorCli.csproj) in `Release` mode and runs a 1-second sensor sanity check.
5. **Downloads `mVolt+.exe`:** Queries the GitHub Releases API for `b00nz/mVolt` and downloads `mVolt+.exe` directly into `tools\bin\mVolt+.exe`.
6. **Checks / Installs `FurMark 2`:** Checks standard install paths (`C:\Program Files\Geeks3D\FurMark2_x64\furmark.exe` or `tools\bin\FurMark2`) and installs `Geeks3D.FurMark.2` via `winget` if missing.

### Verify Your Setup with the Smoke Test Suite
After bootstrapping, run the non-destructive smoke test suite (see [`docs/testing-and-verification.md`](testing-and-verification.md)) to confirm all scripts, tools, and hardware telemetry readers work end-to-end:

```powershell
.\tests\Invoke-SmokeTests.ps1
```

---

## 3. Manual Installation Commands (Fallback)

If you prefer to install each prerequisite manually via `winget` before starting an AI agent session, run:

```powershell
# 1. Runtimes for SensorCli (Telemetry & CPU Stress Tester)
winget install --id Microsoft.DotNet.SDK.8 -e --accept-source-agreements --accept-package-agreements
winget install --id Microsoft.DotNet.DesktopRuntime.10 -e --accept-source-agreements --accept-package-agreements

# 2. VBS-Compatible Hardware Sensor Library & PawnIO Driver
winget install --id Rem0o.FanControl -e --accept-source-agreements --accept-package-agreements

# 3. GPU Benchmark & Artifact Scanner
winget install --id Geeks3D.FurMark.2 -e --accept-source-agreements --accept-package-agreements

# 4. (Optional) System Stability & Thread Affinity Utilities
winget install --id OCBase.OCCT.Personal -e --accept-source-agreements --accept-package-agreements
winget install --id Bitsum.ProcessLasso -e --accept-source-agreements --accept-package-agreements
```

---

## 4. Troubleshooting Common Setup Issues

### Q1: `SensorCli.exe` reports `0` for CPU temperatures or voltages
* **Cause:** Either the terminal is **not running as Administrator**, or the **`PawnIO` driver** is not installed while Windows Virtualization-Based Security (VBS / Memory Integrity) is enabled.
* **Fix:**
  1. Ensure your terminal / AI IDE is launched with **Run as Administrator**.
  2. Confirm `PawnIO` is installed (`C:\Program Files\PawnIO` — installed automatically with recent versions of `FanControl`, or via `winget install Namazso.PawnIO`).

### Q2: `SensorCli` fails to build or fails to load `System.Runtime, Version=10.0.0.0`
* **Cause:** FanControl's bundled `LibreHardwareMonitorLib.dll` targets `.NET 10.0`.
* **Fix:** Install the `.NET 10 Desktop Runtime` (`winget install Microsoft.DotNet.DesktopRuntime.10`). [`SensorCli.csproj`](../tools/SensorCli/SensorCli.csproj) uses `<RollForward>LatestMajor</RollForward>` + dynamic `AssemblyLoadContext` resolution so it compiles with `.NET 8+ SDK` and runs seamlessly on `.NET 10`.

### Q3: `mVolt+.exe` GUI doesn't appear when launched by an AI Agent
* **Cause:** Many AI coding agents execute terminal commands inside a background service or non-interactive session, so `Start-Process mVolt+.exe` spawns a window on a hidden session.
* **Fix:** Always use [`scripts/Launch-InteractiveGui.ps1`](../scripts/Launch-InteractiveGui.ps1) to launch GUI tools onto the user's active desktop session:
  ```powershell
  .\scripts\Launch-InteractiveGui.ps1 -ExecutablePath "$PWD\tools\bin\mVolt+.exe"
  ```
