# NVIDIA GPU Tuning Playbook (RTX 40-Series Ada & RTX 50-Series Blackwell)

This guide covers safe, high-stability GPU optimization using **`mVolt+`** (`b00nz/mVolt`) for **NVIDIA GeForce RTX 40-Series (Ada Lovelace, e.g., RTX 4080 / 4090)** and **RTX 50-Series (Blackwell, e.g., RTX 5080 / 5090)**.

---

## 1. Why We Use `mVolt+` Instead of MSI Afterburner Per-Point Curves

1. **The MSI Afterburner Per-Point V/F Curve Trap:**
   - In MSI Afterburner (`Venom` profiles), editing the Voltage/Frequency curve locks a manual frequency offset to each individual voltage point (`800 mV` to `1,150 mV`) and flattens the tail.
   - As GPU drivers update or ambient temperatures shift, a manual per-point curve often leaves **intermediate transition bins (`950–1,035 mV`) under-volted by 15–25 mV** for the requested clock speed. During rapid DX12/UE5 load transitions, the GPU crosses one of those starved intermediate points and immediately triggers an **`nvlddmkm` Event ID 153 / 14 TDR crash**.
2. **Why `mVolt+` Dynamic Offset + Crossbar Tuning Wins:**
   - **Native NVAPI Whole-Curve Offset (`--core <MHz> --clock-range default`):** Shifts the factory VBIOS boost curve uniformly while allowing NVIDIA GPU Boost to dynamically manage per-bin voltage safety and thermal compensation.
   - **Dedicated Crossbar (`XBar`) Domain Control (`--xbar-offset <MHz>`):** Modern NVIDIA GPUs have a separate **Crossbar (`XBar` / L2 interconnect)** clock domain that connects GPCs (Graphics Processing Clusters) to the L2 cache and memory controllers. Boosting `XBar` (`+90` to `+150 MHz`) improves L2 cache bandwidth and 1% low frame times without requiring unstable shader core clocks.
   - **Full CLI Automation:** Agents can query `--status` (JSON), apply offsets, and reset to defaults (`Run-GpuBenchmark.ps1 -ResetToDefault`) cleanly from PowerShell.
   - **PowerShell gotcha:** `mVolt+.exe` is a GUI-subsystem binary. Called bare, PowerShell does not wait for it and silently drops its output and exit code (including `{"success":false,...}` errors). Always pipe its output (e.g. `& $mvolt --status | Out-String`) or use `Invoke-Mvolt` from [`scripts/MvoltHelpers.ps1`](../scripts/MvoltHelpers.ps1).

---

## 2. Architecture-Specific Reference Targets

### A. NVIDIA GeForce RTX 4080 / 4080 Super (Ada Lovelace — `AD103`, GDDR6X)
* **Stock TGP / Max TGP:** Typically `320W` default / `350W–400W` max (`110%–125%` depending on VBIOS; Gigabyte Gaming OC / Aero / Eagle OC VBIOS `95.03.2b.40.3b` supports **`400W`**).
* **GDDR6X Memory (`22.4 Gbps` / `11,200 MHz` stock):**
  * **Rock-Solid Gaming Sweet Spot:** **`+800` to `+1,000 MHz`** (`24.0–24.4 Gbps` effective, `12,200 MHz` in `mVolt+`).
  * *Warning:* Above `+1,200 MHz`, GDDR6X EDC/ECC error-retry overhead often *reduces* effective FPS or introduces transient hitching even if no visual artifacts appear.
* **Core & Crossbar (`XBar`) Offsets:**
  * **Synthetic Ceiling:** Typically `+90` to `+135 MHz` Core (`~2,880–2,940 MHz` under load) and `+180` to `+210 MHz` `XBar`.
  * **Rock-Solid Multiplayer Target:** **`+50` to `+65 MHz` Core** (`15 MHz` step bins: `+45`, `+60`, `+75`) and **`+105` to `+120 MHz` `XBar`**.
  * **Expected In-Game Boost:** `2,835–2,910 MHz` Core at `1.050–1.075 V` (`60–66°C`).

