<#
Closed Net auction house test against a loopback lobby + GameServer (see ../../src/auction-house/selftest.lua, modes closed*).
  .\ah-closed.ps1 deploy                       copies Gear (from sacred-bild main's build) and the auction-house mod into the test copy (holds the game lock)
  .\ah-closed.ps1 run -Name ah-seller -Role closed -Account seller [-Create] [-Hero Seller]
Only for the test copy of the game, loopback lobby/server on custom ports; never the play folder.
#>
param([Parameter(Mandatory)][ValidateSet('deploy', 'run')][string]$Action, [string]$Name = 'ah-seller', [string]$Role = 'closed',
      [string]$Account = 'seller', [string]$Hero = 'Seller', [switch]$Create, [int]$LobbyPort = 17266, [int]$Timeout = 600, [int]$Watch = 420)
$ErrorActionPreference = 'Stop'
$game = 'B:\Spiele\GOG Games\sacred gold GOG-ahtest'
if ($game -notmatch 'ahtest$') { throw 'test copy only' }
$build = 'E:\git\github\sacred-bild\out\build\msvc-x86\RelWithDebInfo'
$mods = Split-Path (Split-Path $PSScriptRoot)
$lock = 'E:\git\github\sacred-bild\tools\game-lock.ps1'
if ($Action -eq 'deploy') {
    & $lock acquire -Id agent-ah-closed -TimeoutSeconds 900
    try {
        foreach ($f in 'ddraw.dll', 'ddraw.pdb', 'SacredGear.dll', 'SacredGear.pdb') { if ((Get-FileHash "$build\$f").Hash -ne (Get-FileHash "$game\$f" -ea 0).Hash) { Copy-Item -Force "$build\$f" "$game\$f" } }
        $dst = "$game\mods\auction-house"
        Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item "$mods\src\auction-house" $dst -Recurse
        Write-Host 'deployed'
    } finally { & $lock release -Id agent-ah-closed }
    return
}
$cfg = "return {enabled = true, selftest = '$Role', host = '127.0.0.1', port = $LobbyPort, account = '$Account', password = 'x', hero = '$Hero', watch = $Watch, create = $(([string]$Create.IsPresent).ToLower())}"
Set-Content "$game\mods\auction-house\config.lua" $cfg
$p = Start-Process "$game\Sacred.exe" -WorkingDirectory $game -PassThru -ArgumentList "-gear-auto -gear-instance=$Name -gear-window=1600x900 -gear-mods=auction-house -gear-timeout=$Timeout"
$p.WaitForExit()
"$Name exit $($p.ExitCode)"
