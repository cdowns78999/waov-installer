<#
  Miles Installer and Updater  -  We Are One Voice launcher kit
  Plain readable source. Compiled to "Miles Installer and Updater.exe" by ..\build-kit.ps1 (ps2exe).
  Contract: waov-comm skill, i-install\install.txt. Codes: i-install\codes.txt.

  Modes
    (no switch)   install: loading screen, version check, 4 folders, zip copy, kit install, tool check, then the menu
    -Menu         open the menu only (what the Start menu and desktop shortcuts run)
    -Uninstall    remove %LOCALAPPDATA%\WAOV, shortcuts and the Apps list entry (never Documents\WAOV assets)
  Test switches (never needed by a buyer)
    -Simulate "Blender,UnityHub"   treat those tools as missing      -DocsRoot / -AppRoot   redirect folders
    -NoSystem     skip shortcuts and the Apps list entry               -SnapDir   save window PNGs, then close
    -LatestUrl    use another latest.json (file:// for tests)          -NoUpdateCheck   skip the GitHub check
    -VccSettings  use another VCC settings.json (slider 3 tests)        -NoLaunch  slider 3 never starts Unity
    -DryRun       GO runs a 2 second stand-in instead of winget/Hub/pip  -AutoGo  press GO by itself (snapshot runs)
    -TestLink     paste this Google Drive link and press RUN by itself (snapshot runs)
  2.0: ONE screen with four clickable dots (1 CHECKS, 2 DOWNLOADS, 3 MAP ITEM, 4 VRCHAT). GO installs every missing tool
  with one install bar; RUN downloads a pasted Drive link with launcher\drive-fetch.py; VRChat sign-in is always the buyer's own.
  Slider 3 MAP ITEM TO AVATAR lives in launcher\map-avatar.ps1 (dot-sourced below), install.txt section 5b.
  Update rule (every open, install or -Menu): read latest.json from the waov-installer GitHub release. Newer and signed
  with Chad's key -> download, verify, and hand over to that newer kit. Offline -> run this kit (WAOV-W30).
#>
param(
  [switch]$Menu,
  [switch]$Uninstall,
  [string]$Simulate = "",
  [string]$DocsRoot = "",
  [string]$AppRoot = "",
  [switch]$NoSystem,
  [string]$SnapDir = "",
  [string]$LatestUrl = "https://github.com/cdowns78999/waov-installer/releases/latest/download/latest.json",
  [switch]$NoUpdateCheck,
  [string]$ZipRootOverride = "",
  [string]$VccSettings = "",
  [switch]$NoLaunch,
  [switch]$DryRun,
  [switch]$AutoGo,
  [string]$TestLink = ""
)

$ErrorActionPreference = 'Stop'
$KitVersion = '2.0'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ---------- paths ----------
if ($PSCommandPath) { $Here = Split-Path -Parent $PSCommandPath }
else { $Here = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
if (Test-Path (Join-Path $Here 'launcher\base.png')) { $Launcher = Join-Path $Here 'launcher' } else { $Launcher = $Here }
# the zip root holds the .exe and {NAME}-asset.zip; launcher\ sits inside it (the .ps1 may run from launcher\ itself)
$ZipRoot = Split-Path -Parent $Launcher
if ($Launcher -eq $Here -and -not (Get-ChildItem -Path $ZipRoot -Filter '*-asset.zip' -ErrorAction SilentlyContinue)) { $ZipRoot = $Here }
if ($ZipRootOverride) { $ZipRoot = $ZipRootOverride }   # set when an older kit hands over to a newer one

if (-not $AppRoot) { $AppRoot = Join-Path $env:LOCALAPPDATA 'WAOV' }
if (-not $DocsRoot) { $DocsRoot = [Environment]::GetFolderPath('MyDocuments') }
$AssetsRoot = Join-Path $DocsRoot 'WAOV assets'
$Sub = [ordered]@{ AVI = 'WAOV avatars'; ITE = 'WAOV items'; WOR = 'WAOV worlds' }
$NamePattern = '^(AVI|ITE|WOR)-0[12][123]00-\d{8}-\d{4}'
$Simulated = @($Simulate -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$script:Muted = $false

# ---------- log ----------
$LogDir = Join-Path $AppRoot 'logs'
function Write-Log([string]$Code, [string]$Text) {
  try {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    Add-Content -Path (Join-Path $LogDir 'install.log') -Value ("{0}  {1}  {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Code, $Text)
  } catch { }
}

# ---------- sound ----------
$script:Music = $null; $script:Beep = $null
try {
  $script:Music = New-Object System.Media.SoundPlayer (Join-Path $Launcher 'chiptune.wav')
  $script:Beep = New-Object System.Media.SoundPlayer (Join-Path $Launcher 'beep.wav')
  $script:Beep.Load()
} catch { Write-Log 'WAOV-W01' 'sound device or files missing, running muted'; $script:Muted = $true }
function Play-Beep { if (-not $script:Muted -and $script:Beep) { try { $script:Beep.Play() } catch { } } }

# ---------- tools ----------
$Tools = @(
  @{ Key = 'CreatorCompanion'; Label = 'VRChat Creator Companion'; Winget = 'VRChat.CreatorCompanion'; Page = 'https://vrchat.com/download/vcc'; Ok = 'WAOV-I10'; Bad = 'WAOV-E10' },
  @{ Key = 'UnityHub'; Label = 'Unity Hub'; Winget = 'Unity.UnityHub'; Page = 'https://unity.com/download'; Ok = 'WAOV-I11'; Bad = 'WAOV-E11' },
  @{ Key = 'Unity'; Label = 'Unity 2022.3.22f1'; Winget = ''; Page = 'https://unity.com/releases/editor/archive'; Ok = 'WAOV-I12'; Bad = 'WAOV-E12' },
  @{ Key = 'Blender'; Label = 'Blender'; Winget = 'BlenderFoundation.Blender'; Page = 'https://www.blender.org/download/'; Ok = 'WAOV-I13'; Bad = 'WAOV-E13' },
  @{ Key = 'Python'; Label = 'Python 3.12 + gdown'; Winget = 'Python.Python.3.12'; Page = 'https://www.python.org/downloads/'; Ok = 'WAOV-I15'; Bad = 'WAOV-E15' }
)
# 2.0: installs.json ships INSIDE the signed kit and may only pick from this allow-list of winget ids (WAOV-E16 when refused)
$AllowedIds = @('VRChat.CreatorCompanion', 'Unity.UnityHub', 'BlenderFoundation.Blender', 'Python.Python.3.12')
$mf = Join-Path $Launcher 'installs.json'
if (Test-Path $mf) {
  try {
    $mj = Get-Content $mf -Raw | ConvertFrom-Json
    foreach ($t in $Tools) {
      $e = @($mj.tools) | Where-Object { $_.key -eq $t.Key } | Select-Object -First 1
      if ($e -and $e.winget) { if ($AllowedIds -contains [string]$e.winget) { $t.Winget = [string]$e.winget } else { Write-Log 'WAOV-E16' "installs.json id refused: $($e.winget)" } }
    }
  } catch { Write-Log 'WAOV-E16' "installs.json unreadable: $($_.Exception.Message)" }
}
# 2.0: the base Google Drive link lives in launcher\drive.json (DriveLink). Empty = the DOWNLOAD AVATARS button opens the store page.
$DriveLink = ''
$df = Join-Path $Launcher 'drive.json'
if (Test-Path $df) { try { $DriveLink = [string]((Get-Content $df -Raw | ConvertFrom-Json).DriveLink) } catch { } }
$script:DrySet = @{}
$UnityVersion = '2022.3.22f1'
$UnityChangeset = '887be4894c44'   # Unity 2022.3.22f1 changeset, used by the Hub headless install

# slider 3 helpers (map an item to an avatar); a kit without the file simply has no slider 3
$script:HasMap = $false
$mapSrc = Join-Path $Launcher 'map-avatar.ps1'
if (Test-Path $mapSrc) { try { . $mapSrc; $script:HasMap = $true } catch { Write-Log 'WAOV-E66' "map-avatar.ps1 failed to load: $($_.Exception.Message)" } }
foreach ($extra in 'map-verify.ps1', 'map-unity-check.ps1') {   # 2026-11-14: three picks + fast and Unity checks
  $xs = Join-Path $Launcher $extra
  if ($script:HasMap -and (Test-Path $xs)) { try { . $xs } catch { Write-Log 'WAOV-E66' "$extra failed to load: $($_.Exception.Message)"; $script:HasMap = $false } }
}

function Get-UninstallNames {
  $keys = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  $names = foreach ($k in $keys) { Get-ItemProperty $k -ErrorAction SilentlyContinue | ForEach-Object { $_.DisplayName } }
  @($names | Where-Object { $_ })
}
function Get-HubExe {
  foreach ($p in @("$env:ProgramFiles\Unity Hub\Unity Hub.exe", "$env:LOCALAPPDATA\Programs\Unity Hub\Unity Hub.exe")) { if (Test-Path $p) { return $p } }
  return $null
}
function Get-PythonExe {
  $c = @()
  $c += @(Get-ChildItem "$env:LOCALAPPDATA\Programs\Python" -Filter python.exe -Recurse -Depth 1 -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | ForEach-Object { $_.FullName })
  $c += @(Get-ChildItem "$env:ProgramFiles\Python3*" -Filter python.exe -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
  $cmd = Get-Command python -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source -notmatch 'WindowsApps') { $c += $cmd.Source }
  foreach ($p in $c) { if ($p -and (Test-Path $p)) { return $p } }
  return $null
}
function Test-PyLibs([string]$py) {
  try { $p = Start-Process -FilePath $py -ArgumentList @('-c', '"import gdown, PIL"') -PassThru -Wait -WindowStyle Hidden; return ($p.ExitCode -eq 0) } catch { return $false }
}
function Test-Tool([string]$Key) {
  if ($script:DrySet[$Key]) { return $true }
  if ($Simulated -contains $Key) { return $false }
  $names = Get-UninstallNames
  switch ($Key) {
    'CreatorCompanion' { return [bool](($names -like '*Creator Companion*') -or (Test-Path "$env:LOCALAPPDATA\Programs\VRChat Creator Companion")) }
    'UnityHub'         { return [bool]((Get-HubExe) -or ($names -like 'Unity Hub*')) }
    'Unity' {
      $roots = @("$env:ProgramFiles\Unity\Hub\Editor")
      $sec = Join-Path $env:APPDATA 'UnityHub\secondaryInstallPath.json'
      if (Test-Path $sec) { try { $p = (Get-Content $sec -Raw | ConvertFrom-Json); if ($p) { $roots += [string]$p } } catch { } }
      foreach ($r in $roots) { if ($r -and (Test-Path (Join-Path $r "$UnityVersion\Editor\Unity.exe"))) { return $true } }
      return $false
    }
    'Blender' { return [bool](($names -like 'Blender*') -or (Get-ChildItem "$env:ProgramFiles\Blender Foundation" -Filter blender.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)) }
    'Python' { $py = Get-PythonExe; if (-not $py) { return $false }; return (Test-PyLibs $py) }
  }
  return $false
}

# ---------- install steps ----------
function Get-AssetName {
  $z = Get-ChildItem -Path $ZipRoot -Filter '*-asset.zip' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $NamePattern } | Select-Object -First 1
  if ($z) { return @{ Name = ($z.Name -replace '-asset\.zip$', ''); AssetZip = $z.FullName } }
  return $null
}
function Step-Version {
  $vf = Join-Path $AppRoot 'version.json'
  $installed = $null
  if (Test-Path $vf) { try { $installed = [version]((Get-Content $vf -Raw | ConvertFrom-Json).kit) } catch { } }
  $mine = [version]$KitVersion
  if (-not $installed) { $script:KitAction = 'install'; return 'no kit installed yet: full install' }
  if ($mine -gt $installed) { $script:KitAction = 'update'; return "newer kit $mine replaces $installed" }
  if ($mine -eq $installed) { $script:KitAction = 'skip'; Write-Log 'WAOV-I05' "kit $mine already installed, kit install skipped"; return "kit $mine already installed" }
  $script:KitAction = 'keep'; Write-Log 'WAOV-I06' "zip kit $mine is older than installed $installed, kept $installed"; return "kept the newer kit $installed"
}
function Step-Folders {
  $made = 0
  $all = @($AssetsRoot) + @($Sub.Values | ForEach-Object { Join-Path $AssetsRoot $_ })
  foreach ($f in $all) {
    if (Test-Path $f) { Write-Log 'WAOV-I07' "found $f" }
    else {
      try { New-Item -ItemType Directory -Path $f -Force | Out-Null; $made++; Write-Log 'WAOV-I07' "made $f" }
      catch { Write-Log 'WAOV-E02' "could not make $f : $($_.Exception.Message)"; throw }
    }
  }
  return "WAOV assets folders ready ($made made, $(4 - $made) found)"
}
function Step-ZipCopy {
  $a = Get-AssetName
  if (-not $a) { Write-Log 'WAOV-W02' 'no named asset zip next to the installer, nothing copied'; return 'no WAOV asset zip found next to the installer' }
  $prefix = $a.Name.Substring(0, 3)
  $dest = Join-Path $AssetsRoot $Sub[$prefix]
  $outer = @((Join-Path (Split-Path -Parent $ZipRoot) "$($a.Name).zip"), (Join-Path $ZipRoot "$($a.Name).zip"), (Join-Path ([Environment]::GetFolderPath('UserProfile')) "Downloads\$($a.Name).zip")) |
           Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($outer) { $src = $outer } else { $src = $a.AssetZip }
  $target = Join-Path $dest (Split-Path -Leaf $src)
  if ((Test-Path $target) -and ((Get-Item $target).Length -eq (Get-Item $src).Length)) {
    Write-Log 'WAOV-I08' "already there: $target"; return "$(Split-Path -Leaf $src) already in $($Sub[$prefix])"
  }
  Copy-Item -Path $src -Destination $target -Force
  Write-Log 'WAOV-I08' "copied $src -> $target"
  return "copied $(Split-Path -Leaf $src) into $($Sub[$prefix])"
}
function New-Shortcut([string]$Path, [string]$Args) {
  $ws = New-Object -ComObject WScript.Shell
  $s = $ws.CreateShortcut($Path)
  $s.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $s.Arguments = $Args
  $s.IconLocation = (Join-Path $AppRoot 'widget\current\waov.ico') + ',0'
  $s.WorkingDirectory = Join-Path $AppRoot 'widget\current'
  $s.Save()
}
function Step-Kit {
  if ($script:KitAction -in @('skip', 'keep')) { return 'kit install not needed' }
  $cur = Join-Path $AppRoot 'widget\current'; $prev = Join-Path $AppRoot 'widget\previous'
  New-Item -ItemType Directory -Path (Join-Path $AppRoot 'widget') -Force | Out-Null
  if (Test-Path $cur) {
    if (Test-Path $prev) { Remove-Item $prev -Recurse -Force }
    Move-Item $cur $prev
  }
  try {
    Copy-Item -Path $Launcher -Destination $cur -Recurse -Force
    if (-not (Test-Path (Join-Path $cur 'Miles Installer and Updater.ps1'))) { throw 'self-test: launcher script missing after copy' }
    @{ kit = $KitVersion; installed = (Get-Date -Format 'yyyy-MM-dd HH:mm') } | ConvertTo-Json | Set-Content (Join-Path $AppRoot 'version.json')
  } catch {
    Write-Log 'WAOV-E50' "kit install failed, rolled back: $($_.Exception.Message)"
    if (Test-Path $cur) { Remove-Item $cur -Recurse -Force }
    if (Test-Path $prev) { Move-Item $prev $cur }
    return 'kit install failed, rolled back to the previous kit'
  }
  if ($script:KitAction -eq 'update') { Write-Log 'WAOV-I04' "kit $KitVersion installed, old kit moved to previous" } else { Write-Log 'WAOV-I02' "kit $KitVersion copied" }
  if (-not $NoSystem) {
    $menuArgs = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $cur 'Miles Installer and Updater.ps1') + '" -Menu'
    New-Shortcut (Join-Path ([Environment]::GetFolderPath('Programs')) 'We Are One Voice.lnk') $menuArgs
    New-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'We Are One Voice.lnk') $menuArgs
    $uk = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WAOV'
    New-Item -Path $uk -Force | Out-Null
    $un = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $cur 'Miles Installer and Updater.ps1') + '" -Uninstall'
    Set-ItemProperty $uk -Name DisplayName -Value 'We Are One Voice'
    Set-ItemProperty $uk -Name DisplayVersion -Value $KitVersion
    Set-ItemProperty $uk -Name Publisher -Value 'Miles'
    Set-ItemProperty $uk -Name DisplayIcon -Value (Join-Path $cur 'waov.ico')
    Set-ItemProperty $uk -Name UninstallString -Value $un
    Set-ItemProperty $uk -Name NoModify -Value 1 -Type DWord
    Write-Log 'WAOV-I03' 'shortcuts and uninstall entry made'
  }
  return "kit $KitVersion installed"
}
$script:ToolState = @{}
function Step-Check {
  foreach ($t in $Tools) {
    $ok = Test-Tool $t.Key
    $script:ToolState[$t.Key] = $ok
    if ($ok) { Write-Log $t.Ok "$($t.Label) found" } else { Write-Log $t.Bad "$($t.Label) not found" }
  }
  $n = @($script:ToolState.Values | Where-Object { $_ }).Count
  return "tool check: $n of $($Tools.Count) installed"
}

