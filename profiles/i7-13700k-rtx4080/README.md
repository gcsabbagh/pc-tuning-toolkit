# Profile: i7-13700K + Gigabyte RTX 4080

Saved settings, backups and benchmark logs from [Case Study #1](../../docs/case-studies/01-i7-13700k-rtx4080-gigabyte.md).

Scripts stay at the top level so the smoke tests (`profiles/*/*.ps1`) pick them up.

## Scripts

| File | Purpose |
| :--- | :--- |
| [`Apply-Gemini-v1.0-4080.ps1`](Apply-Gemini-v1.0-4080.ps1) | Applies the RTX 4080 Rock-Solid Gaming profile via mVolt+ (400 W, +60 Core, +120 XBar, +1000 Mem). `-DryRun` prints without touching the GPU. |
| [`Apply-SmartHighPerf-13700K.ps1`](Apply-SmartHighPerf-13700K.ps1) | Applies the Option B `SmartHighPerf` power plan (67 W → 22 W idle). |

## Configs & notes

| Path | Contents |
| :--- | :--- |
| [`mvolt-gemini-v1.0-profile.json`](mvolt-gemini-v1.0-profile.json) | Exported mVolt+ profile store (Gemini v1.0). |
| [`nvidia-display-config.json`](nvidia-display-config.json) | NVIDIA settings per display for [`scripts/Set-NvDisplayConfig.ps1`](../../scripts/Set-NvDisplayConfig.ps1): `pg27uqr` (V-Sync On, cap 155 for 160 Hz G-Sync) and `apolloVirtDisplay` (V-Sync Off, cap = client fps − 3). Apollo's state/prep commands call it. See [Case Study #2](../../docs/case-studies/02-apollo-streaming-steam-deck.md). |
| [`process-lasso-rules.md`](process-lasso-rules.md) | Process Lasso rules: games on P-cores, background apps and Sunshine on E-cores. |
| [`benchmarks/`](benchmarks/) | FurMark 2 per-run CSVs and scores for every sweep step, plus the CPU stress baseline. |

## Backups (pre-tuning state, local only)

`backups/` is git-ignored. These files are this machine's own settings and are not published.

| Path | Contents |
| :--- | :--- |
| `backups/Bitsum_Original_Backup.pow` | The original `Bitsum Highest Performance` power plan. Restore with `.\scripts\Manage-CpuPowerPlan.ps1 -Action Restore -BackupFile <path>`. |
| `backups/msi-afterburner/` | Copy of `C:\Program Files (x86)\MSI Afterburner\Profiles` from before mVolt+ tuning. |

What is in the Afterburner backup:

- `VEN_10DE&DEV_2704…cfg` is the RTX 4080. Its `Profile1` slot is the prior OC from case study row 0 (117% power, custom V/F curve, +1200 Mem), and `Profile2`/`Profile3` hold older experiments. `[Startup]` is empty, so nothing applied at boot.
- `VEN_0000&DEV_0000…cfg` is a placeholder-device entry, not real hardware. Afterburner probably wrote it once while it couldn't identify the GPU (for example during a driver reinstall). It carries a startup OC that looks like `Profile1`. It is kept as found.
- `VEN_8086&DEV_A780…cfg` is the i7-13700K's integrated UHD 770 GPU. It has no settings.
- `Profile1.cfg`–`Profile3.cfg` (31 bytes each) are Afterburner's empty global profile-slot stubs (`ProfileContents=1` only).
- `backup/` is Afterburner's own older (2023) copy of its config, with no OC settings.
