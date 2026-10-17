# Testing & Regression Verification Guide

This document describes the automated non-destructive test suite ([`tests/Invoke-SmokeTests.ps1`](../tests/Invoke-SmokeTests.ps1)) included in the **Agentic PC Tuning & Stability Toolkit**, what each check verifies, and how to run it after modifying any PowerShell script, profile, or C# telemetry tool.

---

## 1. Overview & Safety Guarantee

Hardware tuning scripts interact directly with ring-0 sensors (`PawnIO` / `LibreHardwareMonitorLib`), NVAPI clock/voltage domains (`mVolt+`), and Windows Processor Power Plans (`powercfg`). A syntax error, broken CLI flag, or unhandled exit code can cause a script to silently misreport a baseline or apply unintended settings.

[`tests/Invoke-SmokeTests.ps1`](../tests/Invoke-SmokeTests.ps1) is **100% non-destructive**:
- It **never** alters active GPU clocks, voltages, or power caps (profile tests run exclusively with `-DryRun`).
- It **never** modifies your active Windows Power Plan (power plan tests only export a temporary `.pow` backup and read status, then clean up).
- It returns exit code `0` when all checks pass and `1` if any check fails, making it suitable for both local agent verification and CI pipelines.

---

## 2. How to Run the Smoke Test Suite

### Full Suite (Recommended — Run from an Administrator PowerShell)
Runs all 22 static, build, and live read-only hardware/telemetry tests:

```powershell
.\tests\Invoke-SmokeTests.ps1
```

### Static-Only Mode (No Hardware / No Admin / CI Mode)
Skips live hardware, `mVolt+`, `powercfg`, and `SensorCli` execution checks while still running PowerShell AST syntax parsing and static policy regression guards:

```powershell
.\tests\Invoke-SmokeTests.ps1 -SkipHardwareTests
```

---

## 3. What the Test Suite Verifies

| Category | Test Name | What It Verifies & Files Covered |
| :--- | :--- | :--- |
| **1. AST Syntax Parsing** | `AST Syntax: <script>` | Parses every `.ps1` file in [`scripts/`](../scripts/), [`profiles/`](../profiles/), and [`tests/`](../tests/) via `[System.Management.Automation.Language.Parser]::ParseFile` and fails on any syntax error. |
| **2. Static Policy Guards** | `No hardcoded user scratch paths` | Ensures no machine-specific paths (e.g. `\.gemini\antigravity\scratch`) are reintroduced into any script. |
| | `No deprecated mVolt+ flags` | Ensures removed/nonexistent `mVolt+` CLI flags (`--info`, `--reset`) are never called in scripts. (See [`docs/gpu-tuning-guide.md`](gpu-tuning-guide.md) and [`scripts/MvoltHelpers.ps1`](../scripts/MvoltHelpers.ps1).) |
| | `.gitignore un-ignores tools/bin/.gitkeep` | Verifies [`.gitignore`](../.gitignore) keeps the `!tools/bin/` + `tools/bin/*` + `!tools/bin/.gitkeep` negation pattern and that `tools/bin/.gitkeep` exists on disk. |
| | `All relative Markdown links resolve` | Scans [`README.md`](../README.md), [`AGENTS.md`](../AGENTS.md), and every file under [`docs/`](../docs/) to verify all relative Markdown links resolve to existing files or directories. |
| **3. Bootstrap & Build** | `Bootstrap-Tools.ps1 & SensorCli build` | Runs [`scripts/Bootstrap-Tools.ps1`](../scripts/Bootstrap-Tools.ps1) (without `-DownloadMissing`) and verifies [`tools/SensorCli/SensorCli.csproj`](../tools/SensorCli/SensorCli.csproj) compiles cleanly in `Release` mode. (See [`docs/prerequisites-and-setup.md`](prerequisites-and-setup.md).) |
| **4. `mVolt+` Helpers** | `Invoke-Mvolt throws on invalid CLI flag` | Dot-sources [`scripts/MvoltHelpers.ps1`](../scripts/MvoltHelpers.ps1) and verifies `Invoke-Mvolt` catches a non-zero exit code from `mVolt+.exe` (GUI-subsystem binary) when passed an invalid flag (`--info`). |
| | `Get-MvoltStatus returns valid GPU JSON` | Calls `mVolt+ --status` via `Get-MvoltStatus` and verifies valid JSON telemetry with a non-empty `gpu` property is returned. |
| **5. Hardware Discovery** | `Inspect-System.ps1` | Runs [`scripts/Inspect-System.ps1`](../scripts/Inspect-System.ps1) and confirms CPU microcode is decoded to hex (`0x...`) and `[mVolt+ --status]` is queried. |
| **6. Crash Forensics** | `Diagnose-Crashes.ps1` | Runs [`scripts/Diagnose-Crashes.ps1`](../scripts/Diagnose-Crashes.ps1) (`-HoursBack 24`) and verifies all 4 forensic sections (GPU TDRs, WHEA, Reboots/BugChecks, App Crashes) execute cleanly. (See [`docs/crash-diagnostics-guide.md`](crash-diagnostics-guide.md).) |
| **7. CPU Power Plan** | `Manage-CpuPowerPlan.ps1` | Runs [`scripts/Manage-CpuPowerPlan.ps1`](../scripts/Manage-CpuPowerPlan.ps1) with `-Action Backup` to a temporary `.pow` file, verifies the file size (`>= 1 KB`), checks `-Action Status` output for `PERFEPP`, and removes the temporary file. (See [`docs/cpu-tuning-guide.md`](cpu-tuning-guide.md).) |
| **8. Profile Validation** | `Apply-Gemini-v1.0-4080.ps1 -DryRun` | Runs [`profiles/i7-13700k-rtx4080/Apply-Gemini-v1.0-4080.ps1`](../profiles/i7-13700k-rtx4080/Apply-Gemini-v1.0-4080.ps1) with `-DryRun -SkipGpuCheck` to verify privilege, binary, and status checks without writing to the GPU. (See [`docs/case-studies/01-i7-13700k-rtx4080-gigabyte.md`](case-studies/01-i7-13700k-rtx4080-gigabyte.md).) |
| **9. Sensor Telemetry** | `SensorCli.exe 1` | Runs a 1-sample read from [`tools/SensorCli/Program.cs`](../tools/SensorCli/Program.cs), confirms CPU telemetry is present, and verifies all `=== <Hardware> ===` headers contain only clean printable ASCII characters (`0x20–0x7E`) with no corrupted SPD bytes. |

---

## 4. Adding New Tests

When adding a new script under [`scripts/`](../scripts/) or a new hardware profile under [`profiles/`](../profiles/):
1. **AST Syntax Check is automatic:** Any `.ps1` file placed in `scripts/*.ps1`, `profiles/*/*.ps1`, or `tests/*.ps1` is automatically discovered and syntax-checked by `Invoke-SmokeTests.ps1`.
2. **Support `-DryRun` on profile scripts:** Follow the pattern in [`profiles/i7-13700k-rtx4080/Apply-Gemini-v1.0-4080.ps1`](../profiles/i7-13700k-rtx4080/Apply-Gemini-v1.0-4080.ps1) so `Invoke-SmokeTests.ps1` can validate new profiles without modifying live hardware state.
3. **Add a `Run-Test` block:** Add a new `Run-Test "Description" -Skip:$SkipHardwareTests { ... }` block to [`tests/Invoke-SmokeTests.ps1`](../tests/Invoke-SmokeTests.ps1) and run `.\tests\Invoke-SmokeTests.ps1` to confirm `0 Failed` before committing.
