<#
  map-avatar.ps1  -  slider 3, MAP ITEM TO AVATAR (2026-11-11, branch map-avatar-1111)
  Dot-sourced by "Miles Installer and Updater.ps1". Plain readable source, no hidden code.
  Contract: waov-comm skill, i-install\install.txt section 5b. Codes: i-install\codes.txt (I40 to I44, W40 to W42, E60 to E65).

  What it touches
    reads   the avatar project folder (Assets\*.fbx.meta, Packages\vpm-manifest.json, ProjectSettings\ProjectVersion.txt),
            the WAOV items zips in Documents\WAOV assets\WAOV items (item.json inside), VCC's settings.json
    writes  %LOCALAPPDATA%\WAOV\avatars.json (the avatars the person mapped), %LOCALAPPDATA%\WAOV\items\{NAME}\ (the item package),
            and ONLY after the person clicks APPROVE: their project path added to VCC's project list (VCC closed, backup first)
    starts  Unity 2022.3.22f1 on their project with -importPackage, on that same click
  Never: uploads, signs in, edits a scene, or touches GoGo Loco. The person drags the item and clicks Build and Publish.
#>
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$MapFile = Join-Path $AppRoot 'avatars.json'
if (-not $VccSettings) { $VccSettings = Join-Path $env:LOCALAPPDATA 'VRChatCreatorCompanion\settings.json' }
$ItemStage = Join-Path $AppRoot 'items'
# Humanoid bone roles an item may name (Unity HumanBodyBones). Optional bones get a check against the avatar's map.
$BoneRoles = @('Hips','Spine','Chest','UpperChest','Neck','Head','LeftShoulder','RightShoulder','LeftUpperArm','RightUpperArm',
               'LeftLowerArm','RightLowerArm','LeftHand','RightHand','LeftUpperLeg','RightUpperLeg','LeftLowerLeg','RightLowerLeg',
               'LeftFoot','RightFoot','LeftToes','RightToes','Jaw','LeftEye','RightEye')

