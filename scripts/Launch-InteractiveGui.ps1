<#
.SYNOPSIS
    Helper for AI Agents running in non-interactive background shells to launch a GUI executable
    (like mVolt+.exe or OCCT.exe) directly onto the user's interactive Windows desktop session
    with Administrator privileges.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$ExecutablePath,
    [string]$Arguments = ""
)

if (-not (Test-Path $ExecutablePath)) {
    Write-Error "Executable not found: $ExecutablePath"
    return
}

$WorkDir = Split-Path -Parent $ExecutablePath
$TaskName = "Agent_Launch_Interactive_GUI"

$ActionParams = @{
    Execute          = $ExecutablePath
    WorkingDirectory = $WorkDir
}
if ($Arguments) { $ActionParams.Argument = $Arguments }

$Action = New-ScheduledTaskAction @ActionParams
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 2
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "Launched '$ExecutablePath' onto interactive desktop session for $env:USERNAME." -ForegroundColor Green