# ---------- uninstall ----------
if ($Uninstall) {
  foreach ($l in @((Join-Path ([Environment]::GetFolderPath('Programs')) 'We Are One Voice.lnk'), (Join-Path ([Environment]::GetFolderPath('Desktop')) 'We Are One Voice.lnk'))) {
    if (Test-Path $l) { Remove-Item $l -Force }
  }
  Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WAOV' -Recurse -Force -ErrorAction SilentlyContinue
  Add-Content -Path (Join-Path $env:TEMP 'waov-uninstall.log') -Value ("{0}  uninstalled, Documents\WAOV assets kept" -f (Get-Date))
  # the running script lives inside AppRoot, so remove it after this process exits
  Start-Process -WindowStyle Hidden cmd.exe -ArgumentList "/c timeout /t 2 >nul & rmdir /s /q `"$AppRoot`""
  [System.Windows.MessageBox]::Show('We Are One Voice was removed. Your Documents\WAOV assets folder was kept.', 'We Are One Voice') | Out-Null
  return
}

# ---------- update check (every open: install and -Menu) ----------
$script:UpdateNote = ''
function Get-Remote([string]$Url, [string]$OutFile) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $req = [System.Net.WebRequest]::Create($Url); $req.Timeout = 8000
  if ($req -is [System.Net.HttpWebRequest]) { $req.UserAgent = 'WAOV-Installer'; $req.AllowAutoRedirect = $true }
  $resp = $req.GetResponse(); $s = $resp.GetResponseStream()
  try {
    if ($OutFile) { $fs = [IO.File]::Create($OutFile); $s.CopyTo($fs); $fs.Close(); return $OutFile }
    return (New-Object IO.StreamReader($s)).ReadToEnd()
  } finally { $s.Close(); $resp.Close() }
}
function Invoke-UpdateCheck {
  if ($NoUpdateCheck) { return }
  try { $j = (Get-Remote $LatestUrl $null) | ConvertFrom-Json }
  catch { Write-Log 'WAOV-W30' "update check offline, running kit $KitVersion"; $script:UpdateNote = 'offline'; return }
  if ([version]$j.version -le [version]$KitVersion) { Write-Log 'WAOV-I30' "update check: kit $KitVersion is the latest"; return }
  Write-Log 'WAOV-I31' "newer kit $($j.version) found, downloading"
  try {
    $tmp = Join-Path $env:TEMP ('waov-kit-' + $j.version)
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $zip = Join-Path $tmp $j.file
    $url = $j.url
    if (-not $url) { $url = ($LatestUrl -replace '[^/]+$', '') + $j.file }
    [void](Get-Remote $url $zip)
    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne ([string]$j.sha256).ToLower()) { throw 'hash does not match latest.json' }
    $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
    $rsa.FromXmlString((Get-Content (Join-Path $Launcher 'waov-update.pub.xml') -Raw))
    if (-not $rsa.VerifyData([IO.File]::ReadAllBytes($zip), 'SHA256', [Convert]::FromBase64String($j.sig))) { throw 'signature is not from Chad''s key' }
    Expand-Archive -Path $zip -DestinationPath (Join-Path $tmp 'kit') -Force
  } catch {
    Write-Log 'WAOV-E51' "update $($j.version) refused: $($_.Exception.Message)"
    $script:UpdateNote = "v$($j.version) available"
    return
  }
  # hand over to the newer kit; it installs itself (newer than installed -> I04) and opens the menu
  $a = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $tmp 'kit\Miles Installer and Updater.ps1') + '"'),
         '-NoUpdateCheck', '-ZipRootOverride', ('"' + $ZipRoot + '"'))
  if ($PSBoundParameters.ContainsKey('DocsRoot') -or $DocsRoot -ne [Environment]::GetFolderPath('MyDocuments')) { $a += @('-DocsRoot', ('"' + $DocsRoot + '"')) }
  if ($AppRoot -ne (Join-Path $env:LOCALAPPDATA 'WAOV')) { $a += @('-AppRoot', ('"' + $AppRoot + '"')) }
  if ($Simulate) { $a += @('-Simulate', $Simulate) }
  if ($NoSystem) { $a += '-NoSystem' }
  if ($SnapDir) { $a += @('-SnapDir', ('"' + $SnapDir + '"')) }
  Write-Log 'WAOV-I31' "handing over to kit $($j.version)"
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $a -WindowStyle Hidden -Wait
  exit
}
Invoke-UpdateCheck

# ---------- shared look ----------
$Styles = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Style x:Key="Px" TargetType="Button">
    <Setter Property="FontFamily" Value="Consolas"/><Setter Property="FontWeight" Value="Bold"/><Setter Property="FontSize" Value="15"/>
    <Setter Property="Foreground" Value="#000000"/><Setter Property="Background" Value="#AAAAAA"/><Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Padding" Value="14,6"/><Setter Property="Margin" Value="6,0"/>
    <Setter Property="Template"><Setter.Value>
      <ControlTemplate TargetType="Button">
        <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="#000000" BorderThickness="2">
          <Border BorderBrush="#FFFFFF" BorderThickness="2,2,0,0"><Border BorderBrush="#555555" BorderThickness="0,0,3,3">
            <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border></Border>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#FFFF55"/></Trigger>
          <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="Background" Value="#55FFFF"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.45"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value></Setter>
  </Style>
</ResourceDictionary>
'@
function New-Xaml([string]$x) { [Windows.Markup.XamlReader]::Parse($x) }
function Fade-In($el) {
  $a = New-Object System.Windows.Media.Animation.DoubleAnimation(0, 1, [TimeSpan]::FromSeconds(2))
  $e = New-Object System.Windows.Media.Animation.SineEase; $e.EasingMode = 'EaseInOut'; $a.EasingFunction = $e
  $el.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a)
}
function Save-Snap($win, [string]$file) {
  if (-not $SnapDir) { return }
  New-Item -ItemType Directory -Path $SnapDir -Force | Out-Null
  $c = $win.Content
  $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$c.ActualWidth, [int]$c.ActualHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
  $bmp.Render($c)
  $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
  $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
  $fs = [IO.File]::Create((Join-Path $SnapDir $file)); $enc.Save($fs); $fs.Close()
}
function Img([string]$name) {
  $b = New-Object System.Windows.Media.Imaging.BitmapImage
  $b.BeginInit(); $b.UriSource = New-Object Uri (Join-Path $Launcher $name); $b.CacheOption = 'OnLoad'; $b.EndInit(); $b
}

# ---------- menu window ----------
function Show-Menu {
  $x = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
  Title="We Are One Voice" Width="860" Height="620" WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize" Background="#000000"
  TextOptions.TextRenderingMode="Aliased" TextOptions.TextFormattingMode="Display" FontFamily="Consolas">
  <Grid x:Name="Root" Opacity="0" Margin="10" Background="#0000AA">
    <Border BorderBrush="#55FFFF" BorderThickness="3"/>
    <StackPanel HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,16,20,0" Panel.ZIndex="5">
      <TextBlock x:Name="Stamp" FontSize="16" FontWeight="Bold" Foreground="#55FFFF" HorizontalAlignment="Right"/>
      <TextBlock x:Name="StampNote" FontSize="12" FontWeight="Bold" Foreground="#FFFF55" HorizontalAlignment="Right"/>
    </StackPanel>
    <DockPanel Margin="18">
      <StackPanel DockPanel.Dock="Top">
        <StackPanel Orientation="Horizontal">
          <TextBlock Text="WE ARE ONE VOICE" FontSize="26" FontWeight="Bold" Foreground="#FFFF55"/>
          <TextBlock x:Name="Cursor" Text="_" FontSize="26" FontWeight="Bold" Foreground="#FFFFFF"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,12,0,14">
          <TextBlock x:Name="Dot1" Text="(o) 1 CHECKS" FontSize="15" FontWeight="Bold" Foreground="#FFFFFF" Margin="0,0,26,0" Cursor="Hand"/>
          <TextBlock x:Name="Dot2" Text="( ) 2 DOWNLOADS" FontSize="15" FontWeight="Bold" Foreground="#AAAAAA" Margin="0,0,26,0" Cursor="Hand"/>
          <TextBlock x:Name="Dot3" Text="( ) 3 MAP ITEM" FontSize="15" FontWeight="Bold" Foreground="#AAAAAA" Margin="0,0,26,0" Cursor="Hand"/>
          <TextBlock x:Name="Dot4" Text="( ) 4 VRCHAT" FontSize="15" FontWeight="Bold" Foreground="#AAAAAA" Cursor="Hand"/>
        </StackPanel>
        <Rectangle Height="3" Fill="#55FFFF"/>
      </StackPanel>
      <DockPanel DockPanel.Dock="Bottom" Margin="0,12,0,0" LastChildFill="False">
        <Button x:Name="Mute" DockPanel.Dock="Left" Content="MUTE" Style="{DynamicResource Px}"/>
        <Button x:Name="Next" DockPanel.Dock="Right" Content="NEXT &gt;" Style="{DynamicResource Px}"/>
        <Button x:Name="Back" DockPanel.Dock="Right" Content="&lt; BACK" Style="{DynamicResource Px}" Visibility="Collapsed"/>
        <Button x:Name="Recheck" DockPanel.Dock="Right" Content="RE-CHECK" Style="{DynamicResource Px}"/>
      </DockPanel>
      <Grid>
        <DockPanel x:Name="Slide1" Margin="4,10,4,0">
          <StackPanel DockPanel.Dock="Bottom" Margin="0,6,0,0">
            <DockPanel>
              <Button x:Name="Go" DockPanel.Dock="Left" Content="GO" Style="{DynamicResource Px}" Margin="0,0,14,0" FontSize="18" Padding="30,6"/>
              <TextBlock x:Name="GoText" FontSize="15" FontWeight="Bold" Foreground="#FFFF55" VerticalAlignment="Center" TextWrapping="Wrap"/>
            </DockPanel>
            <Grid x:Name="BarBox" Height="24" Margin="0,8,0,0"><Border BorderBrush="#FFFFFF" BorderThickness="3"/><Border x:Name="BarFill" Background="#55FF55" HorizontalAlignment="Left" Width="0" Margin="3"/></Grid>
          </StackPanel>
          <StackPanel x:Name="Rows1"/>
        </DockPanel>
        <DockPanel x:Name="Slide2" Visibility="Collapsed" Margin="4,8,4,0">
          <StackPanel DockPanel.Dock="Top" Orientation="Horizontal">
            <Button x:Name="Sync" Content="SYNC ASSETS" Style="{DynamicResource Px}" Margin="0"/>
            <Button x:Name="Download" Content="DOWNLOAD AVATARS" Style="{DynamicResource Px}"/>
            <Button x:Name="Pair" Content="PAIR" Style="{DynamicResource Px}" Margin="0"/>
            <Button x:Name="Get" Content="GET" Style="{DynamicResource Px}" Visibility="Collapsed"/>
            <Button x:Name="Unpack" Content="UNPACK" Style="{DynamicResource Px}" Visibility="Collapsed" Margin="0"/>
            <TextBlock x:Name="Flash" Text="  [v] SYNCED" FontSize="20" FontWeight="Bold" Foreground="#55FF55" Opacity="0" VerticalAlignment="Center"/>
          </StackPanel>
          <TextBlock DockPanel.Dock="Top" x:Name="PairCode" FontSize="14" FontWeight="Bold" Foreground="#FFFF55" Margin="0,8,0,0" TextWrapping="Wrap"/>
          <DockPanel DockPanel.Dock="Top" Margin="0,8,0,0">
            <Button x:Name="Run" DockPanel.Dock="Right" Content="RUN" Style="{DynamicResource Px}" Margin="8,0,0,0" Padding="22,6"/>
            <TextBox x:Name="LinkBox" FontSize="14" Background="#000000" Foreground="#FFFFFF" BorderBrush="#55FFFF" BorderThickness="2" CaretBrush="#FFFFFF" Padding="4" VerticalContentAlignment="Center"/>
          </DockPanel>
          <TextBlock DockPanel.Dock="Top" x:Name="LinkHint" Text="Pick your zips in the Drive folder, paste the link here, press RUN." FontSize="12" Foreground="#AAAAAA" Margin="0,3,0,0"/>
          <Grid DockPanel.Dock="Top" x:Name="FetchBox" Height="16" Margin="0,6,0,0"><Border BorderBrush="#FFFFFF" BorderThickness="2"/><Border x:Name="FetchFill" Background="#55FFFF" HorizontalAlignment="Left" Width="0" Margin="2"/></Grid>
          <TextBlock DockPanel.Dock="Top" x:Name="FetchText" FontSize="13" FontWeight="Bold" Foreground="#FFFF55" Margin="0,3,0,0" TextWrapping="Wrap"/>
          <Border DockPanel.Dock="Bottom" x:Name="UpTile" Visibility="Collapsed" BorderBrush="#FFFF55" BorderThickness="3" Background="#000000" Margin="0,8,0,0" Padding="10,6">
            <DockPanel>
              <Button x:Name="UpGo" DockPanel.Dock="Right" Content="CONTINUE" Style="{DynamicResource Px}"/>
              <StackPanel>
                <TextBlock Text="LOG INTO VRCHAT TO CONTINUE" FontSize="16" FontWeight="Bold" Foreground="#FFFF55"/>
                <TextBlock Text="You sign in yourself, in your own browser or the SDK. This launcher never asks for your password." FontSize="12" Foreground="#FFFFFF" TextWrapping="Wrap"/>
              </StackPanel>
            </DockPanel>
          </Border>
          <Grid DockPanel.Dock="Top" x:Name="ResultBox" Visibility="Collapsed" Margin="0,8,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="184"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border BorderBrush="#55FFFF" BorderThickness="2" Width="176" Height="100" HorizontalAlignment="Left"><Image x:Name="FeatureImg" Stretch="Uniform" RenderOptions.BitmapScalingMode="NearestNeighbor"/></Border>
            <StackPanel Grid.Column="1" VerticalAlignment="Center">
              <TextBlock x:Name="ResultText" FontSize="15" FontWeight="Bold" Foreground="#55FF55" TextWrapping="Wrap" Margin="0,0,0,8"/>
              <Button x:Name="Upload" Content="UPLOAD TO VRCHAT ACCOUNT" Style="{DynamicResource Px}" IsEnabled="False" HorizontalAlignment="Left" Margin="0"/>
            </StackPanel>
          </Grid>
          <StackPanel DockPanel.Dock="Top" x:Name="Catalog" Margin="0,8,0,0" Visibility="Collapsed"/>
          <TextBlock DockPanel.Dock="Top" x:Name="SyncWhere" FontSize="12" Foreground="#AAAAAA" Margin="0,8,0,4"/>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="SyncList"/></ScrollViewer>
        </DockPanel>
        <Grid x:Name="Slide3" Visibility="Collapsed" Margin="4,8,4,0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="300"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <DockPanel Grid.Column="0">
            <TextBlock DockPanel.Dock="Top" Text="YOUR AVATAR" FontSize="15" FontWeight="Bold" Foreground="#FFFF55" Margin="0,0,0,4"/>
            <Button DockPanel.Dock="Top" x:Name="MapOwn" Content="MAP TO YOUR OWN AVI" Style="{DynamicResource Px}" Margin="0,0,0,6" FontSize="13"/>
            <ListBox DockPanel.Dock="Top" x:Name="AviList" Height="96" Background="#000000" Foreground="#FFFFFF" BorderBrush="#55FFFF" FontSize="13"/>
            <TextBlock DockPanel.Dock="Top" Text="BODY PART" FontSize="15" FontWeight="Bold" Foreground="#FFFF55" Margin="0,10,0,4"/>
            <ComboBox DockPanel.Dock="Top" x:Name="PartPick" FontSize="13"/>
            <TextBlock DockPanel.Dock="Top" Text="ITEM" FontSize="15" FontWeight="Bold" Foreground="#FFFF55" Margin="0,10,0,4"/>
            <ListBox x:Name="ItemList" Background="#000000" Foreground="#FFFFFF" BorderBrush="#55FFFF" FontSize="13"/>
          </DockPanel>
          <DockPanel Grid.Column="2">
            <TextBlock DockPanel.Dock="Top" Text="MAP CHECK" FontSize="15" FontWeight="Bold" Foreground="#FFFF55" Margin="0,0,0,4"/>
            <StackPanel DockPanel.Dock="Top" x:Name="MapRows"/>
            <Button DockPanel.Dock="Top" x:Name="UCheck" Content="RUN UNITY CHECK" Style="{DynamicResource Px}" Margin="0,8,0,0" IsEnabled="False" HorizontalAlignment="Left"/>
            <Button DockPanel.Dock="Top" x:Name="Approve" Content="APPROVE AND OPEN UNITY" Style="{DynamicResource Px}" Margin="0,8,0,6" IsEnabled="False" HorizontalAlignment="Left"/>
            <ScrollViewer VerticalScrollBarVisibility="Auto"><TextBlock x:Name="MapSteps" FontSize="12" Foreground="#FFFFFF" TextWrapping="Wrap"/></ScrollViewer>
          </DockPanel>
        </Grid>
        <StackPanel x:Name="Slide4" Visibility="Collapsed" Margin="4,12,4,0">
          <TextBlock Text="LOG INTO VRCHAT TO CONTINUE" FontSize="22" FontWeight="Bold" Foreground="#FFFF55"/>
          <TextBlock x:Name="Slide4Text" FontSize="15" Foreground="#FFFFFF" TextWrapping="Wrap" Margin="0,12,0,14"/>
          <StackPanel Orientation="Horizontal">
            <Button x:Name="OpenHub" Content="OPEN UNITY HUB" Style="{DynamicResource Px}" Margin="0,0,10,0"/>
            <Button x:Name="OpenVrc" Content="OPEN MY VRCHAT AVATARS" Style="{DynamicResource Px}" Margin="0"/>
          </StackPanel>
        </StackPanel>
      </Grid>
    </DockPanel>
  </Grid>
</Window>
'@
  $w = New-Xaml $x
  $w.Resources.MergedDictionaries.Add((New-Xaml $Styles))
  try { $w.Icon = Img 'waov.ico' } catch { }
  $g = @{}; foreach ($n in 'Root','Cursor','Dot1','Dot2','Dot3','Dot4','Mute','Next','Back','Recheck','Slide1','Slide2','Slide3','Slide4','Sync','Download','Pair','PairCode','Get','Unpack','Catalog','Flash','SyncWhere','SyncList','Stamp','StampNote','MapOwn','AviList','ItemList','MapRows','Approve','MapSteps','PartPick','UCheck','Rows1','Go','GoText','BarBox','BarFill','Run','LinkBox','LinkHint','FetchBox','FetchFill','FetchText','ResultBox','FeatureImg','ResultText','Upload','UpTile','UpGo','Slide4Text','OpenHub','OpenVrc') { $g[$n] = $w.FindName($n) }
  if (-not $script:HasMap) { $g.Dot3.Visibility = 'Collapsed' }
  $g.Stamp.Text = "v$KitVersion"
  if ($script:UpdateNote -and $script:UpdateNote -ne 'offline') { $g.Stamp.Foreground = '#FFFF55'; $g.StampNote.Text = 'UPDATE AVAILABLE: ' + $script:UpdateNote }
  elseif ($script:UpdateNote -eq 'offline') { $g.StampNote.Text = 'offline, not checked' }
  if ($script:Muted) { $g.Mute.Content = 'SOUND ON' }

  $render1 = {
    $g.Rows1.Children.Clear()
    foreach ($t in $Tools) {
      $ok = [bool]$script:ToolState[$t.Key]
      $row = New-Object System.Windows.Controls.DockPanel; $row.Margin = '0,0,0,9'; $row.LastChildFill = $false
      $mark = New-Object System.Windows.Controls.TextBlock
      $mark.FontSize = 22; $mark.FontWeight = 'Bold'; $mark.Width = 56; $mark.VerticalAlignment = 'Center'
      if ($ok) { $mark.Text = '[v]'; $mark.Foreground = '#55FF55' } else { $mark.Text = '[X]'; $mark.Foreground = '#FF5555' }
      $lab = New-Object System.Windows.Controls.TextBlock
      $lab.Text = $t.Label; $lab.FontSize = 18; $lab.FontWeight = 'Bold'; $lab.Foreground = '#FFFFFF'; $lab.VerticalAlignment = 'Center'
      [System.Windows.Controls.DockPanel]::SetDock($mark, 'Left'); [System.Windows.Controls.DockPanel]::SetDock($lab, 'Left')
      [void]$row.Children.Add($mark); [void]$row.Children.Add($lab)
      if ($ok) {
        $st = New-Object System.Windows.Controls.TextBlock; $st.Text = 'installed'; $st.FontSize = 15; $st.Foreground = '#55FF55'; $st.VerticalAlignment = 'Center'
        [System.Windows.Controls.DockPanel]::SetDock($st, 'Right'); [void]$row.Children.Add($st)
      } else {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Style = $w.FindResource('Px'); $btn.Tag = $t
        $needHub = ($t.Key -eq 'Unity' -and -not $script:ToolState['UnityHub'])
        $noWinget = (-not (Get-Command winget -ErrorAction SilentlyContinue)) -and $t.Winget
        if ($needHub) { $btn.Content = 'NEEDS UNITY HUB'; $btn.IsEnabled = $false }
        elseif ($noWinget -or $script:GetIt[$t.Key]) { $btn.Content = 'GET IT' }
        else { $btn.Content = 'INSTALL AND CHECK' }
        $btn.Add_Click({ param($s, $e) Play-Beep; & $installTool $s })
        [System.Windows.Controls.DockPanel]::SetDock($btn, 'Right'); [void]$row.Children.Add($btn)
      }
      [void]$g.Rows1.Children.Add($row)
    }
    $miss = @($Tools | Where-Object { -not $script:ToolState[$_.Key] }).Count
    if (-not ($script:QTimer2 -and $script:QTimer2.IsEnabled)) {
      if ($miss) { $g.Go.IsEnabled = $true; $g.GoText.Text = "$miss missing. Press GO and I install them one after another."; & $setBar 0 '' }
      else { $g.Go.IsEnabled = $false; $g.GoText.Text = '[v] Everything is installed. Press NEXT.'; & $setBar 1 '' }
    }
    if ($paintDots) { & $paintDots }
  }
  $script:GetIt = @{}
  $script:Queue = @(); $script:QPos = 0; $script:QProc = $null; $script:QPhase = ''; $script:QStart = Get-Date; $script:QTimer2 = $null
  $setBar = {
    param([double]$f, [string]$txt)
    $wd = [math]::Max(0, $g.BarBox.ActualWidth - 6)
    $g.BarFill.Width = [math]::Max(0, [math]::Min(1, $f)) * $wd
    if ($txt) { $g.GoText.Text = $txt }
  }
  # starts the process for the tool at the head of the queue (winget, Unity Hub headless, or pip); $false = nothing can run
  $startPhase = {
    $key = $script:Queue[$script:QPos]
    $t = $Tools | Where-Object { $_.Key -eq $key } | Select-Object -First 1
    $script:QPhase = ''
    if ($key -eq 'Unity') {
      $hub = Get-HubExe; if (-not $hub -and -not $DryRun) { return $false }
      $file = $hub; $argv = @('--', '--headless', 'install', '--version', $UnityVersion, '--changeset', $UnityChangeset, '--module', 'windows-mono'); $script:QPhase = 'hub'
    } elseif ($key -eq 'Python' -and (Get-PythonExe)) {
      $file = Get-PythonExe; $argv = @('-m', 'pip', 'install', '--user', '--quiet', 'gdown', 'pillow'); $script:QPhase = 'pip'
    } else {
      if (-not $DryRun -and -not (Get-Command winget -ErrorAction SilentlyContinue)) { return $false }
      if (-not $t.Winget -and -not $DryRun) { return $false }
      $file = 'winget'; $argv = @('install', '--id', $t.Winget, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements'); $script:QPhase = 'winget'
    }
    if ($DryRun) { $file = 'cmd.exe'; $argv = @('/c', 'timeout /t 2 >nul') }
    $script:QStart = Get-Date
    try { $script:QProc = Start-Process -FilePath $file -ArgumentList $argv -PassThru -WindowStyle Hidden } catch { $script:QProc = $null; return $false }
    return $true
  }
  $runQueue = {
    param($keys)
    if ($script:QTimer2 -and $script:QTimer2.IsEnabled) { return }
    $script:Queue = @($keys | Where-Object { $_ }); $script:QPos = 0; $script:QProc = $null; $script:QFail = @()
    if (-not $script:Queue.Count) { & $setBar 1 '[v] Everything is already installed.'; return }
    $g.Go.IsEnabled = $false
    $script:QTimer2 = New-Object System.Windows.Threading.DispatcherTimer; $script:QTimer2.Interval = [TimeSpan]::FromSeconds(1)
    $script:QTimer2.Add_Tick({
      $finish = {
        $script:QTimer2.Stop(); $g.Go.IsEnabled = $true
        if ($script:QFail.Count) { $g.GoText.Text = 'Some tools need the GET IT button: ' + ($script:QFail -join ', ') } else { $g.GoText.Text = '[v] All done. Press NEXT.' }
        & $setBar 1 ''; & $render1
      }
      if (-not $script:QProc) {
        while ($script:QPos -lt $script:Queue.Count -and (Test-Tool $script:Queue[$script:QPos])) { $script:ToolState[$script:Queue[$script:QPos]] = $true; $script:QPos++ }
        if ($script:QPos -ge $script:Queue.Count) { & $finish; return }
        $k = $script:Queue[$script:QPos]; $lab = ($Tools | Where-Object { $_.Key -eq $k }).Label
        if ($k -eq 'Unity' -and -not (Test-Tool 'UnityHub')) { $script:QFail += $lab; $script:GetIt[$k] = $true; Write-Log 'WAOV-E14' "$lab skipped, Unity Hub is not installed"; $script:QPos++; return }
        if (-not (& $startPhase)) { $script:QFail += $lab; $script:GetIt[$k] = $true; Write-Log 'WAOV-E14' "$lab could not start, GET IT offered"; $script:QPos++; & $render1; return }
        return
      }
      $k = $script:Queue[$script:QPos]; $lab = ($Tools | Where-Object { $_.Key -eq $k }).Label
      $secs = ((Get-Date) - $script:QStart).TotalSeconds
      & $setBar (($script:QPos + [math]::Min(0.9, $secs / 150)) / $script:Queue.Count) ("{0} of {1}: installing {2} ..." -f ($script:QPos + 1), $script:Queue.Count, $lab)
      if ($script:QProc.HasExited) {
        if ($DryRun) { $script:DrySet[$k] = $true }
        $ok = Test-Tool $k
        if (-not $ok -and $k -eq 'Python' -and $script:QPhase -eq 'winget' -and (Get-PythonExe)) { if (& $startPhase) { return } }   # Python is in, now add gdown and pillow
        $script:ToolState[$k] = $ok
        if ($ok) { Write-Log 'WAOV-I14' "$lab installed by the buyer's GO click and verified" }
        else { Write-Log 'WAOV-E14' "$lab install failed (exit $($script:QProc.ExitCode)), GET IT offered"; $script:GetIt[$k] = $true; $script:QFail += $lab }
        $script:QProc = $null; $script:QPos++
        & $render1
      }
    })
    $script:QTimer2.Start()
  }
  $installTool = {
    param($btn)
    $t = $btn.Tag
    if ([string]$btn.Content -eq 'GET IT') { Start-Process $t.Page; return }
    & $runQueue @($t.Key)
  }

  $syncNow = {
    $g.SyncList.Children.Clear()
    $g.SyncWhere.Text = $AssetsRoot
    $total = 0
    foreach ($k in $Sub.Keys) {
      $h = New-Object System.Windows.Controls.TextBlock
      $h.Text = ($Sub[$k] -replace '^WAOV ', '').ToUpper(); $h.FontSize = 17; $h.FontWeight = 'Bold'; $h.Foreground = '#FFFF55'; $h.Margin = '0,10,0,4'
      [void]$g.SyncList.Children.Add($h)
      $dir = Join-Path $AssetsRoot $Sub[$k]
      $files = @(Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue)
      $dirs = @(Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'unpacked.json') })
      if (-not $files.Count -and -not $dirs.Count) {
        $e = New-Object System.Windows.Controls.TextBlock; $e.Text = '  nothing here yet'; $e.FontSize = 14; $e.Foreground = '#AAAAAA'
        [void]$g.SyncList.Children.Add($e)
      }
      foreach ($f in $files) {
        $line = New-Object System.Windows.Controls.TextBlock; $line.FontSize = 14; $line.Margin = '12,0,0,2'; $line.TextWrapping = 'Wrap'
        if ($f.Name -match $NamePattern -and $f.Name.Substring(0,3) -eq $k) {
          $code = $f.Name.Substring(4, 5); $dt = $f.Name.Substring(10, 13)
          $store = if ($code[1] -eq '1') { 'store' } else { 'regular' }
          $kind = @{ '1' = 'item'; '2' = 'world'; '3' = 'avatar' }[[string]$code[2]]
          $when = '{0}/{1}/{2} {3}:{4}' -f $dt.Substring(0,2), $dt.Substring(2,2), $dt.Substring(4,4), $dt.Substring(9,2), $dt.Substring(11,2)
          $line.Text = "$($Sub[$k])\$($f.Name)   $store $kind, $when"; $line.Foreground = '#FFFFFF'; $total++
        } else {
          $line.Text = "$($Sub[$k])\$($f.Name)   not a WAOV asset"; $line.Foreground = '#555555'
        }
        [void]$g.SyncList.Children.Add($line)
      }
      foreach ($d in $dirs) {
        $dl = New-Object System.Windows.Controls.TextBlock; $dl.FontSize = 14; $dl.Margin = '12,0,0,2'; $dl.TextWrapping = 'Wrap'; $dl.Foreground = '#55FF55'
        $dl.Text = "$($Sub[$k])\$($d.Name)   unpacked"; $total++
        [void]$g.SyncList.Children.Add($dl)
      }
    }
    if ($total -gt 0) { $script:Ready4 = $true; if ($paintDots) { & $paintDots } }
    Write-Log 'WAOV-I09' "sync scan finished, $total WAOV assets found"
    $a = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    foreach ($kf in @(@(0, 0), @(0.15, 1), @(0.9, 1), @(1.6, 0))) {
      [void]$a.KeyFrames.Add((New-Object System.Windows.Media.Animation.DiscreteDoubleKeyFrame($kf[1], [TimeSpan]::FromSeconds($kf[0]))))
    }
    if ($SnapDir) { $g.Flash.Opacity = 1 } else { $g.Flash.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a) }
  }

  # ---------- slider 3: MAP ITEM TO AVATAR (helpers in map-avatar.ps1) ----------
  $script:MapRows = @()
  $fillLists = {
    $g.AviList.Items.Clear(); $script:AviChoices = @(Get-AvatarChoices)
    foreach ($a in $script:AviChoices) { [void]$g.AviList.Items.Add(('{0}   ({1})' -f $a.name, $a.from)) }
    if (-not $script:AviChoices.Count) { [void]$g.AviList.Items.Add('no avatar yet: click MAP TO YOUR OWN AVI') }
    $g.PartPick.Items.Clear(); $script:Parts = @(Get-BodyParts); foreach ($p in $script:Parts) { [void]$g.PartPick.Items.Add($p.label) }
    $g.ItemList.Items.Clear(); $script:ItemChoices = @(Get-UnpackedItems)
    foreach ($i in $script:ItemChoices) { [void]$g.ItemList.Items.Add(('{0}   {1}' -f $i.name, $(if ($i.item) { $i.item.bone } else { 'no item.json' }))) }
    if (-not $script:ItemChoices.Count) { [void]$g.ItemList.Items.Add('no unpacked items yet: GET and UNPACK on slider 2') }
  }
  $render3 = {
    $g.MapRows.Children.Clear(); $g.Approve.IsEnabled = $false
    $g.UCheck.IsEnabled = $false
    $ai = $g.AviList.SelectedIndex; $ii = $g.ItemList.SelectedIndex; $pi = $g.PartPick.SelectedIndex
    if ($ai -ge 0 -and $ai -lt $script:AviChoices.Count -and $ii -ge 0 -and $ii -lt $script:ItemChoices.Count -and $pi -lt 0) {
      $want = [string]$script:ItemChoices[$ii].item.bone   # preselect the body part the item was made for
      for ($k = 0; $k -lt $script:Parts.Count; $k++) { if ($script:Parts[$k].role -eq $want) { $g.PartPick.SelectedIndex = $k; return } }
    }
    if ($ai -lt 0 -or $ai -ge $script:AviChoices.Count -or $ii -lt 0 -or $ii -ge $script:ItemChoices.Count -or $pi -lt 0) {
      $t = New-Object System.Windows.Controls.TextBlock; $t.Text = 'Pick your avatar, a body part and an item.'; $t.FontSize = 14; $t.Foreground = '#AAAAAA'
      [void]$g.MapRows.Children.Add($t); return
    }
    $script:MapPick = @{ Avi = $script:AviChoices[$ai]; Item = $script:ItemChoices[$ii]; Part = $script:Parts[$pi] }
    $script:MapRows = @(Test-MapPicks $script:MapPick.Avi.path $script:MapPick.Part $script:MapPick.Item)
    foreach ($r in $script:MapRows) {
      $row = New-Object System.Windows.Controls.TextBlock; $row.FontSize = 13; $row.Margin = '0,0,0,3'; $row.TextWrapping = 'Wrap'
      switch ($r.state) { 'ok' { $m = '[v]'; $c = '#55FF55' } 'warn' { $m = '[!]'; $c = '#FFFF55' } default { $m = '[X]'; $c = '#FF5555' } }
      $row.Text = ('{0} {1}: {2}' -f $m, $r.label, $r.note); $row.Foreground = $c
      if ($r.state -ne 'ok') { $row.Text += "  ($($r.code))" }
      [void]$g.MapRows.Children.Add($row)
    }
    $g.UCheck.IsEnabled = -not ($script:MapRows | Where-Object { $_.state -eq 'bad' })   # APPROVE waits for the Unity check
    $g.MapSteps.Text = 'Fast check done. Click RUN UNITY CHECK to prove the mapping (about a minute).'
  }
  if ($script:HasMap) {
    $g.AviList.Add_SelectionChanged({ & $render3 })
    $g.ItemList.Add_SelectionChanged({ & $render3 })
    $g.PartPick.Add_SelectionChanged({ & $render3 })
    $g.UCheck.Add_Click({
      Play-Beep; $g.UCheck.IsEnabled = $false; $g.MapSteps.Foreground = '#FFFF55'
      $script:UJob = Start-UnityMapCheck $script:MapPick.Avi.path $script:MapPick.Part $script:MapPick.Item
      $script:UDots = 0
      $script:UTimer = New-Object System.Windows.Threading.DispatcherTimer; $script:UTimer.Interval = [TimeSpan]::FromSeconds(1)
      $script:UTimer.Add_Tick({
        $st = Read-UnityMapCheck $script:UJob
        if (-not $st.done) {
          $script:UDots = ($script:UDots + 1) % 4
          $word = @{ copy = 'copying your project to a safe temp folder'; unity = 'Unity is checking in the background' }[[string]$st.stage]
          $g.MapSteps.Text = "$word$('.' * ($script:UDots + 1))   ($($st.minutes) min)`nYou can keep using the menu."; return
        }
        $script:UTimer.Stop(); & $script:UFinish $st.result
      })
      $script:UTimer.Start()
    })
    $script:UFinish = {
      param($res)
      foreach ($r in $res.rows) {
        $row = New-Object System.Windows.Controls.TextBlock; $row.FontSize = 13; $row.Margin = '0,0,0,3'; $row.TextWrapping = 'Wrap'
        switch ($r.state) { 'ok' { $m = '[v]'; $c = '#55FF55' } 'warn' { $m = '[!]'; $c = '#FFFF55' } default { $m = '[X]'; $c = '#FF5555' } }
        $row.Text = ('{0} UNITY {1}: {2}' -f $m, $r.label, $r.note); $row.Foreground = $c; [void]$g.MapRows.Children.Add($row)
      }
      if ($res.pass) { $g.Approve.IsEnabled = $true; $g.MapSteps.Text = '[v] Mapping proven in Unity. APPROVE opens your real project.'; $g.MapSteps.Foreground = '#55FF55' }
      else { $g.UCheck.IsEnabled = $true; $g.MapSteps.Text = 'The Unity check found a problem (red rows). Fix it and run again.'; $g.MapSteps.Foreground = '#FF5555' }
    }
    $g.MapOwn.Add_Click({
      Play-Beep
      $d = New-Object System.Windows.Forms.FolderBrowserDialog
      $d.Description = 'Pick your avatar''s Unity project folder (the one with Assets and Packages inside)'
      if ($d.ShowDialog() -eq 'OK') { Save-Avatar $d.SelectedPath; & $fillLists; $g.AviList.SelectedIndex = 0 }
    })
    $g.Approve.Add_Click({
      Play-Beep
      $g.Approve.IsEnabled = $false
      try {
        $vcc = Open-UnpackedInUnity $script:MapPick.Avi.path $script:MapPick.Item
        $g.MapSteps.Text = "VCC: $vcc. Unity is opening.`nDo these in Unity:`n`n" + ((Get-UnpackedSteps $script:MapPick.Item $script:MapPick.Part) -join "`n")
        $g.MapSteps.Foreground = '#FFFFFF'; $script:MapDone = $true; & $paintDots
      } catch {
        $g.MapSteps.Text = 'problem: ' + $_.Exception.Message; $g.MapSteps.Foreground = '#FF5555'; $g.Approve.IsEnabled = $true
      }
    })
  }

  $script:Slide = 1; $script:Skip1 = $false; $script:Ready4 = $false; $script:MapDone = $false
  $allGreen = { -not (@($Tools | Where-Object { -not $script:ToolState[$_.Key] }).Count) }
  $reachable = {
    param([int]$n)
    if ($SnapDir) { return $true }
    switch ($n) {
      1 { return $true }
      2 { return [bool]((& $allGreen) -or $script:Skip1) }
      3 { return [bool]($script:HasMap -and ((& $allGreen) -or $script:Skip1) -and (@(Get-UnpackedItems).Count -gt 0)) }
      4 { return [bool]$script:Ready4 }
    }
    return $false
  }
  $dotNames = @('1 CHECKS', '2 DOWNLOADS', '3 MAP ITEM', '4 VRCHAT')
  $paintDots = {
    $dots = @($g.Dot1, $g.Dot2, $g.Dot3, $g.Dot4)
    for ($i = 0; $i -lt 4; $i++) {
      $n = $i + 1; $ok = & $reachable $n
      $done = switch ($n) { 1 { [bool](& $allGreen) } 2 { [bool]$script:Ready4 } 3 { [bool]$script:MapDone } default { $false } }
      if ($n -eq $script:Slide) { $mark = '(o) '; $col = '#FFFFFF' }
      elseif ($done) { $mark = '[v] '; $col = '#55FF55' }
      elseif ($ok) { $mark = '( ) '; $col = '#AAAAAA' }
      else { $mark = '( ) '; $col = '#666666' }
      $dots[$i].Text = $mark + $dotNames[$i]; $dots[$i].Foreground = $col
      $dots[$i].Cursor = $(if ($ok) { 'Hand' } else { 'Arrow' })
    }
  }
  $go = {
    param([int]$n)
    if ($n -lt 1) { $n = 1 }; if ($n -gt 4) { $n = 4 }
    if (-not (& $reachable $n)) { return }
    $script:Slide = $n
    $slides = @($g.Slide1, $g.Slide2, $g.Slide3, $g.Slide4)
    for ($i = 0; $i -lt 4; $i++) { if ($i + 1 -eq $n) { $slides[$i].Visibility = 'Visible' } else { $slides[$i].Visibility = 'Collapsed' } }
    & $paintDots
    $hasNext = $false; for ($m = $n + 1; $m -le 4; $m++) { if (& $reachable $m) { $hasNext = $true; break } }
    if ($n -eq 1 -or $hasNext) { $g.Next.Visibility = 'Visible' } else { $g.Next.Visibility = 'Collapsed' }
    if ($n -gt 1) { $g.Back.Visibility = 'Visible' } else { $g.Back.Visibility = 'Collapsed' }
    if ($n -eq 1) { $g.Recheck.Visibility = 'Visible' } else { $g.Recheck.Visibility = 'Collapsed' }
    if ($n -eq 3) { & $fillLists; & $render3 }
    if ($n -eq 4) {
      $g.Slide4Text.Text = "1  Open Unity 2022.3 with your avatar project (OPEN UNITY HUB).`n2  Bring your asset in, then open VRChat SDK > Show Control Panel.`n3  Sign in to VRChat yourself in that panel. We never see or ask for your password.`n4  Open the Builder tab, check the rank, then click Build and Publish yourself.`n5  Press OPEN MY VRCHAT AVATARS to see it on your account."
    }
  }
  $g.Next.Add_Click({
    Play-Beep; if ($script:Slide -eq 1) { $script:Skip1 = $true }
    for ($m = $script:Slide + 1; $m -le 4; $m++) { if (& $reachable $m) { & $go $m; break } }
  })
  $g.Back.Add_Click({ Play-Beep; for ($m = $script:Slide - 1; $m -ge 1; $m--) { if (& $reachable $m) { & $go $m; break } } })
  $g.Dot1.Add_MouseLeftButtonUp({ Play-Beep; & $go 1 }); $g.Dot2.Add_MouseLeftButtonUp({ Play-Beep; & $go 2 })
  $g.Dot3.Add_MouseLeftButtonUp({ Play-Beep; & $go 3 }); $g.Dot4.Add_MouseLeftButtonUp({ Play-Beep; & $go 4 })
  $g.Recheck.Add_Click({ Play-Beep; [void](Step-Check); & $render1 })
  $g.Go.Add_Click({ Play-Beep; & $runQueue @($Tools | Where-Object { -not $script:ToolState[$_.Key] } | ForEach-Object { $_.Key }) })
  # SYNC also CATCHES (2026-11-14): after a Google Drive download the script has a break (the browser saves the zip).
  # SYNC looks in Downloads for zips named like our assets (AVI-/ITE-/WOR- codes, or a store name from the list)
  # and COPIES each into the right WAOV folder. The Downloads file is left alone; a zip already there is skipped.
  $script:CatalogNames = @{}
  $script:Naming = @(@{ prefix = 'AVI'; type = 'avi'; folder = 'WAOV avatars' }, @{ prefix = 'ITE'; type = 'item'; folder = 'WAOV items' }, @{ prefix = 'WOR'; type = 'world'; folder = 'WAOV worlds' })
  $catchDownloads = {
    $dl = Join-Path $env:USERPROFILE 'Downloads'; if (-not (Test-Path $dl)) { return 0 }
    $dirOf = @{ AVI = 'WAOV avatars'; ITE = 'WAOV items'; WOR = 'WAOV worlds'; ITEM = 'WAOV items'; WORLD = 'WAOV worlds' }   # keys are case-insensitive: avi = AVI
    $names = @{}; foreach ($k in @($script:CatalogNames.Keys)) { $names[$k] = $script:CatalogNames[$k] }
    $n = 0
    foreach ($z in Get-ChildItem $dl -Filter '*.zip' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-14) }) {
      $base = ($z.BaseName -replace '\s*\(\d+\)$', '')        # Drive adds " (1)" on a second download
      $type = $null
      foreach ($nr in $script:Naming) { if ($base -match ('^' + [regex]::Escape([string]$nr.prefix) + '-')) { $type = [string]$nr.prefix; break } }
      if (-not $type -and $base -match '^(AVI|ITE|WOR)-\d{5}-\d{8}-\d{4}') { $type = $Matches[1] }
      elseif ($names.ContainsKey($base.ToLower())) { $type = $names[$base.ToLower()] }
      if (-not $type) { continue }
      $folder = $dirOf[$type]; foreach ($nr in $script:Naming) { if ($nr.prefix -eq $type -or $nr.type -eq $type) { $folder = [string]$nr.folder } }
      if (-not $folder) { continue }
      $dirOf[$type] = $folder
      $destDir = Join-Path $AssetsRoot $folder; New-Item -ItemType Directory -Force -Path $destDir | Out-Null
      $dest = Join-Path $destDir ($base + '.zip')
      if ((Test-Path $dest) -and ((Get-Item $dest).Length -eq $z.Length)) { continue }
      try { Copy-Item $z.FullName $dest -Force; $n++; Write-Log 'WAOV-I58' "caught $($z.Name) from Downloads into $($dirOf[$type])" }
      catch { Write-Log 'WAOV-E74' "could not copy $($z.Name): $($_.Exception.Message)" }
    }
    return $n
  }
  $g.Sync.Add_Click({
    Play-Beep
    $caught = & $catchDownloads
    & $syncNow; if ($showCatalog) { & $showCatalog }
    if ($caught) { $g.SyncWhere.Text = "[v] caught $caught new download(s) from Downloads. " + $g.SyncWhere.Text }
  })
  # DOWNLOAD AVATARS + PAIR (2026-11-14). Opens the waov.art store; pairing uses a one-time code, never a password.
  $PairApi = 'https://waov.art/.netlify/functions/widget-pair'
  $PairFile = Join-Path $AppRoot 'pair.json'
  if (Test-Path $PairFile) { try { $pj = Get-Content $PairFile -Raw | ConvertFrom-Json; $g.Pair.Content = 'PAIRED'; $g.PairCode.Text = "paired with $($pj.name)"
    try { $pg = Invoke-RestMethod -Method Post -Uri $PairApi -ContentType 'application/json' -Body (@{ op = 'widget.ping'; token = $pj.token } | ConvertTo-Json) -TimeoutSec 8
      if (-not $pg.paired) { Remove-Item $PairFile -Force; $g.Pair.Content = 'PAIR'; $g.PairCode.Text = 'unpaired on waov.art, click PAIR to pair again' } } catch { } } catch { } }
  # 8-bit attention ripple on PAIR every 2 s until paired: 4 stepped colour frames, 120 ms each
  $script:RipFrames = @('#FFFF55','#55FFFF','#FFFFFF','#AAAAAA'); $script:RipI = -1
  $script:RipTimer = New-Object System.Windows.Threading.DispatcherTimer; $script:RipTimer.Interval = [TimeSpan]::FromMilliseconds(120)
  $script:RipTick = 0
  $script:RipTimer.Add_Tick({
    if ($g.Pair.Content -eq 'PAIRED') { $g.Pair.ClearValue([System.Windows.Controls.Control]::BackgroundProperty); $g.Pair.BorderThickness = 0; $script:RipTimer.Stop(); return }
    $script:RipTick = ($script:RipTick + 1) % 17
    if ($script:RipTick -lt 4) {
      $g.Pair.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($script:RipFrames[$script:RipTick])
    } elseif ($script:RipTick -eq 4) { $g.Pair.ClearValue([System.Windows.Controls.Control]::BackgroundProperty) }
  })
  $script:RipTimer.Start()
  # SEND TO WIDGET ground work (2026-11-14, contract i-install\unpack.txt): GET downloads, UNPACK lays it out for the map step.
  $script:QItem = $null; $script:QZip = $null
  $typeDir = @{ avi = 'WAOV avatars'; item = 'WAOV items'; world = 'WAOV worlds' }
  $checkQueue = {
    if (-not (Test-Path $PairFile)) { return }
    try { $tok = (Get-Content $PairFile -Raw | ConvertFrom-Json).token
      $qr = Invoke-RestMethod -Method Post -Uri $PairApi -ContentType 'application/json' -Body (@{ op = 'widget.queue'; token = $tok } | ConvertTo-Json) -TimeoutSec 10
    } catch { return }
    $next = @($qr.items) | Select-Object -First 1
    if ($next -and (-not $script:QItem -or $script:QItem.sendId -ne $next.sendId)) {
      $script:QItem = $next; $g.Get.Content = "GET $($next.name)"; $g.Get.Visibility = 'Visible'; $g.Unpack.Visibility = 'Collapsed'
      $g.PairCode.Text = "$($next.name) is waiting for you. Click GET."; Write-Log 'WAOV-I53' "queue item $($next.name)"
    }
  }
  function Send-Report([string]$state, [string]$note) {
    try { $tok = (Get-Content $PairFile -Raw | ConvertFrom-Json).token
      Invoke-RestMethod -Method Post -Uri $PairApi -ContentType 'application/json' -Body (@{ op = 'widget.report'; token = $tok; sendId = $script:QItem.sendId; state = $state; note = $note } | ConvertTo-Json) -TimeoutSec 10 | Out-Null } catch { }
  }
  $g.Get.Add_Click({
    Play-Beep; $it = $script:QItem; if (-not $it) { return }
    $dir = Join-Path (Join-Path $AssetsRoot $typeDir[[string]$it.type]) $it.name
    if (Test-Path $dir) { $g.PairCode.Text = "$($it.name) is already here (WAOV-E72)"; Write-Log 'WAOV-E72' "folder exists $dir"; return }
    $tmp = Join-Path $env:TEMP ("waov-" + $it.sendId + ".zip")
    $g.PairCode.Text = "downloading $($it.name)..."
    try { Invoke-WebRequest -Uri $it.url -OutFile $tmp -UseBasicParsing -TimeoutSec 900 } catch { $g.PairCode.Text = 'download failed (WAOV-E73)'; Write-Log 'WAOV-E73' $_.Exception.Message; Send-Report 'failed' 'download'; return }
    Write-Log 'WAOV-I54' "downloaded $($it.name)"
    $h = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
    if ($h -ne [string]$it.sha256) { Remove-Item $tmp -Force; $g.PairCode.Text = 'file check failed (WAOV-E71)'; Write-Log 'WAOV-E71' "hash $h"; Send-Report 'failed' 'hash'; return }
    Write-Log 'WAOV-I55' 'hash ok'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Move-Item $tmp (Join-Path $dir ($it.name + '.zip'))
    $script:QZip = $dir; Send-Report 'downloaded' ''
    $g.Get.Visibility = 'Collapsed'; $g.Unpack.Visibility = 'Visible'; $g.PairCode.Text = "[v] $($it.name) downloaded. Click UNPACK."
  })
  $g.Unpack.Add_Click({
    Play-Beep; $it = $script:QItem; $dir = $script:QZip; if (-not $it -or -not $dir) { return }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $outer = Join-Path $dir ($it.name + '.zip'); $stage = Join-Path $dir '_outer'; $asset = Join-Path $dir 'asset'
    try {
      [System.IO.Compression.ZipFile]::ExtractToDirectory($outer, $stage)
      $inner = Get-ChildItem $stage -Filter '*-asset.zip' -Recurse | Select-Object -First 1
      if ($inner) { [System.IO.Compression.ZipFile]::ExtractToDirectory($inner.FullName, $asset) } else { Move-Item $stage $asset; $stage = $null }
      if ($stage) { Remove-Item $stage -Recurse -Force }
      $ij = Get-ChildItem $asset -Filter 'item.json' -Recurse | Select-Object -First 1
      if ($ij) { Copy-Item $ij.FullName (Join-Path $dir 'item.json') }
      $files = @(Get-ChildItem $asset -Recurse -File | ForEach-Object { $_.FullName.Substring($asset.Length + 1) })
      @{ name = $it.name; type = $it.type; sha256 = $it.sha256; at = (Get-Date).ToString('s'); kitVersion = $KitVersion; files = $files } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $dir 'unpacked.json') -Encoding UTF8
    } catch { $g.PairCode.Text = "unpack failed: $($_.Exception.Message)"; Send-Report 'failed' 'unpack'; return }
    Write-Log 'WAOV-I56' "unpacked $($it.name)"; Send-Report 'unpacked' ''
    $g.Unpack.Visibility = 'Collapsed'; $g.PairCode.Text = "[v] $($it.name) unpacked into $dir"; $script:QItem = $null
    & $syncNow
  })
  # STORE LIST once paired (2026-11-14): Avatars / Items / Worlds, each row has DOWNLOAD that opens its Google Drive page
  $showCatalog = {
    if (-not (Test-Path $PairFile)) { $g.Catalog.Visibility = 'Collapsed'; return }
    try { $tok = (Get-Content $PairFile -Raw | ConvertFrom-Json).token
      $cr = Invoke-RestMethod -Method Post -Uri $PairApi -ContentType 'application/json' -Body (@{ op = 'widget.catalog'; token = $tok } | ConvertTo-Json) -TimeoutSec 10
    } catch { return }
    $g.Catalog.Children.Clear()
    $script:CatalogNames = @{}
    if ($cr.naming) { $script:Naming = @($cr.naming) }
    foreach ($tp in 'avi', 'item', 'world') { foreach ($r in @($cr.catalog.$tp)) { if ($r.name) { $script:CatalogNames[([string]$r.name).ToLower()] = $tp }; if ($r.code) { $script:CatalogNames[([string]$r.code).ToLower()] = $tp } } }
    foreach ($pair in @(@('avi','AVATARS'), @('item','ITEMS'), @('world','WORLDS'))) {
      $h = New-Object System.Windows.Controls.TextBlock; $h.Text = " $($pair[1]) "; $h.FontWeight = 'Bold'; $h.Foreground = '#000000'; $h.Background = '#FFFF55'
      $h.HorizontalAlignment = 'Left'; $h.Margin = '0,6,0,2'; [void]$g.Catalog.Children.Add($h)
      $rows = @($cr.catalog.($pair[0]))
      if (-not $rows.Count) { $e = New-Object System.Windows.Controls.TextBlock; $e.Text = '  nothing here yet'; $e.Foreground = '#AAAAAA'; [void]$g.Catalog.Children.Add($e); continue }
      foreach ($r in $rows) {
        $line = New-Object System.Windows.Controls.DockPanel; $line.Margin = '0,2,0,2'
        if ($r.page) {
          $b = New-Object System.Windows.Controls.Button; $b.Content = 'DOWNLOAD'; $b.Style = $w.FindResource('Px'); $b.Tag = [string]$r.page
          [System.Windows.Controls.DockPanel]::SetDock($b, 'Right')
          $b.Add_Click({ param($sender) Play-Beep; Write-Log 'WAOV-I57' "store list download opened $($sender.Tag)"; Start-Process $sender.Tag })
          [void]$line.Children.Add($b)
        }
        $t = New-Object System.Windows.Controls.TextBlock; $t.Text = "  $($r.name)   $($r.code)"; $t.Foreground = '#FFFFFF'; $t.VerticalAlignment = 'Center'; [void]$line.Children.Add($t)
        [void]$g.Catalog.Children.Add($line)
      }
    }
    $g.Catalog.Visibility = 'Visible'
    $g.SyncWhere.Text = "[v] SYNCED with the backdoor store · $($cr.count) assets · $((Get-Date).ToString('HH:mm'))"
  }
  & $showCatalog
  $script:QTimer = New-Object System.Windows.Threading.DispatcherTimer; $script:QTimer.Interval = [TimeSpan]::FromSeconds(10)
  $script:QTimer.Add_Tick({ if (-not $script:QItem) { & $checkQueue } }); $script:QTimer.Start(); & $checkQueue
  $g.Download.Add_Click({ Play-Beep; if ($DriveLink -match '^https://drive\.google\.com/') { Write-Log 'WAOV-I50' 'download avatars: opened the base Drive folder'; Start-Process $DriveLink } else { Write-Log 'WAOV-I50' 'download avatars: opened the waov.art store'; Start-Process 'https://waov.art/perk-center#store' } })
  $g.Pair.Add_Click({
    Play-Beep
    try {
      $r = Invoke-RestMethod -Method Post -Uri $PairApi -ContentType 'application/json' -Body (@{ op = 'widget.code'; pcName = $env:COMPUTERNAME } | ConvertTo-Json) -TimeoutSec 15
    } catch { $g.PairCode.Text = 'could not reach waov.art (WAOV-E70)'; Write-Log 'WAOV-E70' "pair code request failed: $($_.Exception.Message)"; return }
    $script:PairReq = $r; $script:PairTicks = 0
    $g.PairCode.Text = "Your code: $($r.code)   Type it into PAIR WIDGET on waov.art (bottom right yellow button)."
    Write-Log 'WAOV-I51' "pair code shown $($r.code)"
    Start-Process 'https://waov.art/perk-center#store'
    if ($script:PairTimer) { $script:PairTimer.Stop() }
    $script:PairTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:PairTimer.Interval = [TimeSpan]::FromSeconds(3)
    $script:PairTimer.Add_Tick({
      $script:PairTicks++
      try {
        $p = Invoke-RestMethod -Method Post -Uri $PairApi -ContentType 'application/json' -Body (@{ op = 'widget.poll'; code = $script:PairReq.code; pollKey = $script:PairReq.pollKey } | ConvertTo-Json) -TimeoutSec 10
        if ($p.status -eq 'paired' -and $p.token) {
          $script:PairTimer.Stop()
          @{ token = $p.token; name = $p.name; at = (Get-Date).ToString('s') } | ConvertTo-Json | Set-Content -Path $PairFile -Encoding UTF8
          $g.Pair.Content = 'PAIRED'; $g.PairCode.Text = "[v] paired with $($p.name)"; Play-Beep; & $showCatalog
          Write-Log 'WAOV-I52' 'widget paired with a waov.art account'
        } elseif ($p.status -eq 'expired') { $script:PairTimer.Stop(); $g.PairCode.Text = 'code expired, click PAIR again' }
      } catch { }
    })
    $script:PairTimer.Start()
  })
  $g.Mute.Add_Click({
    $script:Muted = -not $script:Muted
    if ($script:Muted) { $g.Mute.Content = 'SOUND ON'; if ($script:Music) { $script:Music.Stop() } } else { $g.Mute.Content = 'MUTE'; Play-Beep }
  })

  # ---------- 2.0 DRIVE RUN: paste a Google Drive link, drive-fetch.py downloads, unzips, files it and makes the feature image ----------
  $FetchPy = Join-Path $Launcher 'drive-fetch.py'
  $StatusFile = Join-Path $AppRoot 'fetch-status.json'
  if ($DriveLink -match '^https://drive\.google\.com/') { $g.LinkHint.Text = 'DOWNLOAD AVATARS opens our Drive folder. Pick your zips, paste the link here, press RUN.' }
  $script:FetchProc = $null; $script:FetchFinished = $false
  $setFetchBar = { param([double]$f) $wd = [math]::Max(0, $g.FetchBox.ActualWidth - 4); $g.FetchFill.Width = [math]::Max(0, [math]::Min(1, $f)) * $wd }
  $fetchFail = { param([string]$msg, [string]$code) $g.FetchText.Text = "$msg ($code)"; $g.FetchText.Foreground = '#FF5555'; Write-Log $code $msg }
  $g.Run.Add_Click({
    Play-Beep
    $link = $g.LinkBox.Text.Trim()
    if ($link -notmatch '^https://drive\.google\.com/[A-Za-z0-9/_\-?=&%.#]+$') { & $fetchFail 'Paste a Google Drive link that starts with https://drive.google.com/' 'WAOV-E75'; return }
    $py = Get-PythonExe
    if (-not $py -or -not (Test-PyLibs $py)) { & $fetchFail 'Python is not ready. Go to 1 CHECKS and press GO' 'WAOV-E76'; return }
    if (-not (Test-Path $FetchPy)) { & $fetchFail 'drive-fetch.py is missing from this kit' 'WAOV-E77'; return }
    New-Item -ItemType Directory -Path $AppRoot -Force | Out-Null
    if (Test-Path $StatusFile) { Remove-Item $StatusFile -Force -ErrorAction SilentlyContinue }
    $g.Run.IsEnabled = $false; $g.ResultBox.Visibility = 'Collapsed'; $g.Upload.IsEnabled = $false; $g.UpTile.Visibility = 'Collapsed'
    $g.FetchText.Foreground = '#FFFF55'; $g.FetchText.Text = 'starting ...'; & $setFetchBar 0.02; $script:FetchFinished = $false
    $script:FetchProc = Start-Process -FilePath $py -ArgumentList @(('"' + $FetchPy + '"'), '--link', ('"' + $link + '"'), '--assets', ('"' + $AssetsRoot + '"'), '--status', ('"' + $StatusFile + '"'), '--kit', $KitVersion) -PassThru -WindowStyle Hidden
    Write-Log 'WAOV-I60' 'drive run started'
    if ($script:FetchTimer) { $script:FetchTimer.Stop() }
    $script:FetchTimer = New-Object System.Windows.Threading.DispatcherTimer; $script:FetchTimer.Interval = [TimeSpan]::FromMilliseconds(700)
    $script:FetchTimer.Add_Tick({
      $st = $null; if (Test-Path $StatusFile) { try { $st = Get-Content $StatusFile -Raw | ConvertFrom-Json } catch { } }
      if ($st) { & $setFetchBar ([double]$st.pct); $g.FetchText.Text = [string]$st.line }
      $over = ($st -and $st.done) -or $script:FetchProc.HasExited
      if (-not $over) { return }
      $script:FetchTimer.Stop(); $script:FetchFinished = $true; $g.Run.IsEnabled = $true
      if ($st -and $st.done -and $st.ok -and @($st.items).Count) {
        & $setFetchBar 1
        $it = @($st.items)[0]
        try { $bi = New-Object System.Windows.Media.Imaging.BitmapImage; $bi.BeginInit(); $bi.UriSource = New-Object Uri ([string]$it.feature); $bi.CacheOption = 'OnLoad'; $bi.EndInit(); $g.FeatureImg.Source = $bi } catch { }
        $n = @($st.items).Count
        if ($n -eq 1) { $g.ResultText.Text = "[v] Downloaded: $($it.name)`n$($it.kind), filed in $($it.folder)" } else { $g.ResultText.Text = "[v] $n assets downloaded, filed and unpacked.`nShowing $($it.name)." }
        $g.ResultBox.Visibility = 'Visible'; $g.Upload.IsEnabled = $true
        $script:Ready4 = $true; Write-Log 'WAOV-I61' "drive run finished, $n asset(s)"
        & $syncNow; & $paintDots
      } else {
        $msg = if ($st -and $st.line) { [string]$st.line } else { 'The download did not finish. Check the link is shared with anyone who has it, then press RUN again.' }
        & $fetchFail $msg 'WAOV-E78'
      }
    })
    $script:FetchTimer.Start()
  })
  $g.Upload.Add_Click({ Play-Beep; $g.UpTile.Visibility = 'Visible'; Write-Log 'WAOV-I62' 'upload tile shown: buyer signs in to VRChat themselves' })
  $g.UpGo.Add_Click({ Play-Beep; & $go 4 })
  $g.OpenHub.Add_Click({ Play-Beep; $h = Get-HubExe; if ($h) { Start-Process $h } else { Start-Process 'https://unity.com/download' } })
  $g.OpenVrc.Add_Click({ Play-Beep; Start-Process 'https://vrchat.com/home/avatars' })

  $blink = New-Object System.Windows.Threading.DispatcherTimer; $blink.Interval = [TimeSpan]::FromMilliseconds(500)
  $blink.Add_Tick({ if ($g.Cursor.Opacity -gt 0) { $g.Cursor.Opacity = 0 } else { $g.Cursor.Opacity = 1 } }); $blink.Start()

  if (-not $script:ToolState.Count) { [void](Step-Check) }
  & $render1
  $w.Add_ContentRendered({ Fade-In $g.Root })
  if ($AutoGo) { $w.Add_ContentRendered({ $g.Go.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }) }
  if ($SnapDir) {
    $script:snap = New-Object System.Windows.Threading.DispatcherTimer; $script:snap.Interval = [TimeSpan]::FromSeconds(2.6)
    $script:snapStep = 0
    $script:Acts = @(
      { Save-Snap $w $(if ($AutoGo) { 'menu-1-installing.png' } else { 'menu-1-checks.png' }) },
      { Save-Snap $w 'menu-1-done.png'; & $go 2; & $syncNow
        if ($TestLink) { $g.LinkBox.Text = $TestLink; $g.Run.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } },
      { Save-Snap $w 'menu-2-downloads.png'; if ($g.Upload.IsEnabled) { $g.Upload.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } },
      { Save-Snap $w 'menu-2-uptile.png'; if ($script:HasMap) { & $go 3; if ($script:AviChoices.Count) { $g.AviList.SelectedIndex = 0 }; if ($script:ItemChoices.Count) { $g.ItemList.SelectedIndex = 0 } } else { & $go 4 } },
      { if ($script:HasMap) { Save-Snap $w 'menu-3-map.png' }; & $go 4 },
      { Save-Snap $w 'menu-4-vrchat.png'; $script:snap.Stop(); $w.Close() }
    )
    $script:snap.Add_Tick({
      if ($script:snapStep -ge 1 -and $script:QTimer2 -and $script:QTimer2.IsEnabled) { return }                     # wait for the install queue
      if ($script:snapStep -ge 2 -and $script:FetchProc -and -not $script:FetchFinished) { return }                   # wait for the Drive run
      & $script:Acts[$script:snapStep]; $script:snapStep++
    })
    $script:snap.Start()
  }
  [void]$w.ShowDialog()
}

