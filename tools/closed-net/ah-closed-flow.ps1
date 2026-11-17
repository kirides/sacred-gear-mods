<# The multi-run Closed Net flow: seller sells and is killed (no save), seller rejoins (no duplicate), buyer buys + collects, buyer relogs (item still there), seller takes the proceeds.
   Needs the loopback lobby + server running (see ah-closed.ps1) and `ah-closed.ps1 deploy` done before (it wipes the state file). #>
param([string]$Seller = 'sellere', [string]$Buyer = 'buyere')
$ErrorActionPreference = 'Stop'
$game = 'B:\Spiele\GOG Games\sacred gold GOG-ahtest'
$run = Join-Path $PSScriptRoot 'ah-closed.ps1'
Remove-Item "$game\mods\auction-house\closed-state.json" -ErrorAction SilentlyContinue
# 1. the sale, then a kill without any save
$job = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-File', $run, 'run', '-Name', 'ah-flow-1', '-Role', 'closed_sell', '-Account', $Seller, '-Hero', 'Seller', '-Create', '-Timeout', '900'
$t0 = Get-Date
while (-not (Test-Path "$game\mods\auction-house\closed-state.json")) { Start-Sleep 2; if (((Get-Date) - $t0).TotalSeconds -gt 400) { throw 'no sale state' } }
Start-Sleep 4
Get-CimInstance Win32_Process -Filter "name='Sacred.exe'" | Where-Object { $_.CommandLine -match 'ah-flow-1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
"killed the seller at $(Get-Date -f HH:mm:ss) without saving"
Start-Sleep 6
foreach ($step in @(@('ah-flow-2', 'closed_check', $Seller, 'Seller', $false), @('ah-flow-3', 'closed_buy', $Buyer, 'Buyer', $true),
                    @('ah-flow-4', 'closed_relogin', $Buyer, 'Buyer', $false), @('ah-flow-5', 'closed_proceeds', $Seller, 'Seller', $false))) {
    $a = @('-NoProfile', '-File', $run, 'run', '-Name', $step[0], '-Role', $step[1], '-Account', $step[2], '-Hero', $step[3], '-Timeout', '600')
    if ($step[4]) { $a += '-Create' }
    $p = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList $a
    $p.WaitForExit()
    "$($step[0]) $($step[1]) done: $(Get-Content "$game\GearAutomation\$($step[0])\run.json" -Raw | ConvertFrom-Json | ForEach-Object { 'exit ' + $_.exit_code })"
}
