# CPU, DDR5 & OS Scheduler Tuning Playbook (AMD Ryzen X3D & Intel Hybrid)

This guide provides architecture-specific tuning playbooks for:
1. **AMD Ryzen 3D V-Cache (`9850X3D` / `9800X3D` / `7800X3D` / `9950X3D` / `7950X3D`)**
2. **Intel 13th/14th Gen Hybrid (`i7-13700K` / `i9-13900K` / `14700K` / `14900K`)**

---

## 1. AMD Ryzen X3D Playbook (`9850X3D` / `9800X3D` / `7800X3D` / `9950X3D`)

AMD's 3D V-Cache processors dominate gaming performance because their expanded `96 MB–128 MB` L3 cache drastically reduces main-memory stalls. Tuning an X3D processor is **not** about fixed all-core multipliers—it is about **PBO2 Curve Optimizer (CO) / Curve Shaper**, **DDR5 `1:1 UCLK=MCLK` memory synchronization**, and **OS thread/power scheduling**.

### A. Hardware Safety Limits (Critical on AM5 X3D)
* **`VSOC` (SoC Voltage):** **Must NEVER exceed `1.30 V`** (AMD AGESA hard cap).
  * **Target Sweet Spot:** **`1.18 V – 1.24 V`** for `DDR5-6000` to `DDR5-6200` (`1.24 V – 1.26 V` if running `DDR5-6400 1:1`). Lowering `VSOC` from an aggressive motherboard auto-EXPO `1.28V` down to `1.20V` frees up `5–8W` of package power budget for the CPU cores!
* **`VDDIO_MEM` / `VDDQ`:** Typically `1.35 V – 1.40 V` for CL30/CL32 EXPO kits.
* **Thermal Limit (`TjMax`):** `89°C` on Zen 4 X3D (`7800X3D`), `95°C` on Zen 5 X3D (`9800X3D` / `9850X3D` / `9950X3D`).

### B. Step 1: Baseline Stress & Telemetry Check (`SensorCli.exe`)
Run the native Scalar + AVX2+FMA stress test:
```powershell
.\tools\SensorCli\bin\Release\net8.0\SensorCli.exe --stress 18
```
Inspect the output for:
1. **Idle vs. Load Package Power (`PPT`):** Should drop to `~20–30 W` at idle (`Tctl/Tdie ~35–42°C`) and scale to `85–145 W` under all-core AVX2 load.
2. **All-Core Boost Clock Under AVX2:**
   - `7800X3D`: Stock all-core AVX2 typically `4,750–4,850 MHz` (`5,050 MHz` gaming).
   - `9800X3D` / `9850X3D`: Stock all-core AVX2 typically `5,150–5,225 MHz` (`5,225–5,425+ MHz` gaming with PBO `+200 MHz`).
3. **`VSOC` and DDR5 DIMM Temps:** Verify `VSOC <= 1.25 V` and DDR5 DIMMs `< 50°C`.

### C. Step 2: Single-CCD vs. Dual-CCD X3D Thread & Power Scheduling

| CPU Topology | Examples | Core Parking & Process Lasso Strategy |
| :--- | :--- | :--- |
| **Single-CCD X3D (8C / 16T)** | `7800X3D`, `9800X3D`, `9850X3D` | **Every core has 3D V-Cache.** You do **NOT** want Windows parking cores during gameplay. Use [`scripts/Manage-CpuPowerPlan.ps1 -Action ApplySmartHighPerf`](../scripts/Manage-CpuPowerPlan.ps1) (`CPMINCORES = 100%`, `PROCTHROTTLEMIN = 5%`, `PERFEPP = 60%`). Pin background apps (`discord.exe`, browsers, OBS) to the last 2 physical cores (`Threads 12–15`) in Process Lasso if desired, leaving `Threads 0–11` clean for the game. |
| **Dual-CCD X3D (12C / 16C)** | `7900X3D`, `7950X3D`, `9900X3D`, `9950X3D` | **Asymmetric CCDs:** `CCD0` has the **3D V-Cache** (gaming CCD), while `CCD1` has higher peak frequency but standard L3 cache. **Do NOT disable Core Parking globally** if relying on Windows Game Bar + AMD 3D V-Cache Performance Optimizer driver, **OR** use Process Lasso to explicitly pin games to `CCD0` (`Threads 0–15` on 16-core) and pin background apps (`discord.exe`, `msedge.exe`, `obs64.exe`, `steam.exe`) to `CCD1` (`Threads 16–31`). |

