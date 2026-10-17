# Case Study #1: Intel Core i7-13700K + Gigabyte RTX 4080 (Z790 / DDR5-6400)

This document records the complete end-to-end hardware inspection, crash forensics, experimental sweeps, and verified production profiles for our first reference system.

---

## 1. System Specifications

* **CPU:** Intel Core i7-13700K (8 P-Cores + 8 E-Cores, 24 Threads)
* **Motherboard:** Gigabyte Z790 AORUS ELITE AX (BIOS `FL`, `2025-06-18`, **Microcode `0x12F`**)
* **Memory:** 32 GB (2×16 GB) G.Skill Trident Z5 DDR5-6400 CL32 (`F5-6400J3239G16G`) @ `6400 MT/s` (`1.40 V`, `VSA = 1.245 V`)
* **GPU:** Gigabyte GeForce RTX 4080 16GB (`SUBSYS_40C51458`, VBIOS `95.03.2b.40.3b`, Driver `616.86`)
  * Default Power Limit: `340 W` (`100%`) | Maximum VBIOS Power Limit: **`400 W` (`117%`)**
* **OS & Security:** Windows 11 with **VBS (Virtualization-Based Security) Enabled**, **Process Lasso** + **FanControl** (`PawnIO` driver)

---

## 2. Part 1: GPU Forensics & Optimization (`mVolt+`)

### A. Root-Cause Diagnosis of Prior Game Crashes
1. **What we found:**
   - Before tuning with `mVolt+`, the system had an old **MSI Afterburner (`Venom`) per-point V/F curve** stored in `VENOM_10DE_2704...cfg`.
   - That custom curve manually locked individual voltage points (`+142 MHz` at `900 mV` tapering down to `+113 MHz` at `990–1,035 mV`) and flattened the high-voltage tail.
   - Across recent driver updates, those intermediate `975–1,035 mV` voltage bins were slightly starved for voltage during rapid DX12/D3D11 load transitions—triggering **`nvlddmkm` Event ID 153** TDR resets during gameplay.
2. **Clean-Slate Remediation:**
   - Backed up all MSI Afterburner `.cfg` profiles to [`profiles/i7-13700k-rtx4080/ab_backup/`](../../profiles/i7-13700k-rtx4080/ab_backup/).
   - Cleared Afterburner's per-point `VFCurve` to `0` offsets so it could no longer fight `mVolt+`.

### B. Controlled GPU Benchmark Sweeps (FurMark 2 Vulkan Knot 1440p + Artifact Scanner)
Each pass was a 30-second FurMark 2 Knot run (`--demo furmark-knot-vk --duration-ms 30000`) at `2560×1440` with `--artifact-scanner` enabled. Score and FPS come from FurMark's [`furmark_scores.csv`](../../profiles/i7-13700k-rtx4080/benchmarks/furmark_scores.csv); clocks and max temperatures from the per-second `fm_*.csv` logs in [`benchmarks/`](../../profiles/i7-13700k-rtx4080/benchmarks/).

| Pass / Profile | Date / Time | Power Cap | Core Offset | `XBar` Offset | VRAM Offset | Sustained Core / VRAM Clock | FurMark 2 Score | FPS (Min / Avg / Max) | Core / VRAM Temp | Real-World Gaming Stability |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **0. Prior Afterburner OC** ([`ab_backup/`](../../profiles/i7-13700k-rtx4080/ab_backup/)) | `Oct 16 20:21` | `117%` | Custom V/F curve | — | `+1,200 MHz` | `2,806 MHz` / `24,805 MHz` | `2,152` | `64 / 71 / 74` | `62°C` / `52°C` | **TDRs (`nvlddmkm` 153) in games** (see A) |
| **1. VRAM + XBar Test** | `Oct 16 20:49` | `400 W` | `+0 MHz` | `+180 MHz` | `+1,350 MHz` | `2,806 MHz` / `25,105 MHz` | `2,004` | `63 / 67 / 75` | `61°C` / `54°C` | Not game-tested |
| **2. Aggressive Push** | `Oct 16 20:50` | `400 W` | `+135 MHz` | `+180 MHz` | `+1,100 MHz` | `2,910–2,926 MHz` / `24,605 MHz` | `2,251` | `68 / 74 / 77` | `67°C` / `56°C` | Not game-tested |
| **3. Peak Synthetic** | `Oct 16 20:51` | `400 W` | `+150 MHz` | `+210 MHz` | `+1,150 MHz` | `2,926–2,940 MHz` / `24,705 MHz` | `2,278` | `68 / 75 / 78` | `66°C` / `60°C` | Not game-tested |
| **4. Initial Gaming (`+90/+150`)** † | `Oct 16 20:54` | `400 W` | `+90 MHz` | `+150 MHz` | `+1,050 MHz` | `2,910–2,926 MHz` / `24,705 MHz` | `2,362` | `68 / 78 / 82` | `65°C` / `58°C` | **TDR (`nvlddmkm` 153) during `Invokyr` transient spike** |
| **5. Final `Gemini v1.0`** | `Oct 17 01:08` | **`400 W`** | **`+60 MHz`** | **`+120 MHz`** | **`+1,000 MHz`** | **`2,838–2,848 MHz` / `24,405 MHz` (`2,910` in-game)** | **`2,309`** (3-run mean) | **`63 / 76 / 80`** | **`67°C` / `60°C`** | **100% Verified (90-min multiplayer `0` errors)** |

