<#
.SYNOPSIS
    Applies the global NVIDIA driver settings for the display a game is about to run on.

.DESCRIPTION
    Each rig lists its displays in profiles\<Rig>\nvidia-display-config.json, keyed by display name,
    with named settings per display:

        {
          "pg27uqr":           { "vsync": "on",  "frameCap": 155 },
          "apolloVirtDisplay": { "vsync": "off", "frameCap": { "fromClientFps": -3, "min": 30 } }
        }

    Known settings are defined in $KnownSettings below (name -> NVIDIA setting ID(s) + value).
    To support another driver setting, add an entry there; displays can then use it by name.

      vsync     "on" | "off"
      frameCap  fixed fps (0 = limiter off), or { "fromClientFps": <offset>, "min": <floor> } to derive
                it from the stream client's fps (APOLLO_CLIENT_FPS / SUNSHINE_CLIENT_FPS, or -Fps)

    The settings are written to the driver's global Base Profile, so they apply to every display at
    once: -Target picks the display the next game will be shown on. Profile Inspector -silentImport
    merges into the existing profile, so every display in a file should list the same settings;
    otherwise a setting from one display is left behind when switching to another.

    Uses NVIDIA Profile Inspector (tools\bin\nvinspect), which requires Admin: run elevated
    (Apollo: "elevated": true). Each switch is logged to tools\bin\nvinspect\apollo-nvprofile.log.

.EXAMPLE
    # Apollo global_state_cmd: do = stream target, undo = local monitor
    .\scripts\Set-NvDisplayConfig.ps1 -Rig i7-13700k-rtx4080 -Target apolloVirtDisplay
    .\scripts\Set-NvDisplayConfig.ps1 -Rig i7-13700k-rtx4080 -Target pg27uqr
#>
param(
    # Folder name under profiles\ that holds nvidia-display-config.json.
    [Parameter(Mandatory)][string]$Rig,
    # Display key from nvidia-display-config.json (case-insensitive).
    [Parameter(Mandatory)][string]$Target,
    # Stream client frame rate; defaults to the value Apollo/Sunshine passes in the environment.
    [double]$Fps = 0,
    # Write the .nip to %TEMP% and print what would be imported, without touching the driver.
    [switch]$DryRun
)

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Inspector = Join-Path $RepoRoot "tools\bin\nvinspect\nvidiaProfileInspector.exe"
$LogFile = Join-Path $RepoRoot "tools\bin\nvinspect\apollo-nvprofile.log"
$ConfigPath = Join-Path $RepoRoot "profiles\$Rig\nvidia-display-config.json"

function Write-Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Write-Host $line
    if (-not $DryRun) { Add-Content -Path $LogFile -Value $line }
}