if ($Menu) { Show-Menu; return }

# ---------- loading window (install) ----------
$lx = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
  Title="We Are One Voice" Width="1100" Height="614" WindowStyle="None" ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
  Background="#000000" TextOptions.TextRenderingMode="Aliased" TextOptions.TextFormattingMode="Display" FontFamily="Consolas">
  <Grid x:Name="Root" Opacity="0">
    <Image x:Name="Base" Stretch="Fill" RenderOptions.BitmapScalingMode="NearestNeighbor"/>
    <Canvas x:Name="Band" Height="106" VerticalAlignment="Bottom" ClipToBounds="True">
      <Rectangle Canvas.Left="40" Canvas.Top="58" Width="760" Height="26" Stroke="#FFFFFF" StrokeThickness="3"/>
      <StackPanel x:Name="Blocks" Orientation="Horizontal" Canvas.Left="46" Canvas.Top="64"/>
      <Image x:Name="Trail" Canvas.Top="14" Height="28" Stretch="Fill" RenderOptions.BitmapScalingMode="NearestNeighbor"/>
      <Image x:Name="Cat" Canvas.Top="4" Width="64" Height="44" RenderOptions.BitmapScalingMode="NearestNeighbor"/>
      <TextBlock x:Name="Loading" Text="L O A D I N G" Canvas.Left="830" Canvas.Top="56" FontSize="24" FontWeight="Bold" Foreground="#FFFF55"/>
      <TextBlock x:Name="Status" Canvas.Left="46" Canvas.Top="88" FontSize="11" Foreground="#AAAAAA"/>
      <Button x:Name="Mute" Canvas.Left="990" Canvas.Top="8" Content="MUTE" Style="{DynamicResource Px}" FontSize="12" Padding="8,3"/>
      <TextBlock x:Name="LStamp" Canvas.Left="992" Canvas.Top="62" FontSize="16" FontWeight="Bold" Foreground="#55FFFF"/>
    </Canvas>
  </Grid>
