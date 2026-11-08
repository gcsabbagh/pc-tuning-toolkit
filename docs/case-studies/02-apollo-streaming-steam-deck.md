# Case Study #2: Apollo → Steam Deck Streaming (i7-13700K + RTX 4080)

This document records four streaming problems found on the [Case Study #1](01-i7-13700k-rtx4080-gigabyte.md) rig after it was tuned, how each was diagnosed, and the fix that was verified. The GPU and CPU profiles from Case Study #1 were not changed. None of these problems came from the overclock.

---

## 1. Setup

* **Host:** the Case Study #1 rig (`i7-13700K`, Gigabyte `RTX 4080`, `Gemini v1.0` + `SmartHighPerf`), wired Ethernet.
* **Monitors:** ASUS `PG27UQR` (primary, 4K 160 Hz HDR, G-Sync) + HP `Z27`.
* **Streaming server:** Apollo `0.4.7` (Sunshine fork), service `ApolloService`, NVENC **AV1** at **90 fps**, Apollo virtual display with `ensure_primary`.
* **Client:** Steam Deck running Moonlight over **6 GHz Wi-Fi** (mesh router). Deck Wi-Fi power management off.

---

## 2. Problems & Fixes

| # | Date | Symptom | Root cause | Fix | Verified |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **A** | `2026-10-30` | Stream capture resets about every `10 s` | When Windows isn't driving the `PG27UQR`, the monitor re-announces itself over DisplayPort. Windows logs it as `Microsoft-Windows-DeviceSetupManager/Admin` Event `112`, and every announce forces Apollo to rebuild capture. | Set Windows to **extend to all screens** so the monitor stays driven. Also turn off **DP Deep Sleep** in the monitor's OSD. | Resets stopped |
| **B** | `2026-11-01` | Moonlight: *"frames dropped due to network jitter"* every `20–40 s` | The Deck's **Developer → "Force WPA supplicant Wi-Fi backend"** toggle. `wpa_supplicant` runs periodic background scans, and each scan briefly takes the radio off-channel. | Turn that toggle **off** on the Deck. | Jitter warnings gone |
| **C** | `2026-11-01` | Short frame stalls on the host (`19–43 ms`) | Sunshine/Apollo was pinned to threads `0–3`, sharing the game's busiest threads and core 0 (where much of Windows' system work runs). | Pin Sunshine/Apollo to the **E-cores (`16–23`) at High priority** in Process Lasso ([rule set](../../profiles/i7-13700k-rtx4080/process-lasso-rules.md)). | `0–3`: 7 of 30 windows stalled. `16–23`: 0 of 15, median `5.1 ms` |
| **D** | `2026-11-08` | High PC latency (`120–150 ms`) while streaming | Global NVIDIA Control Panel **V-Sync On** is correct for G-Sync on the local monitor. Apollo's virtual display has no VRR, though, so the same setting becomes classic V-Sync and frames queue. | Switch the global driver profile per session with [`Set-NvDisplayConfig.ps1`](../../scripts/Set-NvDisplayConfig.ps1). `apolloVirtDisplay` gets V-Sync Off + limiter at client fps `- 3`. `pg27uqr` gets V-Sync On + limiter `155`. | Resume, pause and terminate all switch correctly with no UAC prompts. `RLAT` `~5 ms` while streaming (see the `LAT` pitfall below) |

Metric for **C**: Apollo's debug `Frame processing latency`, worst frame per 20 s window, 90 fps AV1 to the Deck.

---

## 3. Diagnosis Notes

### A. Capture resets → match host events to Apollo's log
Pull `DeviceSetupManager/Admin` Event `112` timestamps and line them up with Apollo's `encoder teardown` log lines. If they match one for one, a display hotplug is causing the resets. The encoder and network are not the problem.

### B. Network jitter → ping the client, look for a rhythm
Ping the Deck about 5 times a second for a few minutes. Random spikes point to RF or interference. **Periodic** bursts every 20–40 s point to something on the client scanning or sleeping on a timer, which here was `wpa_supplicant`.

### D. Automatic V-Sync switch (details in the [GPU guide](../gpu-tuning-guide.md#4-streaming-with-apollo--sunshine-g-sync-v-sync-switch))
* Apollo `global_state_cmd` runs `-Target apolloVirtDisplay` on resume and the `-Target pg27uqr` undo on pause. `global_prep_cmd` runs the `pg27uqr` undo when a session is terminated. All three are `"elevated": true`, because Profile Inspector requires Admin and a UAC prompt would stall the stream.
* Both displays are entries in [`profiles/i7-13700k-rtx4080/nvidia-display-config.json`](../../profiles/i7-13700k-rtx4080/nvidia-display-config.json). The stream's client fps comes from `APOLLO_CLIENT_FPS`: Deck `90 → 87`, TV `120 → 117`.
* Connect with a real app (e.g. **Desktop**). Apollo's built-in **Virtual Display** entry runs neither prep nor state commands.

### Measurement pitfall: the NVIDIA overlay's `LAT` while streaming
With the fix in place, the NVIDIA overlay's **PC Latency (`LAT`)** still read `160–200 ms` while streaming, even though render latency (`RLAT`) was `~5 ms`. Treat `LAT` as an artifact of the virtual display and emulated controller. Judge streaming latency from `RLAT`, Moonlight's on-screen stats, and a phone slow-motion test (input to on-screen change) instead.

---

## 4. Takeaways

1. **Stream hitches are rarely the encoder.** Three of the four problems came from a monitor, the client's Wi-Fi stack, and CPU scheduling.
2. **Correlate timestamps before changing settings.** Event `112` vs. Apollo teardown, and periodic vs. random ping spikes, each pointed straight at the cause.
3. **G-Sync settings don't carry over to a virtual display.** Switch the driver profile per session instead of choosing one setting for both.
