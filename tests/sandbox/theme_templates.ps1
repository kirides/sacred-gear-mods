# Runs the sacred-theme template demo in Sacred Gear's UI sandbox at 1600x900 (the demo mod needs no game; the sandbox reads the game's pictures from the install):
#   .\tests\sandbox\theme_templates.ps1 -Sandbox E:\git\github\sacred-bild\out\build\msvc-x86\RelWithDebInfo\gear_sandbox.exe [-Out <folder for the snapshots>]
param([Parameter(Mandatory)][string]$Sandbox, [string]$Out = (Join-Path $env:TEMP 'theme-templates'))
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot)
$mods = Join-Path $env:TEMP 'theme-templates-mods'
Remove-Item $mods -Recurse -Force -ErrorAction SilentlyContinue
New-Item $mods, $Out -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $repo 'src\sacred-theme') (Join-Path $mods 'sacred-theme') -Recurse
Copy-Item (Join-Path $PSScriptRoot 'theme-templates-demo') (Join-Path $mods 'theme-templates-demo') -Recurse
& $Sandbox --hidden --mods $mods --enable sacred-theme,theme-templates-demo --size 1600x900 --script (Join-Path $PSScriptRoot 'theme_templates.lua') $Out
exit $LASTEXITCODE
