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
  [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$KitVersion = '1.0'
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
  @{ Key = 'Blender'; Label = 'Blender'; Winget = 'BlenderFoundation.Blender'; Page = 'https://www.blender.org/download/'; Ok = 'WAOV-I13'; Bad = 'WAOV-E13' }
)
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
function Test-Tool([string]$Key) {
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
  return "tool check: $n of 4 installed"
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
  Title="We Are One Voice" Width="860" Height="560" WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize" Background="#000000"
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
          <TextBlock x:Name="Dot1" Text="(o) 1 RUN THE CHECK" FontSize="15" FontWeight="Bold" Foreground="#FFFFFF" Margin="0,0,30,0"/>
          <TextBlock x:Name="Dot2" Text="( ) 2 SYNC YOUR WAOV ASSETS" FontSize="15" FontWeight="Bold" Foreground="#AAAAAA" Margin="0,0,30,0"/>
          <TextBlock x:Name="Dot3" Text="( ) 3 MAP ITEM TO AVATAR" FontSize="15" FontWeight="Bold" Foreground="#AAAAAA"/>
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
        <StackPanel x:Name="Slide1" Margin="4,16,4,0"/>
        <DockPanel x:Name="Slide2" Visibility="Collapsed" Margin="4,12,4,0">
          <StackPanel DockPanel.Dock="Top" Orientation="Horizontal">
            <Button x:Name="Sync" Content="SYNC ASSETS" Style="{DynamicResource Px}" Margin="0"/>
            <Button x:Name="Download" Content="DOWNLOAD AVATARS" Style="{DynamicResource Px}"/>
            <Button x:Name="Pair" Content="PAIR" Style="{DynamicResource Px}" Margin="0"/>
            <Button x:Name="Get" Content="GET" Style="{DynamicResource Px}" Visibility="Collapsed"/>
            <Button x:Name="Unpack" Content="UNPACK" Style="{DynamicResource Px}" Visibility="Collapsed" Margin="0"/>
            <TextBlock x:Name="Flash" Text="  [v] SYNCED" FontSize="20" FontWeight="Bold" Foreground="#55FF55" Opacity="0" VerticalAlignment="Center"/>
          </StackPanel>
          <TextBlock DockPanel.Dock="Top" x:Name="PairCode" FontSize="14" FontWeight="Bold" Foreground="#FFFF55" Margin="0,8,0,0" TextWrapping="Wrap"/>
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
      </Grid>
    </DockPanel>
  </Grid>
</Window>
'@
  $w = New-Xaml $x
  $w.Resources.MergedDictionaries.Add((New-Xaml $Styles))
  try { $w.Icon = Img 'waov.ico' } catch { }
  $g = @{}; foreach ($n in 'Root','Cursor','Dot1','Dot2','Dot3','Mute','Next','Back','Recheck','Slide1','Slide2','Slide3','Sync','Download','Pair','PairCode','Get','Unpack','Catalog','Flash','SyncWhere','SyncList','Stamp','StampNote','MapOwn','AviList','ItemList','MapRows','Approve','MapSteps','PartPick','UCheck') { $g[$n] = $w.FindName($n) }
  if (-not $script:HasMap) { $g.Dot3.Visibility = 'Collapsed' }
  $g.Stamp.Text = "v$KitVersion"
  if ($script:UpdateNote -and $script:UpdateNote -ne 'offline') { $g.Stamp.Foreground = '#FFFF55'; $g.StampNote.Text = 'UPDATE AVAILABLE: ' + $script:UpdateNote }
  elseif ($script:UpdateNote -eq 'offline') { $g.StampNote.Text = 'offline, not checked' }
  if ($script:Muted) { $g.Mute.Content = 'SOUND ON' }

  $render1 = {
    $g.Slide1.Children.Clear()
    foreach ($t in $Tools) {
      $ok = [bool]$script:ToolState[$t.Key]
      $row = New-Object System.Windows.Controls.DockPanel; $row.Margin = '0,0,0,14'; $row.LastChildFill = $false
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
      [void]$g.Slide1.Children.Add($row)
    }
  }
  $script:GetIt = @{}
  $installTool = {
    param($btn)
    $t = $btn.Tag
    if ([string]$btn.Content -eq 'GET IT') { Start-Process $t.Page; return }
    $btn.IsEnabled = $false; $btn.Content = 'INSTALLING...'
    if ($t.Key -eq 'Unity') {
      $hub = Get-HubExe
      $p = Start-Process -FilePath $hub -ArgumentList @('--', '--headless', 'install', '--version', $UnityVersion, '--changeset', $UnityChangeset, '--module', 'windows-mono') -PassThru -WindowStyle Hidden
    } else {
      $p = Start-Process -FilePath 'winget' -ArgumentList @('install', '--id', $t.Winget, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements') -PassThru -WindowStyle Hidden
    }
    $timer = New-Object System.Windows.Threading.DispatcherTimer; $timer.Interval = [TimeSpan]::FromSeconds(2)
    $timer.Tag = @{ P = $p; T = $t }
    $timer.Add_Tick({ param($s, $e)
      $d = $s.Tag
      if (-not $d.P.HasExited) { return }
      $s.Stop()
      $ok = Test-Tool $d.T.Key
      $script:ToolState[$d.T.Key] = $ok
      if ($ok) { Write-Log 'WAOV-I14' "$($d.T.Label) installed by the buyer's click and verified" }
      else { Write-Log 'WAOV-E14' "$($d.T.Label) install failed (exit $($d.P.ExitCode)), GET IT offered"; $script:GetIt[$d.T.Key] = $true }
      & $render1
    })
    $timer.Start()
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
      if (-not $files.Count) {
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
    }
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
        $g.MapSteps.Foreground = '#FFFFFF'
      } catch {
        $g.MapSteps.Text = 'problem: ' + $_.Exception.Message; $g.MapSteps.Foreground = '#FF5555'; $g.Approve.IsEnabled = $true
      }
    })
  }

  $script:Slide = 1
  $go = {
    param([int]$n)
    $max = 2; if ($script:HasMap) { $max = 3 }
    if ($n -lt 1) { $n = 1 }; if ($n -gt $max) { $n = $max }
    $script:Slide = $n
    $names = @('1 RUN THE CHECK', '2 SYNC YOUR WAOV ASSETS', '3 MAP ITEM TO AVATAR')
    $slides = @($g.Slide1, $g.Slide2, $g.Slide3); $dots = @($g.Dot1, $g.Dot2, $g.Dot3)
    for ($i = 0; $i -lt 3; $i++) {
      if ($i + 1 -eq $n) { $slides[$i].Visibility = 'Visible'; $dots[$i].Text = '(o) ' + $names[$i]; $dots[$i].Foreground = '#FFFFFF' }
      else { $slides[$i].Visibility = 'Collapsed'; $dots[$i].Text = '( ) ' + $names[$i]; $dots[$i].Foreground = '#AAAAAA' }
    }
    if ($n -lt $max) { $g.Next.Visibility = 'Visible' } else { $g.Next.Visibility = 'Collapsed' }
    if ($n -gt 1) { $g.Back.Visibility = 'Visible' } else { $g.Back.Visibility = 'Collapsed' }
    if ($n -eq 1) { $g.Recheck.Visibility = 'Visible' } else { $g.Recheck.Visibility = 'Collapsed' }
    if ($n -eq 3) { & $fillLists; & $render3 }
  }
  $g.Next.Add_Click({ Play-Beep; & $go ($script:Slide + 1) })
  $g.Back.Add_Click({ Play-Beep; & $go ($script:Slide - 1) })
  $g.Recheck.Add_Click({ Play-Beep; [void](Step-Check); & $render1 })
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
  $g.Download.Add_Click({ Play-Beep; Write-Log 'WAOV-I50' 'download avatars: opened the waov.art store'; Start-Process 'https://waov.art/perk-center#store' })
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

  $blink = New-Object System.Windows.Threading.DispatcherTimer; $blink.Interval = [TimeSpan]::FromMilliseconds(500)
  $blink.Add_Tick({ if ($g.Cursor.Opacity -gt 0) { $g.Cursor.Opacity = 0 } else { $g.Cursor.Opacity = 1 } }); $blink.Start()

  if (-not $script:ToolState.Count) { [void](Step-Check) }
  & $render1
  $w.Add_ContentRendered({ Fade-In $g.Root })
  if ($SnapDir) {
    $snap = New-Object System.Windows.Threading.DispatcherTimer; $snap.Interval = [TimeSpan]::FromSeconds(2.6)
    $script:snapStep = 0
    $snap.Add_Tick({
      $script:snapStep++
      if ($script:snapStep -eq 1) { Save-Snap $w 'menu-slider1.png'; & $go 2; & $syncNow }
      elseif ($script:snapStep -eq 2) {
        Save-Snap $w 'menu-slider2.png'
        if ($script:HasMap) { & $go 3; if ($script:AviChoices.Count) { $g.AviList.SelectedIndex = 0 }; if ($script:ItemChoices.Count) { $g.ItemList.SelectedIndex = 0 } }
        else { $snap.Stop(); $w.Close() }
      }
      elseif ($script:snapStep -eq 3) { Save-Snap $w 'menu-slider3.png'; $snap.Stop(); $w.Close() }
    })
    $snap.Start()
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
