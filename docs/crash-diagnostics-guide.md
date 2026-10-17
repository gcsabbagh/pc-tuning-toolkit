# Crash Diagnostics & Event Log Forensics Guide

When a user says *"My game just crashed—was it my GPU, CPU, RAM, or the game itself?"*, run [`scripts/Diagnose-Crashes.ps1`](../scripts/Diagnose-Crashes.ps1) and match the Windows Event Log signatures below.

---

## 1. Crash Signature Matrix

| Source / Provider | Event ID | Signature / Error Code | Root Cause & Tuning Fix |
| :--- | :--- | :--- | :--- |
| **`nvlddmkm`** (System Log) | `153`, `14`, `13` | `Error occurred on GPUID: 100` / `Graphics Exception: ESR ...` | **NVIDIA GPU Core / XBar / V-F Curve Instability.** The GPU core or crossbar clock exceeded voltage stability during a load/boost transition. **Fix:** Lower `--core` by `15–30 MHz` or replace a manual MSI Afterburner per-point V/F curve with `mVolt+` whole-curve offset. |
| **`Display`** (System Log) | `4101` | `Display driver nvlddmkm stopped responding and has successfully recovered.` | **Windows GPU TDR (Timeout Detection & Recovery).** GPU hung for >2 seconds. Almost always accompanied by `nvlddmkm` ID `153`/`14` or `LiveKernelEvent 141`. **Fix:** Reduce GPU Core/XBar offset by `15–30 MHz` and VRAM by `150–200 MHz`. |
| **`Windows Error Reporting`** (App Log) | `1001` | `LiveKernelEvent` Code **`141`** or **`117`** | **Hardware GPU Hang / TDR.** Code `141` = TDR recovery; Code `117` = TDR failed to recover (often black screen). **Fix:** Back off GPU Core/VRAM overclock. |
| **Game Crash Log / App Error** | `1000` | `0x887A0006` (`DXGI_ERROR_DEVICE_HUNG`) or `0x887A0007` (`DEVICE_RESET`) | **GPU Driver Reset mid-frame.** In DX11/DX12/UE5 games, `DEVICE_HUNG` means either an unstable GPU Core/VRAM overclock OR a game shader bug. Check if `nvlddmkm` logged an error at the exact same timestamp: if `nvlddmkm` is present, it is a hardware OC crash; if `nvlddmkm` is completely silent (`0` events), it is likely an engine/game bug. |
| **`WHEA-Logger`** (System Log) | `18`, `19` | `Cache Hierarchy Error` / `Bus/Interconnect Error` (`APIC ID: X`) | **CPU Undervolt / Curve Optimizer or Infinity Fabric (`FCLK`) Instability.**<br>• **Cache Hierarchy Error (ID 18):** Core `APIC ID X` starved for voltage (usually during light-load or idle transition when AMD Curve Optimizer negative offset is too aggressive, e.g. `-30` to `-35`, or Intel Vcore offset is too negative). **Fix:** Make Curve Optimizer less negative by `+5` to `+10` on that core.<br>• **Bus/Interconnect Error (ID 19):** AMD Infinity Fabric (`FCLK`) or PCIe/SoC instability. **Fix:** Lower `FCLK` by `33–67 MHz` (e.g. `2133 -> 2067/2000 MHz`) or adjust `VSOC`. |
| **`Application Error`** (App Log) | `1000` | Exception `0xc0000005` (`ACCESS_VIOLATION`) with `0` `nvlddmkm` and `0` `WHEA` events | **Memory (DDR5) instability OR Game Software Bug.**<br>• If it happens across multiple games or when DDR5 DIMM temps exceed `55°C`: test RAM stability and check `UCLK/MCLK` & DIMM thermals.<br>• If isolated to a single game with DIMMs at `40°C` and `0` hardware events: game software bug. |
| **`Kernel-Power`** (System Log) | `41` | `The system has rebooted without cleanly shutting down first.` | **Instant Reset / BSOD:** Caused by severe CPU Vmin starvation (aggressive CO undervolt on idle transition), PSU OCP trip, or unstable RAM. Inspect the preceding `BugCheck` (`Event ID 1001`) and `WHEA-Logger` events. |

---

## 2. How to Distinguish a GPU OC Crash from a Game Bug

Always correlate the **exact timestamp** of the game exit with the `System` Event Log:
1. Run `.\scripts\Diagnose-Crashes.ps1 -HoursBack 2`.
2. **Case A — Hardware GPU OC Instability:**
   - Within 1–5 seconds of the game crash, `System` log shows `nvlddmkm` (`Event ID 153` or `14`) or `Display` (`Event ID 4101`), or `Application` log shows `LiveKernelEvent 141`.
   - **Action:** The GPU overclock was unstable at the boost bin reached during that scene. Reduce `--core` by `15–30 MHz` and `--xbar-offset` by `30 MHz`.
3. **Case B — Clean Hardware / Game Engine Bug:**
   - `System` log has **zero** `nvlddmkm`, `Display`, or `WHEA-Logger` events, and `Application` log shows either a clean exit or a pure game-logic exception (`NullReferenceException` / script error).
   - **Action:** Hardware is stable; no downclocking required.
