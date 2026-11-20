<#
  Installs the VeylCore integration into an ox_inventory (tested: v2.48.1).
  Usage:  powershell -ExecutionPolicy Bypass -File install-ox-integration.ps1 -OxInventoryPath "C:\path\to\resources\[ox]\ox_inventory"

  What it does (idempotent):
    1. Copies modules/bridge/veyl (server.lua, client.lua) into ox_inventory.
    2. Appends VeylCore items to data/items.lua once (between marker comments).
    3. Backs up data/shops.lua to data/shops.lua.veyl-backup and replaces it with an empty table:
       ox's default shops pay with money items, which VeylCore does not use (veyl_shops sells instead).
#>
param([Parameter(Mandatory = $true)][string]$OxInventoryPath)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ox = (Resolve-Path -LiteralPath $OxInventoryPath).ProviderPath

if (-not (Test-Path -LiteralPath (Join-Path $ox 'modules\bridge\server.lua'))) { throw "Not an ox_inventory folder: $ox" }

# 1. Bridge
$bridgeDest = Join-Path $ox 'modules\bridge\veyl'
[System.IO.Directory]::CreateDirectory($bridgeDest) | Out-Null
foreach ($f in 'server.lua', 'client.lua') {
    Copy-Item -LiteralPath (Join-Path $here "ox_inventory\modules\bridge\veyl\$f") -Destination (Join-Path $bridgeDest $f) -Force
}
Write-Host 'Bridge installed: modules/bridge/veyl'

# 2. Items
$itemsPath = Join-Path $ox 'data\items.lua'
$items = [System.IO.File]::ReadAllText($itemsPath)
if ($items.Contains('>>> VeylCore items')) {
    Write-Host 'Items already present (skipped)'
} else {
    $snippet = [System.IO.File]::ReadAllText((Join-Path $here 'ox_inventory\veyl_items.lua'))
    $idx = $items.LastIndexOf('}')
    if ($idx -lt 0) { throw 'Unexpected items.lua format' }
    $patched = $items.Substring(0, $idx).TrimEnd() + "`r`n`r`n" + $snippet.TrimEnd() + "`r`n}`r`n"
    [System.IO.File]::WriteAllText($itemsPath, $patched, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host 'Items appended to data/items.lua'
}

# 3. Shops
$shopsPath = Join-Path $ox 'data\shops.lua'
$backup = "$shopsPath.veyl-backup"
if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $shopsPath -Destination $backup }
[System.IO.File]::WriteAllText($shopsPath, "-- Disabled by VeylCore: shops are provided by veyl_shops (numeric money). Original: shops.lua.veyl-backup`r`nreturn {}`r`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host 'Default ox shops disabled (backup kept)'

Write-Host ''
Write-Host 'Add to server.cfg before "ensure ox_inventory":'
Write-Host '  setr inventory:framework "veyl"'
Write-Host '  set inventory:accounts "[]"'
Write-Host '  setr inventory:target true'
