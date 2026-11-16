# Takes the README screenshots in a COPY of the game folder (never the folder you play in):
#   .\run.ps1 -Game "B:\Games\sacred-copy"
# Needs Sacred Gear (and SacredBild) in that folder, savegame 1 with a hero, and this repository's mods.
param([Parameter(Mandatory)][string]$Game, [string]$Save = '1', [string]$Bild = '', [string[]]$Only = @())
$ErrorActionPreference = 'Stop'
if (-not $Bild) { $Bild = Join-Path $PSScriptRoot '..\..\..\sacred-bild' }
$repo = Split-Path (Split-Path $PSScriptRoot)
$mods = Join-Path $Game 'mods'
function Sync($name, $from) { Remove-Item (Join-Path $mods $name) -Recurse -Force -ErrorAction SilentlyContinue; Copy-Item $from (Join-Path $mods $name) -Recurse }
Sync 'shots' $PSScriptRoot
Sync 'autosave' "$repo\src\autosave"
Sync 'shared-stash' "$repo\src\shared-stash"
# The loot filter and the layout editor live in the sacred-bild repository (gear\examples). With -gear-auto they would
# run their own self tests, so their copies here are made plain mods (automation = false).
foreach ($m in 'lootfilter', 'layout') {
    Sync $m "$Bild\gear\examples\$m"
    (Get-Content (Join-Path $mods "$m\mod.lua")) -replace 'automation = true', 'automation = false' | Set-Content (Join-Path $mods "$m\mod.lua")
}
"return { min_quality = 'magic' }" | Set-Content (Join-Path $mods 'lootfilter\config.lua')
# The Mods screen lists every installed mod, so the driver must not be a mod of its own there: this runs inside a copy of
# the autosave mod (automation on) instead.
function Mods-Shot {
    $m = Join-Path $mods 'autosave'
    (Get-Content "$m\mod.lua") -replace "version = '", "automation = true, version = '" | Set-Content "$m\mod.lua"
    Add-Content "$m\main.lua" "`nif gear.auto then gear.task(function() gear.auto.wait_for_menu(120) if gear.auto.wait_for_game(180) then gear.wait(5) gear.auto.press('f11') gear.wait(1.5) gear.auto.screenshot('mod-manager') end gear.auto.quit(0) end) end"
}
function Run($instance, $modlist, $timeout = 150) {
    $p = Start-Process (Join-Path $Game 'Sacred.exe') -WorkingDirectory $Game -PassThru -ArgumentList "-gear-auto -gear-instance=$instance -gear-load=$Save -gear-mods=$modlist -gear-timeout=$timeout"
    $p.WaitForExit()
    "$instance exit $($p.ExitCode)"
}
foreach ($phase in $(if ($Only) { $Only } else { "mods","loot","layout","autosave" })) {
    Sync 'shots' $PSScriptRoot
    "return {phase = '$phase'}" | Set-Content (Join-Path $mods 'shots\config.lua')
    $extra = if ($phase -eq 'autosave') { 'autosave,' } elseif ($phase -eq 'loot') { 'lootfilter,' } elseif ($phase -eq 'layout') { 'layout,' } else { 'lootfilter,layout,autosave,shared-stash,' }
    if ($phase -eq 'mods') {
        Remove-Item (Join-Path $mods 'shots') -Recurse -Force
        Mods-Shot
        Run 'shot-mods' ($extra.TrimEnd(','))
        Sync 'autosave' "$repo\src\autosave"
        continue
    }
    Run "shot-$phase" "${extra}shots"
}
if ($Only -and $Only -notcontains 'stash') { return }
# the shared stash: fill it from the backpack, then open it from the chest window
foreach ($st in 'deposit', 'ui') {
    "return {selftest = '$st', selftest_slot = $Save}" | Set-Content (Join-Path $mods 'shared-stash\config.lua')
    Run "shot-stash-$st" 'shared-stash'
}