† Pass 4's telemetry (`24,705 MHz` VRAM, `~2,926 MHz` core) matches Pass 3's settings, not the listed ones; the settings active during that capture were not logged.

### C. Key Lesson from Pass #4 $\rightarrow$ Pass #5 (`Gemini v1.0`)
- While `+90 MHz Core / +150 MHz XBar` passed FurMark 2 at `2,865 MHz` (`1.015 V`), in actual gameplay (`Invokyr`), lighter rendering moments allowed GPU Boost to climb to its highest `1.075 V` voltage bin (`~2,940+ MHz`), triggering an `nvlddmkm` Event ID 153 reset after 6 minutes.
- Stepping down 2 boost bins to **`+60 MHz Core / +120 MHz XBar / +1,000 MHz VRAM` (`Gemini v1.0`)** scores `2,309` (`76` avg FPS, mean of 3 runs) with `200 MHz` less memory overclock than the prior Afterburner setup, while capping peak in-game transient boost at a rock-solid **`2,895–2,910 MHz`**, which subsequently ran **90+ minutes of multiplayer `Invokyr` with zero crashes or driver warnings**.

---

## 3. Part 2: CPU, DDR5 & Power Plan Optimization (`i7-13700K`)

### A. Hardware & Firmware Audit
* Confirmed BIOS `FL` (`2025-06-18`) is running **Microcode `0x12F`** with Intel Default protection limits active (`PL1 = 253 W`, `PL2 = 253 W`, `IccMax = 307 A`).
* Confirmed G.Skill DDR5-6400 CL32 is running XMP at `6400 MT/s` with DIMM temperatures at a cool **`40.0–41.0°C`** under load.
* Confirmed slightly elevated `100.52 MHz` BCLK gives all P-cores **`5,328 MHz`** (`53 × 100.52`) and E-cores **`4,021–4,222 MHz`**.

### B. All-Core Scalar & AVX2+FMA Stress Test Results
Using [`SensorCli.exe --stress`](../../tools/SensorCli/Program.cs), we loaded all 24 logical processors to 100% across both Scalar and AVX2+FMA workloads:
* **Peak Package Power:** `157.3 W` (Scalar) / `148.1 W` (AVX2+FMA) — well below the `253 W` PL1/PL2 cap.
* **Peak Temperatures:** `79°C` CPU Package max (`61.4–63.4°C` P-Core average, `54–60°C` E-Cores) — **`21°C` of thermal headroom** below the `100°C` TjMax limit!
* **AVX2 Clock Stability:** Held **`5,328 MHz` flat** across all 8 P-cores during 100% AVX2+FMA load with zero thermal, power, or VRM throttling.

### C. Solving the `67W` / `1.38V` Idle Heat Trap (`SmartHighPerf` Option B)
* **Discovery:** Because Process Lasso's default `Bitsum Highest Performance` profile had `PROCTHROTTLEMIN = 100%` and `PERFEPP = 5%`, the i7-13700K was pinned at `5,328 MHz` and `1.36–1.39 V` even at `3%` desktop load—burning **`67.4 W`** and sitting at **`61°C`** at idle.
* **Optimization Applied ([`Apply-SmartHighPerf-13700K.ps1`](../../profiles/i7-13700k-rtx4080/Apply-SmartHighPerf-13700K.ps1)):**
  - Kept **Core Parking 100% disabled** (`CPMINCORES = 100%`, `CPMINCORES1 = 100%`) so all 24 threads stay awake for gaming.
  - Set `PROCTHROTTLEMIN = 5%`, `PROCTHROTTLEMIN1 = 5%`, `HETEROCLASS0FLOORPERF = 5%`.
  - Tuned Speed Shift Energy Performance Preference (`PERFEPP` / `PERFEPP1`) to **`60%`**.

| CPU Metric | Before (`Bitsum Default`) | After (`Option B SmartHighPerf`) | Delta |
| :--- | :--- | :--- | :--- |
| **Core Parking** | `100%` Unparked | **`100%` Unparked** | Zero wake-up latency |
| **Idle Motherboard `Vcore`** | `1.36 V` | **`0.83 V`** | **`-0.53 V` lower idle voltage** |
| **Idle CPU Package Power** | `67.4 W` | **`22.5 W`** | **`-44.9 W` less idle heat** |
| **Idle CPU Package Temp** | `61.0°C` | **`36.0°C`** | **`-25.0°C` cooler at idle** |
| **Idle Core Average Temp** | `42.9°C` | **`32.4°C`** | **`-10.5°C` cooler core average** |
| **Load Boost Clocks** | `5,328 MHz` (P) / `4,222 MHz` (E) | **`5,328 MHz` (P) / `4,222 MHz` (E)** | Instant `<1 ms` Speed Shift ramp |
