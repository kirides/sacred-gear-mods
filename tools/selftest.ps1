# Runs the self test of one mod in a COPY of the game folder (never the one you play in):
#   .\selftest.ps1 -Game "B:\Games\sacred-copy" -Mods lootfilter [-Config @{ lootfilter = '{test_quit = true}' }] [-Save 10] [-Timeout 300]
# The copy's mods folder is EMPTIED and filled with the given mods (from this repository's src) and the theme mod (src/sacred-theme). The game runs once with -gear-auto; the log is GearAutomation\<instance>\SacredGear.log.
param([Parameter(Mandatory)][string]$Game, [Parameter(Mandatory)][string[]]$Mods, [hashtable]$Config = @{}, [string]$Save = '10',
      [int]$Timeout = 300, [string]$Instance = 'selftest')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$modsDir = Join-Path $Game 'mods'
Remove-Item $modsDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item $modsDir -ItemType Directory | Out-Null
Copy-Item (Join-Path $repo 'src\sacred-theme') (Join-Path $modsDir 'sacred-theme') -Recurse
foreach ($m in $Mods) { Copy-Item (Join-Path $repo "src\$m") (Join-Path $modsDir $m) -Recurse }
foreach ($k in $Config.Keys) { "return $($Config[$k])" | Set-Content (Join-Path $modsDir "$k\config.lua") }
$list = (@('sacred-theme') + $Mods) -join ','
$p = Start-Process (Join-Path $Game 'Sacred.exe') -WorkingDirectory $Game -PassThru -ArgumentList "-gear-auto -gear-instance=$Instance -gear-load=$Save -gear-mods=$list -gear-timeout=$Timeout"
$p.WaitForExit()
"$Instance exit $($p.ExitCode)"
Get-Content (Join-Path $Game "GearAutomation\$Instance\SacredGear.log") | Select-String 'PASS|FAIL|passed|RmlUi (warning|error)'
