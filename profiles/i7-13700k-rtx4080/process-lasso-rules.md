# Process Lasso Rule Set — i7-13700K

Standard game and background-app rules for the i7-13700K (`Threads 0–15` = 8 hyper-threaded P-Cores, `Threads 16–23` = 8 E-Cores). Assumes the `Bitsum Highest Performance` plan with [`Apply-SmartHighPerf-13700K.ps1`](Apply-SmartHighPerf-13700K.ps1) applied is the default power plan.

Config lives in `C:\ProgramData\ProcessLasso\config\prolasso.ini`. Before editing it by hand, back it up, close the Lasso GUI, and stop the `ProcessGovernor` service; otherwise the GUI can overwrite your changes.

---

## 1. Per-Game Rule

| Setting | Value | Why |
|---|---|---|
| **CPU Affinity** | `0-15` (P-Cores) | Keeps main/render threads off the E-Cores. Use affinity **or** a CPU Set, not both. |
| **Priority** | Normal (no rule) | `High` gains little and can starve audio, input, and Sunshine. |
| **I/O Priority** | Normal (no rule) | Raising it mostly speeds up loading screens and can make other I/O stutter. |
| **Efficiency Mode** | Off | Prevents Windows from throttling the game when it loses focus. |
| **ProBalance** | Excluded | Stops ProBalance from lowering the game's priority, e.g. while it's in the background during a stream. |
| **Power Plan** | None | Bitsum (SmartHighPerf) is already the default; per-game plans and Gaming Mode add nothing. |
| **GPU Preference** | High performance (`2`) | Only matters with the iGPU enabled; harmless otherwise. |

**Watch out for:**
- **Rule the real game process, not its launcher.** For Unreal Engine titles that's usually `*-Win64-Shipping.exe` (e.g. `deadzone2steam-win64-shipping.exe`).
- **Kernel anti-cheat titles** (Easy Anti-Cheat, BattlEye, Vanguard): skip the affinity rule, or use a CPU Set instead. Some anti-cheat resets or flags affinity changes.

## 2. Fewer Per-Game Rules

- **Unreal Engine wildcard:** `*-win64-shipping.exe` → `0-15` covers most UE games in one rule. *(Untested here; verify on one game in the Lasso log before relying on it.)*
- **Keep `steam.exe` on `0-15`.** A game inherits its launcher's affinity, so with Steam on the P-cores, Steam games without a rule start on the P-cores anyway. Moving Steam to the E-Cores would also move those games there. Put `steamwebhelper.exe` (the Steam UI) on the E-Cores instead.

## 3. Background Apps

| Apps | Affinity | Priority |
|---|---|---|
| `discord.exe`, `msedge.exe`, `chrome.exe`, `steamwebhelper.exe`, Epic / EA launchers, WhatsApp, Spotify | `16-23` | Normal |
| Sunshine / Apollo: `sunshine.exe`, `sunshinesvc.exe`, `sunshine_wgc_capture.exe`, `sunshine_display_helper.exe` | `16-23` | High |
| Plex, Google Drive | `16-23` | Normal or Below Normal |

Sunshine stays at **High** so it wins CPU contention over the (Normal-priority) game. It was previously on `0-3`, sharing the game's busiest threads and core 0 (where much of Windows' system work runs). Apollo's debug `Frame processing latency` (worst frame per 20 s window, 90 fps AV1 to a Steam Deck): `0-3` had 7 of 30 windows at `19–43 ms`; `16-23` had 0 of 15, median `5.1 ms`.

## 4. Exceptions

- **Heavily multithreaded games** (Cities: Skylines II, late-game Frostpunk 2) and **first launch after an update** (shader compilation) can benefit from all 24 threads. Use `0-23` or no affinity rule.

## 5. Keep Off

SmartTrim, standby-list clearing, CPU Limiter, Foreground Boosting, timer-resolution override, instance limits.

---

## `prolasso.ini` Reference

| Rule | Key | Entry format |
|---|---|---|
| Affinity | `DefaultAffinitiesEx` (`[ProcessDefaults]`) | `game.exe,0,0-15` |
| CPU Set | `CPUSets` | `game.exe,(0-15)` |
| Priority | `DefaultPriorities` | `sunshine.exe,high` |
| Efficiency Mode off | `EfficiencyMode` (`[ProcessAllowances]`) | `game.exe,0` |
| ProBalance exclusion | `OocExclusions` (`[OutOfControlProcessRestraint]`) | `game.exe` |
| GPU preference | `DefaultGPUAdapterPreferences` | `<full exe path>,2` |
| Per-game power plan | `DefaultPowerSchemes` | leave empty |

Example: a new game plus the background set:

```ini
DefaultAffinitiesEx=*-win64-shipping.exe,0,0-15,newgame.exe,0,0-15,steam.exe,0,0-15,steamwebhelper.exe,0,16-23,discord.exe,0,16-23,msedge.exe,0,16-23,sunshine.exe,0,16-23,sunshinesvc.exe,0,16-23,sunshine_wgc_capture.exe,0,16-23,sunshine_display_helper.exe,0,16-23
DefaultPriorities=sunshine.exe,high,sunshinesvc.exe,high,sunshine_wgc_capture.exe,high,sunshine_display_helper.exe,high
OocExclusions=newgame.exe
```
