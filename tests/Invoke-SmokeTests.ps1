<#
.SYNOPSIS
    Non-destructive smoke test suite for the Agentic PC Tuning & Stability Toolkit.
    Verifies PowerShell AST syntax, .gitignore rules, Bootstrap-Tools, MvoltHelpers,
    Inspect-System, Diagnose-Crashes, Manage-CpuPowerPlan, Profile DryRun, and SensorCli
    without modifying GPU clocks or active power plans.
#>
param(
    [switch]$SkipHardwareTests
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$passed = 0
$failed = 0
$skipped = 0

function Run-Test {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$TestBlock,
        [switch]$Skip
    )
    if ($Skip) {
        Write-Host "  [SKIP] $Name" -ForegroundColor Yellow
        $script:skipped++
        return
    }
    try {
        & $TestBlock
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:passed++
    } catch {
        Write-Host "  [FAIL] $Name -> $($_.Exception.Message)" -ForegroundColor Red
        $script:failed++
    }
}

Write-Host "================ PC TUNING TOOLKIT SMOKE TESTS ================" -ForegroundColor Cyan

# 1. PowerShell AST Syntax Check across all repo scripts
$allScripts = Get-ChildItem -Path (Join-Path $RepoRoot "scripts\*.ps1"), (Join-Path $RepoRoot "profiles\*\*.ps1"), (Join-Path $RepoRoot "tests\*.ps1") -File
foreach ($s in $allScripts) {
    $relName = $s.FullName.Substring($RepoRoot.Length + 1)
    Run-Test "AST Syntax: $relName" {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$null, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            throw ($errors | ForEach-Object { $_.Message }) -join "; "
        }
    }
}

# 2. Static Policy Checks (No machine-specific scratch paths or removed mVolt+ flags in scripts)
Run-Test "Static Check: No hardcoded user scratch paths in scripts" {
    $hits = Select-String -Path (Join-Path $RepoRoot "scripts\*.ps1"), (Join-Path $RepoRoot "profiles\*\*.ps1") -Pattern "\\\.gemini\\antigravity\\scratch"
    if ($hits) {
        throw "Found hardcoded scratch path in: $($hits.Path -join ', ')"
    }
}

Run-Test "Static Check: No deprecated mVolt+ flags (--info / --reset) in scripts" {
    $hits = Select-String -Path (Join-Path $RepoRoot "scripts\*.ps1"), (Join-Path $RepoRoot "profiles\*\*.ps1") -Pattern "mvolt\s+--(info|reset)\b"
    if ($hits) {
        throw "Found invalid mVolt+ flag in: $($hits.Path -join ', ')"
    }
}

Run-Test "Static Check: .gitignore un-ignores tools/bin/.gitkeep properly" {
    $gi = Get-Content (Join-Path $RepoRoot ".gitignore") -Raw
    if ($gi -notmatch "!tools/bin/" -or $gi -notmatch "tools/bin/\*" -or $gi -notmatch "!tools/bin/\.gitkeep") {
        throw ".gitignore is missing the '!tools/bin/' + 'tools/bin/*' + '!tools/bin/.gitkeep' pattern."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot "tools\bin\.gitkeep"))) {
        throw "tools\bin\.gitkeep file is missing."
    }
}

Run-Test "Static Check: All relative Markdown links in README, AGENTS, and docs/ resolve" {
    $mdFiles = Get-ChildItem -Path (Join-Path $RepoRoot "*.md"), (Join-Path $RepoRoot "docs\*.md"), (Join-Path $RepoRoot "docs\*\*.md") -File
    $broken = @()
    foreach ($md in $mdFiles) {
        $content = Get-Content -LiteralPath $md.FullName -Raw
        $matches = [regex]::Matches($content, '\[[^\]]+\]\((?!https?:|mailto:|#)([^)#]+)(?:#[^)]*)?\)')
        foreach ($m in $matches) {
            $relTarget = $m.Groups[1].Value.Trim()
            $resolved = Join-Path $md.DirectoryName $relTarget
            if (-not (Test-Path -LiteralPath $resolved)) {
                $broken += "$($md.Name) -> $relTarget"
            }
        }
    }
    if ($broken.Count -gt 0) {
        throw "Broken markdown links: $($broken -join ', ')"
    }
}

# 3. Bootstrap-Tools & SensorCli Build
Run-Test "Bootstrap-Tools.ps1 & SensorCli build" -Skip:$SkipHardwareTests {
    $out = & (Join-Path $RepoRoot "scripts\Bootstrap-Tools.ps1") *>&1 | Out-String
    if ($out -notmatch "\[OK\] Built SensorCli\.exe successfully") {
        throw "Bootstrap-Tools did not build SensorCli.exe cleanly. Output:`n$out"
    }
}

# 4. MvoltHelpers error handling & status parsing
. (Join-Path $RepoRoot "scripts\MvoltHelpers.ps1")
$mvolt = Find-Mvolt -RepoRoot $RepoRoot

