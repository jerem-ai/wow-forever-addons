<#
Keeps the group's WoW Forever addons installed and current on Windows.

install.ps1 saves this file to %LOCALAPPDATA%\wow-forever-addons\ and a scheduled task runs it
at logon and once a day. Each run reads addons.json from GitHub (the list only, never code),
installs anything new and updates anything with a newer Forever build.

  powershell -NoProfile -ExecutionPolicy Bypass -File sync.ps1 [-WowRoot "D:\Games\World of Warcraft"] [-FindOnly]

Exit codes: 0 all good, 1 something failed, 2 WoW Forever not found.
#>
param([string]$WowRoot, [switch]$FindOnly, [string]$Addons)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$AddonsUrl = 'https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/addons.json'
$Forever = 88568  # CurseForge gameVersionTypeId for WoW Forever (1.60.x)
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'
$Data = Join-Path $env:LOCALAPPDATA 'wow-forever-addons'
$script:LogLines = New-Object System.Collections.Generic.List[string]

function Say([string]$msg) { Write-Host $msg; $script:LogLines.Add($msg) }

function Read-Json([string]$path) {
    if (Test-Path -LiteralPath $path) {
        try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { }
    }
    return $null
}

function Find-WowRoot([string]$explicit) {
    $candidates = @()
    if ($explicit) { $candidates += $explicit }
    foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
                     'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft') {
        $p = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).InstallPath
        if ($p) { $p = $p.TrimEnd('\'); $candidates += $p; $candidates += (Split-Path $p -Parent) }
    }
    foreach ($drive in Get-PSDrive -PSProvider FileSystem) {
        foreach ($sub in 'Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft',
                         'World of Warcraft', 'Games\World of Warcraft', 'Battle.net\World of Warcraft') {
            $candidates += (Join-Path $drive.Root $sub)
        }
    }
    foreach ($root in $candidates) {
        if ($root -and (Test-Path -LiteralPath (Join-Path $root '_forever_\Wow.exe'))) {
            return (Resolve-Path -LiteralPath $root).Path
        }
    }
    return $null
}

function Get-AddonList {
    $cache = Join-Path $Data 'addons.cache.json'
    $source = if ($Addons) { $Addons } else { $AddonsUrl }
    try {
        $raw = if (Test-Path -LiteralPath $source) { Get-Content -LiteralPath $source -Raw }
               else { (Invoke-WebRequest -UseBasicParsing -UserAgent $UA -Uri $source).Content }
        $list = ($raw | ConvertFrom-Json).addons
        if (Test-Path -LiteralPath $Data) { Set-Content -LiteralPath $cache -Value $raw -Encoding UTF8 }
        return $list
    } catch {
        $cached = Read-Json $cache
        if ($cached) {
            Say "WARNING addon list unreachable ($($_.Exception.Message)); using the copy from the last sync"
            return $cached.addons
        }
        throw
    }
}

function Get-ForeverFile($projectId) {
    $list = Invoke-RestMethod -UserAgent $UA -Uri ("https://www.curseforge.com/api/v1/mods/$projectId/files" +
        "?pageIndex=0&pageSize=50&sort=dateCreated&sortDescending=true&gameVersionTypeId=$Forever")
    foreach ($releaseType in 1, 2, 3) {  # release, then beta, then alpha
        $file = $list.data | Where-Object { $_.gameVersionTypeIds -contains $Forever -and $_.releaseType -eq $releaseType } |
            Select-Object -First 1
        if ($file) { return $file }
    }
    return $null
}

function Save-Addon($projectId, $file, [string]$zip) {
    Invoke-WebRequest -UseBasicParsing -UserAgent $UA -OutFile $zip `
        -Uri "https://www.curseforge.com/api/v1/mods/$projectId/files/$($file.id)/download"
    $size = (Get-Item -LiteralPath $zip).Length
    if ($file.fileLength -and $size -ne $file.fileLength) { throw "download is $size bytes, expected $($file.fileLength)" }
    $folders = @{}
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        foreach ($e in $z.Entries) {
            $name = $e.FullName.Replace('\', '/')
            if ($name.StartsWith('/') -or $name -match '(^|/)\.\.(/|$)' -or $name -match '^[A-Za-z]:') {
                throw "unsafe path in zip: $($e.FullName)"
            }
            $parts = $name.Split('/')
            if ($parts.Count -gt 1 -and $parts[0]) { $folders[$parts[0]] = $true }
        }
    } finally { $z.Dispose() }
    return @($folders.Keys | Sort-Object)
}

function Invoke-Sync {
    $config = Read-Json (Join-Path $Data 'config.json')
    $root = Find-WowRoot $(if ($WowRoot) { $WowRoot } elseif ($config) { $config.wow_root })
    if (-not $root) {
        Say 'WoW Forever not found (no _forever_\Wow.exe). Install it through Battle.net first, or rerun the install with -WowRoot.'
        return 2
    }
    $addonsDir = Join-Path $root '_forever_\Interface\AddOns'
    Say "WoW Forever: $root"
    if ($FindOnly) { return 0 }

    New-Item -ItemType Directory -Force -Path $addonsDir | Out-Null
    $statePath = Join-Path $Data 'state.json'
    $state = @{}
    $saved = Read-Json $statePath
    if ($saved) { foreach ($p in $saved.PSObject.Properties) { $state[$p.Name] = $p.Value } }
    $tmp = Join-Path $env:TEMP ('wow-forever-addons-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $failed = 0
    try {
        foreach ($a in Get-AddonList) {
            $pid_ = [string]$a.curseforge_id
            try {
                $file = Get-ForeverFile $pid_
                if (-not $file) { throw 'no Forever file on CurseForge' }
                $have = $state[$pid_]
                if ($have -and $have.file_id -eq $file.id -and
                    -not (@($have.folders) | Where-Object { -not (Test-Path -LiteralPath (Join-Path $addonsDir $_)) })) {
                    Say ('CURRENT {0}: {1}' -f $a.name, $file.displayName)
                    continue
                }
                $zip = Join-Path $tmp "$pid_.zip"
                $folders = Save-Addon $pid_ $file $zip
                Expand-Archive -LiteralPath $zip -DestinationPath $addonsDir -Force
                $state[$pid_] = [pscustomobject]@{ file_id = $file.id; folders = $folders }
                Say ('{0} {1}: {2}' -f $(if ($have) { 'UPDATED' } else { 'OK     ' }), $a.name, $file.displayName)
            } catch {
                Say ('FAILED  {0}: {1}' -f $a.name, $_.Exception.Message)
                $failed++
            }
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $Data) { $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding UTF8 }
    Say "AddOns folder: $addonsDir"
    if ($failed) { return 1 }
    return 0
}

$code = Invoke-Sync
if (Test-Path -LiteralPath $Data) {
    $log = Join-Path $Data 'sync.log'
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $log) { $lines.AddRange([string[]]@(Get-Content -LiteralPath $log | Select-Object -Last 2000)) }
    $lines.Add(('== {0} exit {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $code))
    $lines.AddRange($script:LogLines)
    Set-Content -LiteralPath $log -Value $lines -Encoding UTF8
}
exit $code
