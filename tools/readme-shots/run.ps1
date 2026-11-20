# Takes all the pictures of docs/images in a COPY of the game folder (never the folder you play in) and cuts them out:
#   .\run.ps1 -Game "B:\Games\sacred-copy"            everything
#   .\run.ps1 -Game "B:\Games\sacred-copy" -Only fight,chat    only these steps (names below)
#   .\run.ps1 -Game "B:\Games\sacred-copy" -CropOnly   cut the images again out of the shots already taken
# Needs in the copy: ddraw.dll (SacredBild) and SacredGear.dll of the build you want shown, 1600x900, and a savegame in slot -Save
# (default 10) with a hero and a few hostile creatures near: the author's test save is a Wood Elf (level 1) with a Dark Elf next
# to her, a chest and wolves in the same place. The game's mods folder is EMPTIED for every step and filled with the step's mods
# from this repository (so that the Mods screen lists only them): it must be a copy. Results: GearAutomation\shot-<step>\*.bmp,
# then crop.py (Python with Pillow) writes docs/images/* as crops.json says (10-30 px around each window).
# Server mods run without a server: the script hands what the server would send to the mod's own channel handlers (phase 'server').
param([Parameter(Mandatory)][string]$Game, [string]$Save = '10', [string[]]$Only = @(), [switch]$CropOnly)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot)
$mods = Join-Path $Game 'mods'

function Prepare($names, $config) {
    # $names: mod folders of src (and 'shots' = this folder); $config: @{ mod = 'lua table text' } written to mods\<mod>\config.lua
    Remove-Item $mods -Recurse -Force -ErrorAction SilentlyContinue
    New-Item $mods -ItemType Directory | Out-Null
    foreach ($n in $names) {
        if ($n -eq 'shots') { Copy-Item $PSScriptRoot (Join-Path $mods 'shots') -Recurse; Remove-Item (Join-Path $mods 'shots\run.ps1'), (Join-Path $mods 'shots\crop.py'), (Join-Path $mods 'shots\crops.json') }
        else { Copy-Item (Join-Path $repo "src\$n") (Join-Path $mods $n) -Recurse }
    }
    foreach ($k in $config.Keys) { "return $($config[$k])" | Set-Content (Join-Path $mods "$k\config.lua") }
}
function Run($instance, $slot, $modlist, $timeout = 240) {
    $load = if ($slot -eq '-') { '' } else { "-gear-load=$slot" }
    $p = Start-Process (Join-Path $Game 'Sacred.exe') -WorkingDirectory $Game -PassThru -ArgumentList "-gear-auto -gear-instance=shot-$instance $load -gear-mods=$modlist -gear-timeout=$timeout"
    $p.WaitForExit()
    "shot-$instance exit $($p.ExitCode)"
}
# One step = the mods in, the config, one run. The panels' open state is kept by Gear in mods\gear_layout.json: it is gone with the folder.
function Step($name, $modlist, $config = @{}, $slot = $Save, $timeout = 240) {
    if ($Only.Count -and ($Only -notcontains $name)) { return }
    $names = $modlist -split ','
    Prepare $names $config
    Run $name $slot $modlist $timeout
}
function Phase($name, $mod, $lua, $extra = @(), $slot = $Save) {
    # a phase of main.lua (this folder) with the mod, e.g. the Mods screen with clicks
    Step $name (@($mod) + $extra + 'shots' -join ',') @{ shots = $lua } $slot
}

if (-not $CropOnly) {
    # the self tests that take pictures
    Step 'artbars'    'art-bars,art-bars_selftest,companions'
    Step 'cc'         'custom-classes,custom-classes_selftest,companions'
    Step 'st'         'sector-tools,sector-tools_selftest'
    Step 'companions' 'companions,companions_selftest'
    Step 'compare'    'item-compare,item-compare_selftest,companions'
    Step 'we'         'world-events,world-events_selftest'
    Step 'boss'       'world-events,world-events_bosstest'
    Step 'chat'       'enhanced-chat,enhanced-chat_selftest' @{ 'enhanced-chat_selftest' = "{slot = $Save, quit = true}" }
    Step 'bsl'        'better-saveload,better-saveload_selftest' @{} $Save
    Step 'bounty'     'bounty,bounty_selftest' @{ bounty_selftest = "{phase = 'shots'}" }
    Step 'beditor'    'bounty,bounty_selftest' @{ bounty_selftest = "{phase = 'editor'}" }
    Step 'quests'     'bounty,quests_selftest' @{ quests_selftest = "{phase = 'shots'}" }
    Step 'stash-ui'   'shared-stash' @{ 'shared-stash' = "{selftest = 'ui', selftest_slot = $Save}" }
    Step 'layout'     'layout'
    # the auction house in a single player game (the market runs in the game itself); the hero gets gold first
    Step 'ah'         'auction-house,shots' @{ 'auction-house' = "{selftest = 'sp', selftest_slot = $Save}"; shots = "{phase = 'gold', gold = 50000}" } $Save 300
    # phases of main.lua
    Phase 'autosave' 'autosave' "{phase = 'autosave'}"
    Phase 'lf'       'lootfilter' "{phase = 'lootfilter'}"
    Phase 'fight'    'damagemeter' "{phase = 'fight'}" @('lootlog', 'sessiontracker')
    Phase 'twitch'   'twitch_integration' "{phase = 'twitch'}" @('twi_sacred')
    foreach ($w in 'achievements', 'buildsharer', 'serverfeed') {
        Phase "srv-$w" $w "{phase = 'server', which = '$w', press = true, wait = 8}"
    }
    Phase 'srv-questhelper' 'questhelper' "{phase = 'server', which = 'questhelper', press = true, clicks = {{522, 112}}}"
    # the Mods screen (F11): the mod is the second row of the list (README screenshots comes first), its Settings button is at 1005, 323
    # (the first row is at 250), its tabs at 1015 / 1113, 213, the next page button at 887, 707
    Phase 'dt'       'drop-tuning' "{phase = 'modscreen', clicks = {{1005, 250}, {887, 707}}}"
    Phase 'dtmore'   'drop-tuning' "{phase = 'modscreen', clicks = {{1005, 250}, {1113, 213}}}"
    Phase 'keys'     'key-bindings' "{phase = 'modscreen', clicks = {{1106, 250}}}"
    Phase 'realms'   'realms' "{phase = 'modscreen', realm = {id = 'private', name = 'Private realm', host = 'realm.example.com', port = 7066}, clicks = {{1005, 323}, {1113, 213}}}"
    Phase 'spawn'    'spawn-rate' "{phase = 'modscreen', clicks = {{1005, 323}}}"
    Phase 'region'   'region-counter' "{phase = 'modscreen', clicks = {{1005, 323}}}"
    Phase 'twibase'  'twitch_integration' "{phase = 'modscreen', clicks = {}}" @('twi_sacred')
}
python (Join-Path $PSScriptRoot 'crop.py') $Game