Run-Test "MvoltHelpers: Invoke-Mvolt throws on invalid CLI flag (--info)" -Skip:($SkipHardwareTests -or -not $mvolt) {
    $threw = $false
    try {
        Invoke-Mvolt $mvolt @("--info") *>$null
    } catch {
        $threw = $true
    }
    if (-not $threw) {
        throw "Invoke-Mvolt did not throw on invalid flag '--info'."
    }
}

Run-Test "MvoltHelpers: Get-MvoltStatus returns valid GPU JSON" -Skip:($SkipHardwareTests -or -not $mvolt) {
    $st = Get-MvoltStatus -MvoltPath $mvolt
    if (-not $st -or -not $st.gpu) {
        throw "Get-MvoltStatus returned null or missing 'gpu' field."
    }
}

# 5. Inspect-System.ps1
Run-Test "Inspect-System.ps1: Decodes microcode & queries GPU status" -Skip:$SkipHardwareTests {
    $out = & (Join-Path $RepoRoot "scripts\Inspect-System.ps1") *>&1 | Out-String
    if ($out -notmatch "Microcode Revision\s+:\s+0x[0-9A-Fa-f]+") {
        throw "Inspect-System did not output a formatted hex Microcode Revision (0x...)."
    }
    if ($mvolt -and $out -notmatch "\[mVolt\+ --status\]") {
        throw "Inspect-System did not run [mVolt+ --status]."
    }
}

# 6. Diagnose-Crashes.ps1
Run-Test "Diagnose-Crashes.ps1: Executes 24h event log scan cleanly" -Skip:$SkipHardwareTests {
    $out = & (Join-Path $RepoRoot "scripts\Diagnose-Crashes.ps1") -HoursBack 24 *>&1 | Out-String
    if ($out -notmatch "=== 1\. GPU DRIVER & TDR EVENTS" -or $out -notmatch "=== 4\. APPLICATION CRASHES") {
        throw "Diagnose-Crashes output missing expected sections."
    }
}

# 7. Manage-CpuPowerPlan.ps1 (Backup + Status)
Run-Test "Manage-CpuPowerPlan.ps1: Exports backup .pow and reads status" -Skip:$SkipHardwareTests {
    $tmpPow = Join-Path $RepoRoot "tools\bin\SmokeTest_Backup.pow"
    Remove-Item -LiteralPath $tmpPow -ErrorAction SilentlyContinue
    try {
        $out = & (Join-Path $RepoRoot "scripts\Manage-CpuPowerPlan.ps1") -Action Backup -BackupFile $tmpPow *>&1 | Out-String
        if (-not (Test-Path -LiteralPath $tmpPow) -or (Get-Item -LiteralPath $tmpPow).Length -lt 1024) {
            throw "Power plan backup file was not created or is empty."
        }
        $stOut = & (Join-Path $RepoRoot "scripts\Manage-CpuPowerPlan.ps1") -Action Status *>&1 | Out-String
        if ($stOut -notmatch "GUID Alias: PERFEPP") {
            throw "Manage-CpuPowerPlan Status did not list processor power settings."
        }
    } finally {
        Remove-Item -LiteralPath $tmpPow -ErrorAction SilentlyContinue
    }
}

# 8. Profile DryRun
Run-Test "Apply-Gemini-v1.0-4080.ps1: -DryRun validates without writing" -Skip:($SkipHardwareTests -or -not $mvolt) {
    $out = & (Join-Path $RepoRoot "profiles\i7-13700k-rtx4080\Apply-Gemini-v1.0-4080.ps1") -DryRun -SkipGpuCheck *>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $out -notmatch "\[DRY RUN\] All checks passed") {
        throw "Apply-Gemini-v1.0-4080.ps1 -DryRun failed. Output:`n$out"
    }
}

# 9. SensorCli 1-sample telemetry read + ASCII hardware name check
Run-Test "SensorCli.exe: Reads telemetry with clean ASCII hardware headers" -Skip:$SkipHardwareTests {
    $sensorExe = Join-Path $RepoRoot "tools\SensorCli\bin\Release\net8.0\SensorCli.exe"
    if (-not (Test-Path -LiteralPath $sensorExe)) {
        throw "SensorCli.exe not found at $sensorExe"
    }
    $out = & $sensorExe 1 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $out -notmatch "=== .* \(Cpu\) ===") {
        throw "SensorCli did not output a CPU hardware section."
    }
    $headerLines = ($out -split "`r?`n") | Where-Object { $_ -match "^=== " }
    foreach ($h in $headerLines) {
        if ($h.ToCharArray() | Where-Object { [int]$_ -lt 32 -or [int]$_ -gt 126 }) {
            throw "Non-ASCII or control character found in hardware header: $h"
        }
    }
}

Write-Host "`n================ SUMMARY: $passed Passed, $failed Failed, $skipped Skipped ================" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
if ($failed -gt 0) { exit 1 }