### D. Step 3: PBO2 Curve Optimizer (CO) & Zen 5 Boost Override
On `9800X3D` / `9850X3D` (Zen 5 X3D, which placed the 3D V-Cache *underneath* the CCD for dramatically better thermal transfer and unlocked PBO frequency scaling):
1. **PBO Limits:** `Motherboard` or `PPT = 142W / TDC = 110A / EDC = 170A`.
2. **CPU Boost Clock Override (Zen 5 X3D):** `+100 MHz` to `+200 MHz` (raises peak boost ceiling by up to +200 MHz when thermal/power headroom permits).
3. **Curve Optimizer (All-Core or Per-Core Negative Offset):**
   - **Safe Multiplayer Starting Point:** **`-15` to `-20` all-core** (approx. `-45 mV` to `-60 mV` across the V/F curve).
   - **Enthusiast Tuned Range:** **`-20` to `-30`**, validated with `SensorCli.exe --stress` AND light-load single-thread core cycling (`OCCT` Core Cycler).
   - *Watch out for:* If a negative CO offset is too aggressive (`-30` to `-40`), the PC will **not** usually crash under 100% all-core load—instead, it will reboot or throw a **`WHEA-Logger` Event ID 18 (`Cache Hierarchy Error`)** when transitioning from load back to idle! Always check [`scripts/Diagnose-Crashes.ps1`](../scripts/Diagnose-Crashes.ps1) after tuning CO.

### E. Step 4: DDR5 Memory Sweet Spot for AM5 X3D
* **6000 MT/s CL30 (Universal 100% Plug-and-Play Sweet Spot):** Runs `MCLK = 3000 MHz`, `UCLK = 3000 MHz` (`1:1` mode), `FCLK = 2000 MHz` at `VSOC ~1.18–1.20 V`.
* **6200–6400 MT/s CL30/CL32 (Tuned 1:1 Ceiling):**
  * **CRITICAL CHECK:** If the user enables a `DDR5-6400` EXPO/XMP profile on AM5, many motherboards automatically drop `UCLK` into **`1:2` mode (`UCLK = MCLK / 2 = 1600 MHz`)**, which **hurts gaming latency** compared to `DDR5-6000 1:1`!
  * Always verify that `UCLK = MCLK` (`1:1` mode, `3100–3200 MHz`) and `FCLK = 2067–2133 MHz`.

---

## 2. Intel 13th/14th Gen Hybrid Playbook (`i7-13700K` / `i9-13900K` / `14700K` / `14900K`)

### A. Mandatory Silicon Protection Verification
Run [`scripts/Inspect-System.ps1`](../scripts/Inspect-System.ps1) first and confirm:
1. **CPU Microcode Revision:** Must be **`0x12B` or `0x12F`** (e.g., `2F010000` in Windows registry). This prevents elevated transient `VID` requests (`>1.55V`) that caused Raptor Lake Vmin Shift degradation.
2. **Power & Current Limits (Intel Default Settings):**
   - `i7-13700K` / `14700K`: **`PL1 = 253 W`, `PL2 = 253 W`, `IccMax = 307 A`**.
   - Never set `PL1/PL2 = 4095 W (Unlimited)` or `IccMax = 512 A`.

### B. Fixing the "High-Performance Power Plan Idle Trap"
Many enthusiasts install **Process Lasso** / **ParkControl** and activate `Bitsum Highest Performance`. By default, this sets:
- `PROCTHROTTLEMIN` / `PROCTHROTTLEMIN1` = `100%`
- `HETEROCLASS0FLOORPERF` = `100%`
- `PERFEPP` / `PERFEPP1` (Speed Shift Energy Performance Preference) = `5%`

**What goes wrong:**
- Even at `2%` desktop load, all 8 P-cores and 8 E-cores are pinned at max all-core frequency (`5.3 GHz` / `1.38 V`), burning **`65–70 W` at idle** and keeping idle package temps at **`60°C+`**.
- Worse, because all 8 P-cores are forced active 24/7, the 2 favored P-cores can never enter 1–2 Active Core Turbo (`5.4 GHz`).

**The Fix (`SmartHighPerf` Option B):**
Run:
```powershell
.\scripts\Manage-CpuPowerPlan.ps1 -Action ApplySmartHighPerf
```
This keeps **Core Parking 100% disabled** (`CPMINCORES = 100%`) so no cores ever sleep during gameplay, while setting `PROCTHROTTLEMIN = 5%` and `PERFEPP = 60%`.
- **Result:** Idle `Vcore` drops from **`1.36 V` $\rightarrow$ `0.83 V`**, idle power drops from **`67 W` $\rightarrow$ `22 W`**, idle temps drop by **`-25°C`**, and hardware Speed Shift snaps clocks back to **`5,328+ MHz` in `<1 ms`** the instant any thread requests CPU work.

### C. Hybrid P-Core / E-Core Affinity in Process Lasso
On Intel Hybrid CPUs (e.g., `i7-13700K` where `Threads 0–15` are the 8 hyper-threaded P-Cores and `Threads 16–23` are the 8 E-Cores):
- Pin background chat/browsers/capture (`discord.exe`, `msedge.exe`, `chrome.exe`) to **E-Cores (`16–23`)**.
- Keep multiplayer games on **P-Cores (`0–15`)** with **Efficiency Mode = OFF**.
