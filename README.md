# Agentic PC Tuning & Stability Toolkit

An **AI-Agent-Ready Hardware Telemetry, Crash Forensics, and GPU/CPU Tuning Toolkit** for Windows gaming PCs.

Designed so that any human or AI coding agent (Antigravity, Claude Code, Cursor, etc.) can open this repository, read [`AGENTS.md`](AGENTS.md), and systematically inspect, stress-test, diagnose, and optimize a user's **GPU, CPU, DDR5 Memory, and Windows Scheduler**—with **100% multiplayer gaming stability** as the non-negotiable top priority.

---

## Table of Contents

1. [Documentation & Guides (Human-Readable)](#documentation--guides-human-readable)
2. [Supported Hardware & Architecture Playbooks](#supported-hardware--architecture-playbooks)
3. [Prerequisites, Required Libraries & Tools](#prerequisites-required-libraries--tools)
4. [Quick Start (For AI Agents & Users)](#quick-start-for-ai-agents--users)
5. [Repository Structure](#repository-structure)

---

## Documentation & Guides (Human-Readable)

Whether you are tuning your PC yourself or guiding an AI agent through the process, start with these guides in [`docs/`](docs/):

| Guide | What You'll Learn |
| :--- | :--- |
| **[1. Prerequisites & Setup Guide](docs/prerequisites-and-setup.md)** | Every required runtime (`.NET 8/10`), VBS-compatible sensor driver (`PawnIO` / `FanControl`), GPU tuner (`mVolt+`), and benchmark tool (`FurMark 2`), plus 1-click `winget` install commands and troubleshooting. |
| **[2. Tuning Methodology & Objectives](docs/methodology.md)** | Why **Multiplayer Stability > Synthetic Peak Scores**, why games crash during light-to-heavy load transitions even when synthetic stress tests pass, and our 5-Phase scientific tuning loop. |
| **[3. NVIDIA GPU Tuning Playbook (Ada & Blackwell)](docs/gpu-tuning-guide.md)** | Why MSI Afterburner's fixed per-point V/F curves cause `nvlddmkm` TDR crashes in UE5/DX12 games, and how to use `mVolt+` to tune **Power Cap**, **Core Offset**, **Crossbar (`XBar`) L2 Interconnect**, and **GDDR6X / GDDR7 Memory ECC** sweet spots on **RTX 4080/4090** and **RTX 5080/5090**. |
| **[4. CPU, DDR5 & OS Scheduler Playbook (AMD X3D & Intel)](docs/cpu-tuning-guide.md)** | Complete tuning guides for **AMD Ryzen 3D V-Cache (`9850X3D`, `9800X3D`, `7800X3D`, `9950X3D`)** (PBO2 Curve Optimizer, `VSOC <= 1.25V`, DDR5 `1:1 UCLK=MCLK`, Single vs. Dual-CCD core parking) and **Intel 13th/14th Gen Hybrid (`i7-13700K`, `14700K`, `14900K`)** (Microcode `0x12F` safety, Speed Shift EPP idle power fix, P/E-core affinities). |
| **[5. Crash Diagnostics & Event Log Forensics](docs/crash-diagnostics-guide.md)** | How to read Windows Event Logs (`nvlddmkm` Event IDs `153/14`, `Display 4101`, `LiveKernelEvent 141`, and CPU `WHEA-Logger` Event IDs `18/19`) to immediately tell whether a game crashed from GPU Core, VRAM, CPU undervolt, RAM, or a game bug. |
| **[6. Case Study #1: i7-13700K + Gigabyte RTX 4080](docs/case-studies/01-i7-13700k-rtx4080-gigabyte.md)** | Real-world walkthrough of our first tuned rig: diagnosing Afterburner V/F curve TDRs, running 5 FurMark 2 + artifact scanner sweeps, catching a transient boost spike in `Invokyr`, locking in the rock-solid **`Gemini v1.0`** profile, and dropping idle CPU power from **`67.4W` $\rightarrow$ `22.5W` (`-25°C` cooler)**. |
| **[7. Case Study #2: Apollo $\rightarrow$ Steam Deck Streaming](docs/case-studies/02-apollo-streaming-steam-deck.md)** | Tracking down streaming hitches and latency on the same rig: a monitor's DisplayPort hotplug resetting capture, Steam Deck `wpa_supplicant` scans causing network jitter, Sunshine moved to the E-cores, and an automatic G-Sync $\leftrightarrow$ streaming V-Sync switch that removes classic V-Sync queuing on Apollo's virtual display. |
| **[8. Testing & Regression Verification Guide](docs/testing-and-verification.md)** | How to run [`tests/Invoke-SmokeTests.ps1`](tests/Invoke-SmokeTests.ps1) (full hardware mode or `-SkipHardwareTests` static mode) to verify AST syntax, static policy guards, `mVolt+` helpers, `SensorCli`, and script execution after making changes. |
| **[9. Autonomous AI Agent Playbook (`AGENTS.md`)](AGENTS.md)** | Step-by-step operational instructions, safety guardrails, and PowerShell commands for AI coding assistants. |

---

## Supported Hardware & Architecture Playbooks

* **NVIDIA GPUs (via `mVolt+` CLI & FurMark 2 Artifact Scanner):**
  * **RTX 50-Series (Blackwell — e.g., `RTX 5080`, `RTX 5090`):** Dynamic Core offset, Crossbar (`XBar`) L2 interconnect tuning, and GDDR7 PAM3 ECC memory bandwidth sweet-spot profiling.
  * **RTX 40-Series (Ada Lovelace — e.g., `RTX 4080`, `RTX 4090`):** Replacing unstable MSI Afterburner per-point V/F curves with whole-curve + `XBar` offsets and GDDR6X ECC profiling.
* **AMD & Intel CPUs (via VBS-compatible `SensorCli` + Power Plan & Process Lasso Playbooks):**
  * **AMD Ryzen 3D V-Cache (`9850X3D`, `9800X3D`, `7800X3D`, `9950X3D`, `7950X3D`):** PBO2 Curve Optimizer (CO) / Curve Shaper, `VSOC <= 1.25V` safety guardrails, DDR5 `6000–6400 MT/s` `1:1 UCLK=MCLK` verification, and Single-CCD vs. Dual-CCD core parking / thread affinity.
  * **Intel 13th/14th Gen Hybrid (`i7-13700K`, `i9-13900K`, `14700K`, `14900K`):** Microcode `0x12F` Vmin Shift verification (`253W PL1/PL2`, `307A IccMax`), Speed Shift EPP idle-power optimization (`SmartHighPerf`), and P-core / E-core gaming thread scheduling.

---

## Prerequisites, Required Libraries & Tools

Run **`.\scripts\Bootstrap-Tools.ps1 -DownloadMissing`** from an **Administrator** PowerShell prompt to install or locate everything automatically. The full dependency matrix, `winget` IDs, and troubleshooting live in [`docs/prerequisites-and-setup.md`](docs/prerequisites-and-setup.md).

* **Required:** Administrator shell, `.NET 8 SDK` + `.NET 10 Runtime`, FanControl (`LibreHardwareMonitorLib.dll` + `PawnIO`), `mVolt+` (NVIDIA), FurMark 2 (GPU bench), NVIDIA driver (`nvidia-smi`).
* **Recommended:** OCCT Personal (3D Adaptive stability validation).
* **Optional:** NVIDIA Profile Inspector (streaming V-Sync switch), Process Lasso (background-app affinity).

---

## Quick Start (For AI Agents & Users)

> [!IMPORTANT]
> Run your terminal or AI IDE (`Antigravity`, `Cursor`, `PowerShell`) **as Administrator** so hardware sensors (`PawnIO` / `LibreHardwareMonitorLib`) and `mVolt+` have hardware register access.

### 1. Ask Your AI Agent to Tune Your Rig
Open this repository in your AI coding assistant and prompt:
> *"Read `AGENTS.md` and `docs/methodology.md`. Inspect my CPU, GPU, and RAM, check my crash logs, run a baseline thermal/stress check, and help me tune my GPU and CPU for 100% stable multiplayer gaming."*

### 2. Or Run the Toolkit Scripts Directly
```powershell
# 1. Bootstrap tools, install missing dependencies & build SensorCli.exe
.\scripts\Bootstrap-Tools.ps1 -DownloadMissing

# 2. Inspect CPU, Microcode/AGESA, BIOS, RAM XMP/EXPO, GPU VBIOS, and Power Plan
.\scripts\Inspect-System.ps1

# 3. Check the last 72 hours of Windows Event Logs for GPU TDRs, WHEA errors, or crashes
.\scripts\Diagnose-Crashes.ps1 -HoursBack 72

# 4. Run a 20-second CPU Scalar + AVX2+FMA stress & thermal check
.\tools\SensorCli\bin\Release\net8.0\SensorCli.exe --stress 18

# 5. Run three 30-second FurMark 2 Knot (Vulkan) passes with artifact scanning and report mean/spread
.\scripts\Run-GpuBenchmark.ps1 -Label "baseline" -ResetToDefault -Runs 3

# 6. Run the non-destructive smoke & regression test suite after modifying any scripts
.\tests\Invoke-SmokeTests.ps1
```

---

## Repository Structure

```text
pc-tuning-toolkit/
├── AGENTS.md                                  # Autonomous AI Agent Playbook (Start here if you are an AI agent!)
├── README.md                                  # Project overview, TOC & quick start
├── docs/
│   ├── prerequisites-and-setup.md             # Required runtimes, drivers (PawnIO), libraries & winget setup guide
│   ├── methodology.md                         # Core philosophy (Multiplayer Stability > Synthetic Peak) & 5-Phase loop
│   ├── gpu-tuning-guide.md                    # NVIDIA RTX 40-Series (Ada) & RTX 50-Series (Blackwell / 5080) mVolt+ Guide
│   ├── cpu-tuning-guide.md                    # AMD Ryzen X3D (9850X3D/9800X3D/7800X3D) & Intel 13th/14th Gen Guide
│   ├── crash-diagnostics-guide.md             # Event Log forensics (nvlddmkm TDRs, WHEA-Logger, DXGI_ERROR_DEVICE_HUNG)
│   ├── testing-and-verification.md            # Automated non-destructive smoke & regression test suite guide
│   └── case-studies/
│       ├── 01-i7-13700k-rtx4080-gigabyte.md   # Case Study #1: Full thinking, baseline, sweeps & verified results
│       └── 02-apollo-streaming-steam-deck.md  # Case Study #2: Apollo -> Steam Deck streaming hitches & latency fixes
├── scripts/
│   ├── Bootstrap-Tools.ps1                    # Locates/downloads mVolt+, LibreHardwareMonitorLib (PawnIO), SensorCli, FurMark 2, Profile Inspector
│   ├── Set-NvDisplayConfig.ps1                # Applies a rig's per-display NVIDIA settings (V-Sync, FPS cap) for the target display
│   ├── Inspect-System.ps1                     # Hardware discovery: CPU, Microcode/AGESA, BIOS, VBS, DDR5, GPU VBIOS, Power Plan
│   ├── Diagnose-Crashes.ps1                   # Scans Windows Event Logs for GPU TDRs, WHEA hardware errors, BSODs & app faults
│   ├── Run-GpuBenchmark.ps1                   # Automated mVolt+ tuner + FurMark 2 Vulkan Knot + Artifact Scanner + CSV logger
│   ├── Manage-CpuPowerPlan.ps1                # Backup, inspect, and apply "SmartHighPerf" (Unparked + Dynamic Idle EPP)
│   ├── Launch-InteractiveGui.ps1              # Helper for background AI agents to open GUI apps on the user's desktop
│   └── MvoltHelpers.ps1                       # Shared mVolt+ wrapper (synchronous calls, exit-code checks, --status parsing)
├── tools/
│   └── SensorCli/                             # C# Hardware Telemetry & Native Scalar + AVX2+FMA CPU Stress Tester
│       ├── SensorCli.csproj
│       └── Program.cs
├── tests/
│   └── Invoke-SmokeTests.ps1                  # Automated non-destructive smoke & regression test suite
└── profiles/
    └── i7-13700k-rtx4080/                     # Saved profiles, backups & benchmark logs from Case Study #1
        ├── Apply-Gemini-v1.0-4080.ps1         # 1-click apply for RTX 4080 Rock-Solid Gaming profile (+60 Core/+120 XBar/+1000 Mem)
        ├── Apply-SmartHighPerf-13700K.ps1     # 1-click apply for i7-13700K Option B Power Plan (67W -> 22W idle, 0.83V, 36°C)
        ├── nvidia-display-config.json         # Per-display NVIDIA settings (pg27uqr, apolloVirtDisplay) for Set-NvDisplayConfig.ps1
        ├── README.md                          # Index of this profile's files
        ├── process-lasso-rules.md             # Process Lasso rule set (games on P-Cores, background & Sunshine on E-Cores)
        ├── mvolt-gemini-v1.0-profile.json     # Exported mVolt+ JSON profile
        ├── benchmarks/                        # Raw FurMark 2 CSVs & CPU stress logs
        └── backups/                           # Local only (git-ignored): original power plan + MSI Afterburner profiles
```
