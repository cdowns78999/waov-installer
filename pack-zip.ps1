<#
  pack-zip.ps1  -  builds the outer {NAME}.zip for an m- run (2026-11-09).
    powershell -NoProfile -ExecutionPolicy Bypass -File pack-zip.ps1 -Name AVI-01300-11092026-1430 -AssetFolder <folder with the asset files> -OutDir <folder>
  Layout (install.txt section 1):  Miles Installer and Updater.exe, {NAME}-asset.zip, README.txt, launcher\, backup\
  Refuses to pack when the name breaks naming.txt or the kit .exe is missing (the zip would be BLOCKED).
  2.0: -Feature <image> puts feature.png inside {NAME}-asset.zip (the launcher shows it after the Drive download). Without one,
  an existing feature*.png / render*.png in the asset folder is used, else the launcher draws a card (WAOV-W63 warning here).
#>
param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$AssetFolder, [Parameter(Mandatory)][string]$OutDir, [string]$ReadmeTop = '', [string]$Feature = '')
$ErrorActionPreference = 'Stop'
$K = $PSScriptRoot
if ($Name -notmatch '^(AVI|ITE|WOR)-0[12][123]00-\d{8}-\d{4}$') { throw "name $Name does not match naming.txt" }
$exe = Join-Path $K 'Miles Installer and Updater.exe'
if (-not (Test-Path $exe)) { throw 'kit .exe missing: run build-kit.ps1 first (zip BLOCKED)' }

$stage = Join-Path $env:TEMP "waov-pack-$Name"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
if ($Feature) {
  if (-not (Test-Path $Feature)) { throw "feature image not found: $Feature" }
  Copy-Item $Feature (Join-Path $AssetFolder 'feature.png') -Force
}
if (-not (Get-ChildItem $AssetFolder -Recurse -Include 'feature*.png', 'render*.png', 'feature*.jpg' -ErrorAction SilentlyContinue)) {
  Write-Warning 'WAOV-W63: no feature image in the asset folder, the launcher will draw a generated card (use -Feature <image>)'
}
Compress-Archive -Path (Join-Path $AssetFolder '*') -DestinationPath (Join-Path $stage "$Name-asset.zip")
Copy-Item $exe $stage
Copy-Item (Join-Path $K 'launcher') (Join-Path $stage 'launcher') -Recurse
Remove-Item (Join-Path $stage 'launcher\contact-sheet.png') -ErrorAction SilentlyContinue
Copy-Item (Join-Path $K 'backup') (Join-Path $stage 'backup') -Recurse
(($ReadmeTop, '', (Get-Content (Join-Path $K 'README-LAUNCHER.txt') -Raw)) -join "`r`n") | Set-Content (Join-Path $stage 'README.txt') -Encoding UTF8

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$zip = Join-Path $OutDir "$Name.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
Remove-Item $stage -Recurse -Force

# check: list it
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [IO.Compression.ZipFile]::OpenRead($zip)
$names = $z.Entries.FullName; $z.Dispose()
foreach ($must in @('Miles Installer and Updater.exe', "$Name-asset.zip", 'README.txt', 'launcher/waov.ico', 'backup/Miles Installer and Updater.bat')) {
  if (-not ($names -contains $must -or $names -contains ($must -replace '/', '\'))) { throw "check failed: $must missing from the zip" }
}
"packed $zip  ($([math]::Round((Get-Item $zip).Length / 1MB, 2)) MB, $($names.Count) entries)"
