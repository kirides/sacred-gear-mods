# Takes the README's screenshots in a COPY of the game folder (never the folder you play in):
#   .\run.ps1 -Game "B:\Games\sacred-copy"
# Needs Sacred Gear (and SacredBild) in that folder and savegame 1 with a hero. Results: GearAutomation\shot-*\*.bmp
param([Parameter(Mandatory)][string]$Game, [string]$Save = '1')
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot)
$mods = Join-Path $Game 'mods'
function Sync($name, $from) { Remove-Item (Join-Path $mods $name) -Recurse -Force -ErrorAction SilentlyContinue; Copy-Item $from (Join-Path $mods $name) -Recurse }
function Run($instance, $modlist, $timeout = 150) {
    $p = Start-Process (Join-Path $Game 'Sacred.exe') -WorkingDirectory $Game -PassThru -ArgumentList "-gear-auto -gear-instance=$instance -gear-load=$Save -gear-mods=$modlist -gear-timeout=$timeout"
    $p.WaitForExit()
    "$instance exit $($p.ExitCode)"
}
Sync 'shots' $PSScriptRoot
Sync 'autosave' "$repo\src\autosave"
Sync 'shared-stash' "$repo\src\shared-stash"
Run 'shot-autosave' 'autosave,shots'
# the shared stash: fill it from the backpack, then open it from the chest window
foreach ($st in 'deposit', 'ui') {
    "return {selftest = '$st', selftest_slot = $Save}" | Set-Content (Join-Path $mods 'shared-stash\config.lua')
    Run "shot-stash-$st" 'shared-stash'
}
