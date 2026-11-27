$ErrorActionPreference = 'Stop'
$base = Join-Path ([IO.Path]::GetTempPath()) ('squad-test-' + [guid]::NewGuid())
$previousLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $base 'data'
    $root = Join-Path $base 'WoW'
    $addonsDir = Join-Path $root '_forever_\Interface\AddOns'
    New-Item -ItemType Directory -Force -Path $addonsDir | Out-Null
    New-Item -ItemType File -Path (Join-Path $root '_forever_\Wow.exe') | Out-Null
    foreach ($folder in @('A','B')) { New-Item -ItemType Directory -Path (Join-Path $addonsDir $folder) | Out-Null }
    $catalogFile = Join-Path $base 'catalog.json'
    @{ addons = @(@{name='A';curseforge_id=1}); optional_addons = @(@{name='B';curseforge_id=2}) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $catalogFile
    . ./sync.ps1 -WowRoot $root -Addons $catalogFile
    New-Item -ItemType Directory -Force -Path $Data | Out-Null
    @{ '1' = @{file_id=1;folders=@('A')}; '2' = @{file_id=1;folders=@('B')} } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Data 'state.json')
    $script:Requested = @()
    function Get-ForeverFile($projectId) { $script:Requested += [int]$projectId; return @{id=1;displayName='current'} }
    function Get-Process { return $null }
    if ((Invoke-Sync) -ne 0 -or ($script:Requested -join ',') -ne '1') { throw 'Default squad profile installed an extra' }
    @{profile='full'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Data 'config.json')
    $script:Requested = @()
    if ((Invoke-Sync) -ne 0 -or ($script:Requested -join ',') -ne '1,2') { throw 'Full profile lost an optional addon' }
    function Get-Process { return @{ProcessName='Wow'} }
    $script:Requested = @()
    if ((Invoke-Sync) -ne 75 -or $script:Requested.Count -ne 0) { throw 'Running game did not defer updates' }
    $bundle = (Get-Content addons.json -Raw | ConvertFrom-Json).ui_bundle
    $resolved = Resolve-Addon $bundle
    $script:BundleFile = (Resolve-Path SquadUI.zip).Path
    function Invoke-WebRequest { param([switch]$UseBasicParsing, $UserAgent, $OutFile, $Uri); Copy-Item -LiteralPath $script:BundleFile -Destination $OutFile }
    $zip = Join-Path $base 'ui.zip'
    $folders = @(Save-Addon $resolved.projectId $resolved.file $zip)
    if (($folders -join ',') -ne 'SquadUI') { throw 'Bundle folder did not resolve' }
    $resolved.file.sha256 = '0' * 64
    $caught = $false
    try { Save-Addon $resolved.projectId $resolved.file $zip | Out-Null } catch { $caught = $_.Exception.Message -match 'checksum' }
    if (-not $caught) { throw 'Changed bundle was accepted' }
    $tokens = $null; $errors = $null
    [Management.Automation.Language.Parser]::ParseFile((Resolve-Path install.ps1), [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) { throw ($errors | Out-String) }
    Write-Host 'Windows: squad/full selection, game guard, package checksum and installer syntax passed'
} finally {
    $env:LOCALAPPDATA = $previousLocalAppData
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
