<#
Installs the WoW Forever addon sync on Windows. Run in PowerShell (no admin needed):

  irm https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.ps1 | iex

WoW somewhere unusual:  $env:WOW_FOREVER_ROOT = 'D:\Games\World of Warcraft'; irm ... | iex
Also install WowUp-CF:  $env:WOW_FOREVER_WOWUP = '1'; irm ... | iex
Remove the sync:        $env:WOW_FOREVER_UNINSTALL = '1'; irm ... | iex

Saves sync.ps1 to %LOCALAPPDATA%\wow-forever-addons\, adds a scheduled task that runs it at logon
and once a day, then runs the first sync. Installed addons are never removed.
#>
function Install-WowForeverAddons([string]$WowRoot, [switch]$WithWowUp, [switch]$Uninstall) {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $repo = 'https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main'
    $data = Join-Path $env:LOCALAPPDATA 'wow-forever-addons'
    $sync = Join-Path $data 'sync.ps1'
    $taskName = 'WoW Forever addons sync'
    $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\wow-forever-addons-sync.cmd'
    $runSync = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$sync`""
    function Get-TaskFolder { $s = New-Object -ComObject Schedule.Service; $s.Connect(); $s.GetFolder('\') }

    if ($Uninstall) {
        try { (Get-TaskFolder).DeleteTask($taskName, 0) } catch { }
        Remove-Item -LiteralPath $startup -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $data -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host 'Removed the sync task and its files. Installed addons were left in place.'
        return
    }

    New-Item -ItemType Directory -Force -Path $data | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri "$repo/sync.ps1" -OutFile $sync
    if ($WowRoot) {
        @{ wow_root = $WowRoot } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $data 'config.json') -Encoding UTF8
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sync -FindOnly
    if ($LASTEXITCODE -eq 2) {
        Write-Host "RESULT: WoW Forever not found. Set `$env:WOW_FOREVER_ROOT to your World of Warcraft folder and run the install again."
        return
    }

    # Task Scheduler's COM API, not the ScheduledTasks cmdlets: those go through CIM, which
    # refuses some non-admin sessions.
    $me = [Security.SecurityElement]::Escape([Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Keeps WoW Forever addons current: https://github.com/jerem-ai/wow-forever-addons</Description></RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled><UserId>$me</UserId><Delay>PT2M</Delay></LogonTrigger>
    <CalendarTrigger><StartBoundary>2026-01-01T12:00:00</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger>
  </Triggers>
  <Principals><Principal id="Author"><UserId>$me</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT30M</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>$([Security.SecurityElement]::Escape($runSync))</Arguments></Exec></Actions>
</Task>
"@
    try {
        $folder = Get-TaskFolder
        $null = $folder.RegisterTask($taskName, $xml, 6, $null, $null, 3)  # create or update; interactive token
        $null = $folder.GetTask($taskName)
        Remove-Item -LiteralPath $startup -Force -ErrorAction SilentlyContinue
        Write-Host "Daily sync on: scheduled task '$taskName' (at logon and 12:00)"
    } catch {
        # The Startup folder still runs the sync at every logon.
        New-Item -ItemType Directory -Force -Path (Split-Path $startup) | Out-Null
        Set-Content -LiteralPath $startup -Encoding ASCII -Value "@start `"`" /min powershell.exe $runSync"
        Write-Host "Sync on at every logon (Startup folder; the scheduled task was refused: $($_.Exception.Message.Trim()))"
    }

    if ($WithWowUp) {
        $url = 'https://github.com/WowUp/WowUp.CF/releases/download/v2.25.4/WowUp-CF-Setup-2.25.4.exe'
        $exe = Join-Path $env:TEMP 'WowUp-CF-Setup-2.25.4.exe'
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $exe
        $hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLower()
        if ($hash -eq '1cbfe659a716a9b6694c8162a60bf60edac2c0c92bee5a213df519fb4e3a0a47') {
            Start-Process -FilePath $exe -ArgumentList '/S' -Wait
            Write-Host 'WowUp-CF 2.25.4 installed'
        } else {
            Write-Host "WowUp-CF skipped: checksum $hash does not match the release"
        }
        Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
    }

    Write-Host 'First sync:'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sync
    $result = @{ 0 = 'all addons installed'; 1 = 'some addons failed, see the lines above'; 2 = 'WoW Forever not found' }[$LASTEXITCODE]
    Write-Host "RESULT: $result (log: $data\sync.log)"
}

Install-WowForeverAddons -WowRoot $env:WOW_FOREVER_ROOT -WithWowUp:($env:WOW_FOREVER_WOWUP -eq '1') -Uninstall:($env:WOW_FOREVER_UNINSTALL -eq '1')