</Window>
'@
$lw = New-Xaml $lx
$lw.Resources.MergedDictionaries.Add((New-Xaml $Styles))
try { $lw.Icon = Img 'waov.ico' } catch { }
$L = @{}; foreach ($n in 'Root','Base','Band','Blocks','Trail','Cat','Loading','Status','Mute','LStamp') { $L[$n] = $lw.FindName($n) }
$L.LStamp.Text = "v$KitVersion"
$L.Base.Source = Img 'base.png'
$L.Trail.Source = Img 'trail.png'
$catFrames = @(0..3 | ForEach-Object { Img "cat-$_.png" })
$L.Cat.Source = $catFrames[0]
$L.Mute.Add_Click({
  $script:Muted = -not $script:Muted
  if ($script:Muted) { $L.Mute.Content = 'SOUND'; if ($script:Music) { $script:Music.Stop() } } else { $L.Mute.Content = 'MUTE'; if ($script:Music) { $script:Music.PlayLooping() } }
})

Write-Log 'WAOV-I01' "launcher started, kit $KitVersion, from $Here"
$Steps = @(
  @{ Name = 'checking the installed version'; Do = { Step-Version } },
  @{ Name = 'making your WAOV assets folders'; Do = { Step-Folders } },
  @{ Name = 'copying your asset zip'; Do = { Step-ZipCopy } },
  @{ Name = 'installing the launcher'; Do = { Step-Kit } },
  @{ Name = 'checking Creator Companion, Unity and Blender'; Do = { Step-Check } }
)
$script:stepIx = 0; $script:progress = 0.0; $script:frame = 0; $script:failed = $false
$blockCount = 30

