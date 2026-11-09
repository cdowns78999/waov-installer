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
  [string]$ZipRootOverride = ""
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
          <TextBlock x:Name="Dot2" Text="( ) 2 SYNC YOUR WAOV ASSETS" FontSize="15" FontWeight="Bold" Foreground="#AAAAAA"/>
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
            <TextBlock x:Name="Flash" Text="  [v] SYNCED" FontSize="20" FontWeight="Bold" Foreground="#55FF55" Opacity="0" VerticalAlignment="Center"/>
          </StackPanel>
          <TextBlock DockPanel.Dock="Top" x:Name="SyncWhere" FontSize="12" Foreground="#AAAAAA" Margin="0,8,0,4"/>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="SyncList"/></ScrollViewer>
        </DockPanel>
      </Grid>
    </DockPanel>
  </Grid>
</Window>
'@
  $w = New-Xaml $x
  $w.Resources.MergedDictionaries.Add((New-Xaml $Styles))
  try { $w.Icon = Img 'waov.ico' } catch { }
  $g = @{}; foreach ($n in 'Root','Cursor','Dot1','Dot2','Mute','Next','Back','Recheck','Slide1','Slide2','Sync','Flash','SyncWhere','SyncList','Stamp','StampNote') { $g[$n] = $w.FindName($n) }
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

  $go = {
    param([int]$n)
    if ($n -eq 1) { $g.Slide1.Visibility = 'Visible'; $g.Slide2.Visibility = 'Collapsed'; $g.Dot1.Text = '(o) 1 RUN THE CHECK'; $g.Dot1.Foreground = '#FFFFFF'; $g.Dot2.Text = '( ) 2 SYNC YOUR WAOV ASSETS'; $g.Dot2.Foreground = '#AAAAAA'; $g.Next.Visibility = 'Visible'; $g.Recheck.Visibility = 'Visible'; $g.Back.Visibility = 'Collapsed' }
    else { $g.Slide1.Visibility = 'Collapsed'; $g.Slide2.Visibility = 'Visible'; $g.Dot1.Text = '( ) 1 RUN THE CHECK'; $g.Dot1.Foreground = '#AAAAAA'; $g.Dot2.Text = '(o) 2 SYNC YOUR WAOV ASSETS'; $g.Dot2.Foreground = '#FFFFFF'; $g.Next.Visibility = 'Collapsed'; $g.Recheck.Visibility = 'Collapsed'; $g.Back.Visibility = 'Visible' }
  }
  $g.Next.Add_Click({ Play-Beep; & $go 2 })
  $g.Back.Add_Click({ Play-Beep; & $go 1 })
  $g.Recheck.Add_Click({ Play-Beep; [void](Step-Check); & $render1 })
  $g.Sync.Add_Click({ Play-Beep; & $syncNow })
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
      elseif ($script:snapStep -eq 2) { Save-Snap $w 'menu-slider2.png'; $snap.Stop(); $w.Close() }
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