function Get-ClientFps {
    $f = $Fps
    # Apollo passes the client's requested frame rate; some Sunshine builds pass it in millihertz.
    if ($f -le 0) {
        $raw = if ($env:APOLLO_CLIENT_FPS) { $env:APOLLO_CLIENT_FPS } else { $env:SUNSHINE_CLIENT_FPS }
        [double]::TryParse("$raw", [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$f) | Out-Null
    }
    if ($f -gt 1000) { $f = $f / 1000 }
    if ($f -le 0) {
        Write-Log "WARN: no client fps in environment; defaulting to 120"
        $f = 120
    }
    return $f
}

# Known settings: config name -> driver setting(s) and a converter from the JSON value to a DWORD.
# Converters throw on invalid values.
$KnownSettings = [ordered]@{
    vsync = @{
        Ids     = @(@{ Id = "11041231"; Name = "Vertical Sync" })
        Convert = {
            param($v)
            switch ("$v") {
                "on"    { 1199655232 }   # Force on
                "off"   { 138504007 }    # Force off
                default { throw "vsync must be 'on' or 'off' (got '$v')" }
            }
        }
    }
    frameCap = @{
        Ids     = @(@{ Id = "277041154"; Name = "Frame Rate Limiter" }, @{ Id = "277041162"; Name = "Frame Rate Limiter for NVCPL" })
        Convert = {
            param($v)
            if ($v -is [System.Management.Automation.PSCustomObject]) {
                if ($null -eq $v.fromClientFps) { throw "frameCap object needs fromClientFps" }
                $min = if ($null -ne $v.min) { [int]$v.min } else { 30 }
                $cap = [Math]::Max($min, [int][Math]::Floor((Get-ClientFps)) + [int]$v.fromClientFps)
            } elseif ($v -is [int] -or $v -is [long]) {
                $cap = [int]$v
            } else {
                throw "frameCap must be an fps number or { fromClientFps, min } (got '$v')"
            }
            # Frame Rate Limiter is a 10-bit fps mask (max 1023); 0 = off.
            [Math]::Min(1023, [Math]::Max(0, $cap))
        }
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Log "ERROR: display config not found: $ConfigPath"
    exit 1
}
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$entry = $config.PSObject.Properties | Where-Object Name -eq $Target | Select-Object -First 1
if (-not $entry) {
    Write-Log "ERROR: unknown target '$Target' for rig $Rig (known: $($config.PSObject.Properties.Name -join ', '))"
    exit 1
}
$Target = $entry.Name

# Settings missing from this display would keep whatever another display last set.
$allNames = @($config.PSObject.Properties | ForEach-Object { $_.Value.PSObject.Properties.Name }) | Sort-Object -Unique
$missing = $allNames | Where-Object { $_ -notin $entry.Value.PSObject.Properties.Name }
if ($missing) {
    Write-Log "WARN: $Target does not set $($missing -join ', '); the previous value stays in the driver."
}

$rows = @()
$summary = @()
foreach ($s in $entry.Value.PSObject.Properties) {
    $def = $KnownSettings[$s.Name]
    if (-not $def) {
        Write-Log "ERROR: unknown setting '$($s.Name)' in $Target (known: $($KnownSettings.Keys -join ', '))"
        exit 1
    }
    try { $dword = & $def.Convert $s.Value }
    catch { Write-Log "ERROR: ${Target}.$($s.Name): $($_.Exception.Message)"; exit 1 }
    foreach ($id in $def.Ids) { $rows += @{ Id = $id.Id; Name = $id.Name; Value = $dword } }
    $shown = if ($s.Value -is [System.Management.Automation.PSCustomObject]) { $dword } else { $s.Value }
    $summary += "$($s.Name)=$shown"
}

$settingsXml = ($rows | ForEach-Object {
@"
      <ProfileSetting>
        <SettingNameInfo>$($_.Name)</SettingNameInfo>
        <SettingID>$($_.Id)</SettingID>
        <SettingValue>$($_.Value)</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>
"@
}) -join "`r`n"
$nipXml = @"
<?xml version="1.0" encoding="utf-8"?>
<ArrayOfProfile>
  <Profile>
    <ProfileName>Base Profile</ProfileName>
    <Executeables />
    <Settings>
$settingsXml
    </Settings>
  </Profile>
</ArrayOfProfile>
"@

$nip = Join-Path $env:TEMP "nvdisplay-$Target.nip"
[IO.File]::WriteAllText($nip, $nipXml, [Text.UTF8Encoding]::new($false))
Write-Log ("{0}: importing {1} ({2})" -f $Target, $nip, ($summary -join ", "))

if ($DryRun) {
    Write-Host "DryRun: would run `"$Inspector`" -silentImport `"$nip`"" -ForegroundColor Cyan
    exit 0
}

if (-not (Test-Path -LiteralPath $Inspector)) {
    Write-Log "ERROR: nvidiaProfileInspector.exe not found at $Inspector (run .\scripts\Bootstrap-Tools.ps1 -DownloadMissing)"
    exit 1
}
$p = Start-Process $Inspector -ArgumentList "-silentImport `"$nip`"" -PassThru
if (-not $p.WaitForExit(30000)) {
    $p | Stop-Process -Force
    Write-Log "ERROR: Profile Inspector did not exit within 30 s (is its window already open?)"
    exit 1
}
Write-Log "Profile Inspector exit code $($p.ExitCode)"
exit $p.ExitCode
