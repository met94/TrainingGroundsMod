param(
    [string]$ModsRoot = 'D:\SteamLibrary\steamapps\common\PAYDAY3\PAYDAY3\Binaries\Win64\ue4ss\Mods'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ModsRoot)) {
    Write-Error "Mods root not found: $ModsRoot"
    exit 1
}

$Root = $PSScriptRoot
$Src = Join-Path $Root 'lua\TrainingSpawner'
$Pd3Lib = Join-Path $Root 'shared\pd3lib'
$ModDir = Join-Path $ModsRoot 'TrainingSpawner'
$ScriptsDir = Join-Path $ModDir 'scripts'
$LibDir = Join-Path $ScriptsDir 'pd3lib'

if (-not (Test-Path -LiteralPath (Join-Path $Pd3Lib 'pd3lib.lua'))) {
    Write-Error "pd3lib submodule missing at $Pd3Lib - run: git submodule update --init"
    exit 1
}

# Mirror sources; /XD pd3lib + /XF pd3lib.lua keep the vendored library intact.
# user_config.lua is preserved so local tweaks survive re-deploys (created below if missing).
robocopy "$Src\scripts" $ScriptsDir /MIR /NFL /NDL /NJH /NJS /XD pd3lib /XF pd3lib.lua user_config.lua
if ($LASTEXITCODE -ge 8) {
    Write-Error "robocopy failed (scripts) with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

New-Item -ItemType Directory -Force -Path $LibDir | Out-Null

# Vendored pd3lib: same layout as the release zip (scripts\pd3lib.lua + scripts\pd3lib\).
Copy-Item -Force (Join-Path $Pd3Lib 'pd3lib.lua') (Join-Path $ScriptsDir 'pd3lib.lua')
Copy-Item -Force (Join-Path $Pd3Lib 'selftest.lua') (Join-Path $LibDir 'selftest.lua')
Copy-Item -Force (Join-Path $Pd3Lib 'LICENSE.md') (Join-Path $LibDir 'LICENSE.md')

foreach ($Sub in @('core', 'game')) {
    robocopy (Join-Path $Pd3Lib $Sub) (Join-Path $LibDir $Sub) /MIR /NFL /NDL /NJH /NJS
    if ($LASTEXITCODE -ge 8) {
        Write-Error "robocopy failed (pd3lib\$Sub) with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $ScriptsDir 'user_config.lua'))) {
    Copy-Item -Force (Join-Path $Src 'scripts\user_config.lua') (Join-Path $ScriptsDir 'user_config.lua')
    Write-Host "user_config.lua created from template"
}

Copy-Item -Force (Join-Path $Src 'mod.txt') (Join-Path $ModDir 'mod.txt')
if (-not (Test-Path -LiteralPath (Join-Path $ModDir 'enabled.txt'))) {
    New-Item -ItemType File -Force -Path (Join-Path $ModDir 'enabled.txt') | Out-Null
}

Write-Host "deployed: TrainingSpawner (vendored pd3lib) -> $ModDir"