# ---------- avatars the person mapped (Map to your own Avi) ----------
function Get-SavedAvatars {
  if (-not (Test-Path $MapFile)) { return @() }
  try { return @((Get-Content $MapFile -Raw | ConvertFrom-Json) | Where-Object { $_.path }) } catch { return @() }
}
function Save-Avatar([string]$Path) {
  $Path = $Path.TrimEnd('\')
  $list = @(Get-SavedAvatars | Where-Object { $_.path -ne $Path })
  $list += [pscustomobject]@{ name = (Split-Path -Leaf $Path); path = $Path; saved = (Get-Date -Format 'yyyy-MM-dd HH:mm') }
  New-Item -ItemType Directory -Path $AppRoot -Force | Out-Null
  ConvertTo-Json -InputObject @($list) -Depth 4 | Set-Content -Path $MapFile -Encoding UTF8
  Write-Log 'WAOV-I40' "avatar project saved: $Path"
}

# ---------- VCC project list ----------
function Get-VccProjects {
  if (-not (Test-Path $VccSettings)) { return @() }
  try { return @((Get-Content $VccSettings -Raw | ConvertFrom-Json).userProjects | Where-Object { $_ }) } catch { return @() }
}
# VCC lists can hold stale paths (a removed drive, a deleted folder): those are skipped, never an error.
function Test-AvatarFolder([string]$Path) {
  try {
    $m = Join-Path $Path 'Packages\vpm-manifest.json'
    return ((Test-Path -LiteralPath $m -ErrorAction Stop) -and ((Get-Content -LiteralPath $m -Raw) -match '"com\.vrchat\.avatars"'))
  } catch { return $false }
}
# Saved avatars first, then VCC projects that carry the VRChat Avatars SDK. One row per folder.
function Get-AvatarChoices {
  $out = New-Object System.Collections.ArrayList; $seen = @{}
  foreach ($a in Get-SavedAvatars) {
    if ($seen[$a.path.ToLower()]) { continue }; $seen[$a.path.ToLower()] = $true
    [void]$out.Add([pscustomobject]@{ name = $a.name; path = $a.path; from = 'saved' })
  }
  foreach ($p in Get-VccProjects) {
    $p = ([string]$p).TrimEnd('\')
    if ($seen[$p.ToLower()] -or -not (Test-AvatarFolder $p)) { continue }; $seen[$p.ToLower()] = $true
    [void]$out.Add([pscustomobject]@{ name = (Split-Path -Leaf $p); path = $p; from = 'VCC' })
  }
  return @($out)
}

# ---------- WAOV items (item.json inside each ITE zip) ----------
function Read-Entry($e) { $r = New-Object IO.StreamReader($e.Open()); try { $r.ReadToEnd() } finally { $r.Close() } }
# Opens {NAME}.zip, or the {NAME}-asset.zip inside it, and hands the archive that holds item.json to $Action.
function Use-ItemArchive([string]$Zip, [scriptblock]$Action) {
  $outer = [IO.Compression.ZipFile]::OpenRead($Zip)
  try {
    if ($outer.Entries | Where-Object { $_.Name -eq 'item.json' }) { return (& $Action $outer) }
    $inner = $outer.Entries | Where-Object { $_.Name -like '*-asset.zip' } | Select-Object -First 1
    if (-not $inner) { return $null }
    $ms = New-Object IO.MemoryStream; $s = $inner.Open(); $s.CopyTo($ms); $s.Close(); $ms.Position = 0
    $z2 = New-Object IO.Compression.ZipArchive($ms, [IO.Compression.ZipArchiveMode]::Read)
    try { return (& $Action $z2) } finally { $z2.Dispose() }
  } finally { $outer.Dispose() }
}
function Get-WaovItems {
  $dir = Join-Path $AssetsRoot $Sub['ITE']
  $out = New-Object System.Collections.ArrayList
  foreach ($f in @(Get-ChildItem -Path $dir -Filter '*.zip' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $NamePattern })) {
    $j = $null
    try { $j = Use-ItemArchive $f.FullName { param($z) $e = $z.Entries | Where-Object { $_.Name -eq 'item.json' } | Select-Object -First 1; if ($e) { Read-Entry $e | ConvertFrom-Json } } } catch { }
    if ($j -and $j.bone -and $j.package) { Write-Log 'WAOV-I41' "item read: $($f.Name), bone $($j.bone)" }
    else { Write-Log 'WAOV-E64' "item.json missing or unreadable in $($f.Name)"; $j = $null }
    [void]$out.Add([pscustomobject]@{ zip = $f.FullName; file = $f.Name; manifest = $j })
  }
  return @($out)
}

# ---------- the check (runs on every pick, never changes anything) ----------
function Get-UnityExe {
  $roots = @("$env:ProgramFiles\Unity\Hub\Editor")
  $sec = Join-Path $env:APPDATA 'UnityHub\secondaryInstallPath.json'
  if (Test-Path $sec) { try { $p = (Get-Content $sec -Raw | ConvertFrom-Json); if ($p) { $roots += [string]$p } } catch { } }
  foreach ($r in $roots) { $e = Join-Path $r "$UnityVersion\Editor\Unity.exe"; if ($r -and (Test-Path $e)) { return $e } }
  return $null
}
function New-Row([string]$Label, [string]$State, [string]$Note, [string]$Code) {
  [pscustomobject]@{ label = $Label; state = $State; note = $Note; code = $Code }
}
# Returns rows with state ok (green), warn (yellow, can still go on) or bad (red, APPROVE stays off).
function Test-MapReady([string]$Project, $Item) {
  $rows = New-Object System.Collections.ArrayList
  $j = $null; if ($Item) { $j = $Item.manifest }
  if (-not $j) { [void]$rows.Add((New-Row 'Item details (item.json)' 'bad' 'missing in this zip, ask Miles for a newer zip' 'WAOV-E64')) }
  elseif ($BoneRoles -notcontains [string]$j.bone) { [void]$rows.Add((New-Row 'Item details (item.json)' 'bad' "unknown bone role '$($j.bone)'" 'WAOV-E64')) }
  else { [void]$rows.Add((New-Row 'Item details (item.json)' 'ok' "sits on $($j.bone)" 'WAOV-I41')) }

  $pv = Join-Path $Project 'ProjectSettings\ProjectVersion.txt'
  $isProj = $false; try { $isProj = (Test-Path -LiteralPath (Join-Path $Project 'Assets') -ErrorAction Stop) -and (Test-Path -LiteralPath $pv -ErrorAction Stop) } catch { }
  if (-not $isProj) {
    [void]$rows.Add((New-Row 'Unity project' 'bad' 'no Assets and ProjectSettings folders here' 'WAOV-E60')); return @($rows)
  }
  $ver = ((Select-String -Path $pv -Pattern 'm_EditorVersion:\s*(\S+)' | Select-Object -First 1).Matches[0].Groups[1].Value)
  if ($ver -like '2022.3*') { [void]$rows.Add((New-Row 'Unity version' 'ok' $ver 'WAOV-I42')) }
  else { [void]$rows.Add((New-Row 'Unity version' 'warn' "$ver, VRChat needs 2022.3 (VCC can migrate it)" 'WAOV-W42')) }

  $man = Join-Path $Project 'Packages\vpm-manifest.json'; $mtext = ''
  if (Test-Path $man) { $mtext = Get-Content $man -Raw }
  if ($mtext -match '"com\.vrchat\.avatars"') { [void]$rows.Add((New-Row 'VRChat Avatars SDK' 'ok' 'in the project' 'WAOV-I42')) }
  else { [void]$rows.Add((New-Row 'VRChat Avatars SDK' 'bad' 'not in this project, open it in VCC as an avatar project' 'WAOV-E61')) }
  if ($mtext -match '"nadena\.dev\.modular-avatar"') { [void]$rows.Add((New-Row 'Modular Avatar' 'ok' 'in the project' 'WAOV-I42')) }
  else { [void]$rows.Add((New-Row 'Modular Avatar' 'warn' 'add it in VCC before you drag the item (Manage Project)' 'WAOV-W41')) }

  # Humanoid model: an FBX whose import settings say animationType 3 (Humanoid). The bone check reads that model's humanName list.
  $hum = $null
  foreach ($m in @(Get-ChildItem -Path (Join-Path $Project 'Assets') -Recurse -File -Include '*.fbx.meta' -ErrorAction SilentlyContinue)) {
    if (Select-String -Path $m.FullName -Pattern '^\s*animationType:\s*3\s*$' -Quiet) { $hum = $m; break }
  }
  if (-not $hum) { [void]$rows.Add((New-Row 'Humanoid avatar model' 'bad' 'none found, the avatar rig must be set to Humanoid' 'WAOV-E62')) }
  else {
    $hname = $hum.Name -replace '\.meta$', ''
    [void]$rows.Add((New-Row 'Humanoid avatar model' 'ok' $hname 'WAOV-I42'))
    if ($j -and $BoneRoles -contains [string]$j.bone) {
      if (Select-String -Path $hum.FullName -Pattern ("humanName:\s*" + $j.bone + "\s*$") -Quiet) {
        [void]$rows.Add((New-Row "Bone $($j.bone)" 'ok' 'found in the Humanoid map' 'WAOV-I42'))
      } else { [void]$rows.Add((New-Row "Bone $($j.bone)" 'bad' 'this avatar has no such bone mapped' 'WAOV-E63')) }
    }
  }
  if (Get-UnityExe) { [void]$rows.Add((New-Row "Unity $UnityVersion" 'ok' 'installed' 'WAOV-I12')) }
  else { [void]$rows.Add((New-Row "Unity $UnityVersion" 'bad' 'not installed, see slider 1' 'WAOV-E65')) }

  $bad = @($rows | Where-Object { $_.state -eq 'bad' }).Count
  if (-not $bad) { Write-Log 'WAOV-I42' "map check passed: $($j.name) -> $Project" }
  else { Write-Log ($rows | Where-Object { $_.state -eq 'bad' } | Select-Object -First 1).code "map check: $bad red rows for $Project" }
  return @($rows)
}

# ---------- APPROVE AND OPEN UNITY (only on the person's click) ----------
function Add-ToVcc([string]$Project) {
  if (-not (Test-Path $VccSettings)) { Write-Log 'WAOV-W40' 'VCC settings not found, project not added'; return 'VCC not found, add the project in VCC yourself' }
  if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*CreatorCompanion*' }) {
    Write-Log 'WAOV-W40' 'VCC is open, project not added'; return 'VCC is open: close it and click APPROVE again, or add the project in VCC'
  }
  $raw = Get-Content $VccSettings -Raw; $s = $raw | ConvertFrom-Json
  $list = @($s.userProjects | Where-Object { $_ })
  if ($list | Where-Object { ([string]$_).TrimEnd('\') -ieq $Project }) { Write-Log 'WAOV-I43' "already in VCC: $Project"; return 'already in VCC' }
  Copy-Item $VccSettings ($VccSettings + '.bak-waov') -Force
  $s.userProjects = @($list) + @($Project)
  ConvertTo-Json -InputObject $s -Depth 20 | Set-Content -Path $VccSettings -Encoding UTF8
  Write-Log 'WAOV-I43' "added to VCC: $Project (backup settings.json.bak-waov)"
  return 'added to VCC'
}
function Get-ItemPackage($Item) {
  $j = $Item.manifest
  $dest = Join-Path $ItemStage $j.name
  New-Item -ItemType Directory -Path $dest -Force | Out-Null
  $out = Join-Path $dest (Split-Path -Leaf $j.package)
  Use-ItemArchive $Item.zip {
    param($z)
    $e = $z.Entries | Where-Object { $_.Name -eq (Split-Path -Leaf $j.package) } | Select-Object -First 1
    if (-not $e) { throw "the item package $($j.package) is not in the zip" }
    $in = $e.Open(); $fs = [IO.File]::Create($out); try { $in.CopyTo($fs) } finally { $fs.Close(); $in.Close() }
  } | Out-Null
  return $out
}
function Open-MapInUnity([string]$Project, $Item) {
  $vcc = Add-ToVcc $Project
  $pkg = Get-ItemPackage $Item
  $exe = Get-UnityExe
  if (-not $exe) { Write-Log 'WAOV-E65' 'Unity 2022.3.22f1 not found'; throw "Unity $UnityVersion is not installed (slider 1)" }
  if ($NoLaunch) { Write-Log 'WAOV-I44' "test mode, Unity not started: $exe -projectPath $Project -importPackage $pkg"; return $vcc }
  Start-Process -FilePath $exe -ArgumentList @('-projectPath', ('"' + $Project + '"'), '-importPackage', ('"' + $pkg + '"'))
  Write-Log 'WAOV-I44' "Unity opened on $Project with $pkg"
  return $vcc
}

# The manual moments the menu shows after Unity opens (install.txt section 5b, step click boxes).
function Get-MapSteps($Item) {
  $j = $Item.manifest
  @(
    "1. WAIT   Unity opens your project and imports the item. The first open can take a few minutes.",
    "          PASS  the folder Assets\WAOV\Items\$($j.name) shows in the Project panel.",
    "2. DRAG   the prefab '$($j.title)' from that folder onto your avatar in the Hierarchy.",
    "          PASS  it sits under your avatar's name and shows on the $($j.bone) bone in the Scene view.",
    "3. CLICK  VRChat SDK (top menu), Show Control Panel, sign in with YOUR VRChat account, then Builder.",
    "          PASS  your avatar's name shows at the top of the Builder.",
    "4. CLICK  Build and Publish. This click is always yours (VRChat rule: no software uploads for you).",
    "          PASS  in VRChat, the '$($j.toggle)' toggle shows in your expression menu, next to GoGo Loco if you have it."
  )
}