$anim = New-Object System.Windows.Threading.DispatcherTimer
$anim.Interval = [TimeSpan]::FromMilliseconds(90)
$anim.Add_Tick({
  # target progress follows the real steps; the bar eases toward it
  $target = [math]::Min(1.0, ($script:stepIx / $Steps.Count))
  if ($script:progress -lt $target) { $script:progress = [math]::Min($target, $script:progress + 0.012) }
  $want = [int][math]::Floor($script:progress * $blockCount)
  $colors = '#FF5555','#FFFF55','#55FF55','#55FFFF','#5555FF','#FF55FF'
  while ($L.Blocks.Children.Count -lt $want) {
    $r = New-Object System.Windows.Shapes.Rectangle; $r.Width = 21; $r.Height = 14; $r.Margin = '0,0,4,0'
    $r.Fill = $colors[$L.Blocks.Children.Count % $colors.Count]; [void]$L.Blocks.Children.Add($r)
  }
  $x = 40 + $script:progress * 700
  [System.Windows.Controls.Canvas]::SetLeft($L.Cat, $x)
  $tw = [math]::Min(160, [math]::Max(0, $x - 40)); $L.Trail.Width = $tw; [System.Windows.Controls.Canvas]::SetLeft($L.Trail, $x - $tw + 6)
  $script:frame++
  $L.Cat.Source = $catFrames[$script:frame % 4]
  if ($script:frame % 6 -eq 0) { if ($L.Loading.Opacity -gt 0) { $L.Loading.Opacity = 0 } else { $L.Loading.Opacity = 1 } }
  if ($script:stepIx -ge $Steps.Count -and $script:progress -ge 1.0) {
    $anim.Stop()
    if ($SnapDir) { Save-Snap $lw 'loading.png' }
    $done = New-Object System.Windows.Threading.DispatcherTimer; $done.Interval = [TimeSpan]::FromMilliseconds(700)
    $done.Add_Tick({ param($s, $e) $s.Stop(); $lw.Close() }); $done.Start()
  }
})

