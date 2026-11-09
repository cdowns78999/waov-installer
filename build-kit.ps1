<#
  build-kit.ps1  -  compiles the WAOV launcher kit (2026-11-09). Run on Chad's PC only.
    powershell -NoProfile -ExecutionPolicy Bypass -File build-kit.ps1
  Output (this folder):
    Miles Installer and Updater.exe     ps2exe build of launcher\Miles Installer and Updater.ps1, icon waov.ico, no console
    backup\Miles Installer and Updater.bat
    README-LAUNCHER.txt                 the LAUNCHER section every zip README carries
  Then pack a zip with pack-zip.ps1.
#>
$ErrorActionPreference = 'Stop'
$K = $PSScriptRoot
$src = Join-Path $K 'launcher\Miles Installer and Updater.ps1'
$ver = ((Select-String -Path $src -Pattern "^\`$KitVersion = '([\d\.]+)'").Matches[0].Groups[1].Value)

if (-not (Get-Module -ListAvailable ps2exe)) {
  Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
  Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe

$exe = Join-Path $K 'Miles Installer and Updater.exe'
Invoke-ps2exe -inputFile $src -outputFile $exe -iconFile (Join-Path $K 'launcher\waov.ico') -noConsole -STA `
  -title 'Miles Installer and Updater' -description 'We Are One Voice launcher' -product 'We Are One Voice' `
  -company 'Miles' -copyright 'Miles' -version "$ver.0"

New-Item -ItemType Directory -Path (Join-Path $K 'backup') -Force | Out-Null
@'
@echo off
rem Backup launcher for We Are One Voice. Use it only if an antivirus blocks Miles Installer and Updater.exe.
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0..\launcher\Miles Installer and Updater.ps1"
'@ | Set-Content -Path (Join-Path $K 'backup\Miles Installer and Updater.bat') -Encoding ASCII

@"
LAUNCHER (kit $ver)
  Double click "Miles Installer and Updater.exe" (the rainbow W).
  What it does: shows the We Are One Voice loading screen, makes or finds Documents\WAOV assets with
  WAOV avatars, WAOV items and WAOV worlds, copies this zip into the right one, installs a small menu to
  %LOCALAPPDATA%\WAOV with Start menu and desktop shortcuts, and checks for VRChat Creator Companion,
  Unity Hub, Unity 2022.3.22f1 and Blender. Missing tools install only when you click INSTALL AND CHECK.
  It never asks for a VRChat password. You sign in to the VRChat SDK and click Build and Publish yourself.
  Windows protected your PC? The launcher is not code signed yet: click More info, then Run anyway.
  Antivirus blocked it? Run backup\Miles Installer and Updater.bat instead. The source is launcher\Miles Installer and Updater.ps1.
  Uninstall: Settings, Apps, We Are One Voice. Your Documents\WAOV assets folder is always kept.
"@ | Set-Content -Path (Join-Path $K 'README-LAUNCHER.txt') -Encoding UTF8

Get-Item $exe | Select-Object Name, Length, @{n='Version';e={$_.VersionInfo.FileVersion}}