### B. NVIDIA GeForce RTX 5080 (Blackwell — `GB203`, GDDR7)
* **Stock TGP / Max TGP:** `360W` default / `390W–450W` max (`108%–125%` depending on AIB VBIOS).
* **GDDR7 Memory (`30.0 Gbps` PAM3 signaling stock):**
  * Blackwell's GDDR7 uses **PAM3 (3-level Pulse Amplitude Modulation)** with hardware link ECC.
  * **Benchmark Every Step:** Because GDDR7 silently corrects bit errors via link retries, **never blindly max out the memory slider**. Sweep `--mem` in `+250 MHz` increments (`+500`, `+750`, `+1000`, `+1250`) using [`scripts/Run-GpuBenchmark.ps1`](../scripts/Run-GpuBenchmark.ps1) and stop `250 MHz` below the point where FPS plateaus or regresses.
  * **Rock-Solid Gaming Sweet Spot:** Typically **`+750` to `+1,250 MHz`** on the memory clock offset.
* **Core & Crossbar (`XBar`) Offsets:**
  * Blackwell `GB203` clocks significantly higher out of the box (`2,800–2,950 MHz` stock boost, scaling to **`3,100–3,225 MHz`** tuned).
  * **Step 1 (Baseline):** Check stock boost clock in FurMark 2 Knot (`Run-GpuBenchmark.ps1 -ResetToDefault`) and inspect the peak voltage boost bin in a light workload.
  * **Step 2 (Synthetic Sweep):** Unlock `--power-cap-watts` to max VBIOS limit, then test `--core` in `+30 MHz` increments (`+60`, `+90`, `+120`, `+150`) alongside `--xbar-offset` (`+90`, `+120`, `+150`, `+180`).
  * **Step 3 (Multiplayer Safe Profile):** Back off **`-30 MHz` on Core** and **`-30 to -45 MHz` on `XBar`** from the highest artifact-free synthetic run so transient boosts above `3,150+ MHz` never trigger `nvlddmkm` TDRs in UE5 titles.

---

## 3. Step-by-Step `mVolt+` Tuning Procedure for Agents

### Step 1: Inspect VBIOS Limits & Neutralize MSI Afterburner
1. Run `.\tools\bin\mVolt+.exe --status | Out-String` (JSON) to read:
   - Power limits (`power_limits.default_mw` vs. `power_limit_percent_limit_max`)
   - Current `core_offset_mhz`, `xbar_offset_mhz`, and `memory_offset_mhz`
2. Check if MSI Afterburner (`MSIAfterburner.exe`) is running or has startup profiles in `C:\Program Files (x86)\MSI Afterburner\Profiles`.
   - Back up all `.cfg` files in `Profiles\`.
   - Set `[Startup] VFCurve=` to all zeros (or disable Afterburner's startup OC apply) so it cannot overwrite `mVolt+`.

### Step 2: Run Stock Baseline
```powershell
.\scripts\Run-GpuBenchmark.ps1 -Label "00_stock_baseline" -ResetToDefault
```
Record the baseline **FurMark 2 Score**, **Min/Avg/Max FPS**, **Sustained Core Clock (MHz)**, **Core/Hotspot/VRAM Temps (°C)**, and **Power Draw (W)**.

### Step 3: Unlock Power Cap & Sweep Memory + Core/XBar
Run controlled 20-second passes with the Vulkan Artifact Scanner enabled:
```powershell
# Example Pass 1: Max Power + Conservative Core/XBar/Mem
.\scripts\Run-GpuBenchmark.ps1 -Label "01_step1" -PowerWatts 400 -CoreOffset 60 -XbarOffset 120 -MemOffset 1000
```
- Verify `0` artifacts detected by FurMark 2 (`--artifact-scanner`).
- Verify `0` events in `.\scripts\Diagnose-Crashes.ps1 -HoursBack 1`.
- Compare effective Core Clock (`MHz`) and FPS against the baseline.

### Step 4: Save & Persist in `mVolt+`
Once the **Rock-Solid Gaming** values are chosen and verified:
1. Apply the final settings via CLI.
2. Launch the `mVolt+` GUI onto the user's desktop using [`scripts/Launch-InteractiveGui.ps1`](../scripts/Launch-InteractiveGui.ps1):
   ```powershell
   .\scripts\Launch-InteractiveGui.ps1 -ExecutablePath "$PWD\tools\bin\mVolt+.exe"
   ```
3. Have the user save the profile (e.g., `Gemini v1.0`) and enable **Start with Windows**, then verify the saved JSON in `%LOCALAPPDATA%\mVolt+\profiles\`.