$work = New-Object System.Windows.Threading.DispatcherTimer
$work.Interval = [TimeSpan]::FromMilliseconds(650)
$work.Add_Tick({
  if ($script:stepIx -ge $Steps.Count) { $work.Stop(); return }
  $st = $Steps[$script:stepIx]
  $L.Status.Text = $st.Name + '...'
  try { $msg = & $st.Do; $L.Status.Text = [string]$msg }
  catch { $script:failed = $true; $L.Status.Text = 'problem: ' + $_.Exception.Message; Write-Log 'WAOV-E01' ($st.Name + ': ' + $_.Exception.Message) }
  $script:stepIx++
})

$lw.Add_ContentRendered({
  # opens black, fades in over 2 seconds; nothing moves or plays until the fade is done
  Fade-In $L.Root
  $startT = New-Object System.Windows.Threading.DispatcherTimer; $startT.Interval = [TimeSpan]::FromSeconds(2)
  $startT.Add_Tick({ param($s, $e) $s.Stop()
    if (-not $script:Muted -and $script:Music -and -not $SnapDir) { try { $script:Music.PlayLooping() } catch { } }
    $anim.Start(); $work.Start() })
  $startT.Start()
})
[void]$lw.ShowDialog()
if ($script:Music) { try { $script:Music.Stop() } catch { } }
Show-Menu
