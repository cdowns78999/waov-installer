<#
  map-verify.ps1  -  slider 3 FAST CHECK (2026-11-14). Dot-sourced after map-avatar.ps1 (uses New-Row, Get-UnityExe, Write-Log).
  The three picks: AVATAR (project folder) -> BODY PART (body-parts.json) -> ITEM (an UNPACKED folder, i-install\unpack.txt).
  Every case returns a row: ok (green), warn (yellow, APPROVE still allowed), bad (red, APPROVE stays off).
  Codes: I45 fast check passed, I46 unity check passed, E67 item folder not unpacked, E68 item has no Bone Proxy prefab,
         E69 unity check failed (map-check.json says why). Older codes reused: W42, E62, E63, E64, E65.
  Reads only. Never writes into the avatar project.
#>

$BodyPartsFile = Join-Path $PSScriptRoot 'body-parts.json'
function Get-BodyParts {
  try { return @((Get-Content $BodyPartsFile -Raw | ConvertFrom-Json).parts) } catch { return @() }
}

# Items that finished UNPACK (unpacked.json present), from Documents\WAOV assets\WAOV items\{NAME}\
function Get-UnpackedItems {
  $root = Join-Path $AssetsRoot 'WAOV items'
  if (-not (Test-Path $root)) { return @() }
  $out = New-Object System.Collections.ArrayList
  foreach ($d in Get-ChildItem $root -Directory) {
    $u = Join-Path $d.FullName 'unpacked.json'
    if (-not (Test-Path $u)) { continue }
    try { $uj = Get-Content $u -Raw | ConvertFrom-Json } catch { continue }
    $ij = $null; $ip = Join-Path $d.FullName 'item.json'
    if (Test-Path $ip) { try { $ij = Get-Content $ip -Raw | ConvertFrom-Json } catch { } }
    [void]$out.Add([pscustomobject]@{ name = $d.Name; dir = $d.FullName; unpacked = $uj; item = $ij })
  }
  return @($out)
}

function Get-HumanoidMeta([string]$Project) {
  # The avatar's model: an .fbx.meta with animationType: 3 (Humanoid). Largest one wins if there are several.
  Get-ChildItem (Join-Path $Project 'Assets') -Recurse -Filter '*.fbx.meta' -ErrorAction SilentlyContinue |
    Where-Object { Select-String -LiteralPath $_.FullName -Pattern 'animationType:\s*3' -Quiet } |
    Sort-Object Length -Descending | Select-Object -First 1
}

# ---------- the fast check: one row per case ----------
function Test-MapPicks([string]$Project, $Part, $Item) {
  $rows = New-Object System.Collections.ArrayList
  $add = { param($l, $s, $n, $c) [void]$rows.Add((New-Row $l $s $n $c)) }

  # 1 AVATAR
  if (-not $Project -or -not (Test-Path -LiteralPath $Project)) { & $add 'Avatar project' 'bad' 'folder not found' 'WAOV-E62'; return @($rows) }
  if (-not (Test-AvatarFolder $Project)) { & $add 'Avatar project' 'bad' 'no VRChat Avatars SDK in Packages' 'WAOV-E62' } else { & $add 'Avatar project' 'ok' (Split-Path -Leaf $Project) 'WAOV-I42' }
  $verFile = Join-Path $Project 'ProjectSettings\ProjectVersion.txt'
  $ver = if (Test-Path $verFile) { ((Get-Content $verFile | Select-String 'm_EditorVersion:') -replace '.*:\s*', '') } else { 'unknown' }
  if ($ver -like '2022.3*') { & $add 'Unity version' 'ok' $ver 'WAOV-I42' } else { & $add 'Unity version' 'bad' "$ver, VRChat needs 2022.3" 'WAOV-W42' }
  $man = Join-Path $Project 'Packages\vpm-manifest.json'
  if ((Test-Path $man) -and ((Get-Content $man -Raw) -match 'nadena\.dev\.modular-avatar')) { & $add 'Modular Avatar' 'ok' 'installed' 'WAOV-I42' }
  else { & $add 'Modular Avatar' 'bad' 'not in the project (add it in VCC)' 'WAOV-E62' }
  $meta = Get-HumanoidMeta $Project
  if (-not $meta) { & $add 'Humanoid model' 'bad' 'no Humanoid rig found' 'WAOV-E62' } else { & $add 'Humanoid model' 'ok' $meta.Name.Replace('.meta', '') 'WAOV-I42' }

  # 2 BODY PART
  if (-not $Part -or -not $Part.role) { & $add 'Body part' 'bad' 'pick a body part' 'WAOV-E64' }
  elseif ($BoneRoles -notcontains [string]$Part.role) { & $add 'Body part' 'bad' "unknown role $($Part.role)" 'WAOV-E64' }
  elseif ($meta) {
    $map = Select-String -LiteralPath $meta.FullName -Pattern 'humanName:\s*(\w+)' -AllMatches | ForEach-Object { $_.Matches.Groups[1].Value }
    $role = [string]$Part.role
    if (-not $map) {
      # Auto-mapped rig: the .meta lists nothing. Required bones are safe, optional ones need the Unity check.
      if ($RequiredBones -contains $role) { & $add "Body part ($role)" 'ok' 'a required Humanoid bone' 'WAOV-I42' }
      else { & $add "Body part ($role)" 'warn' 'optional bone, the Unity check confirms it' 'WAOV-W42' }
    } elseif ($map -contains $role) { & $add "Body part ($role)" 'ok' 'found in the Humanoid map' 'WAOV-I42' }
    elseif ($Part.fallback -and ($map -contains [string]$Part.fallback)) { & $add "Body part ($role)" 'warn' "not mapped, will use $($Part.fallback)" 'WAOV-W42' }
    else { & $add "Body part ($role)" 'bad' 'this avatar has no such bone mapped' 'WAOV-E63' }
  }

  # 3 ITEM
  if (-not $Item) { & $add 'Item' 'bad' 'pick an item' 'WAOV-E67'; return @($rows) }
  if (-not (Test-Path (Join-Path $Item.dir 'unpacked.json'))) { & $add 'Item' 'bad' 'not unpacked yet (UNPACK on slider 2)' 'WAOV-E67'; return @($rows) }
  $zip = Join-Path $Item.dir ($Item.name + '.zip')
  if ((Test-Path $zip) -and $Item.unpacked.sha256) {
    $h = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    if ($h -eq [string]$Item.unpacked.sha256) { & $add 'Item file check' 'ok' 'hash matches' 'WAOV-I55' } else { & $add 'Item file check' 'bad' 'zip changed since download' 'WAOV-E71' }
  } else { & $add 'Item file check' 'warn' 'no zip kept to re-check' 'WAOV-W42' }
  $pkg = Get-ChildItem (Join-Path $Item.dir 'asset') -Recurse -Filter '*.unitypackage' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($pkg) { & $add 'Item package' 'ok' $pkg.Name 'WAOV-I41' } else { & $add 'Item package' 'bad' 'no .unitypackage inside' 'WAOV-E67' }
  if ($Item.item -and $Item.item.prefab) { & $add 'Item prefab' 'ok' ([string]$Item.item.prefab) 'WAOV-I41' }
  else { & $add 'Item prefab' 'bad' 'item.json names no prefab with a Bone Proxy' 'WAOV-E68' }
  if ($Item.item -and $Item.item.bone -and $Part -and ([string]$Item.item.bone -ne [string]$Part.role)) {
    & $add 'Body part vs item' 'warn' "made for $($Item.item.bone), you picked $($Part.role)" 'WAOV-W42'
  }

  # 4 UNITY present for the deep check
  if (Get-UnityExe) { & $add 'Unity 2022.3 installed' 'ok' 'ready for the Unity check' 'WAOV-I42' } else { & $add 'Unity 2022.3 installed' 'bad' 'install it on slider 1' 'WAOV-E65' }

  if (-not ($rows | Where-Object { $_.state -eq 'bad' })) { Write-Log 'WAOV-I45' "fast check passed: $(Split-Path -Leaf $Project) / $($Part.role) / $($Item.name)" }
  return @($rows)
}

# ---------- APPROVE for an unpacked item (no zip re-read: the package is already in asset\) ----------
function Open-UnpackedInUnity([string]$Project, $Item) {
  $vcc = Add-ToVcc $Project
  $pkg = Get-ChildItem (Join-Path $Item.dir 'asset') -Recurse -Filter '*.unitypackage' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $pkg) { throw 'the item has no .unitypackage (WAOV-E67)' }
  $exe = Get-UnityExe
  if (-not $exe) { Write-Log 'WAOV-E65' 'Unity 2022.3 not found'; throw "Unity $UnityVersion is not installed (slider 1)" }
  if ($NoLaunch) { Write-Log 'WAOV-I44' "test mode, Unity not started: $exe -projectPath $Project -importPackage $($pkg.FullName)"; return $vcc }
  Start-Process -FilePath $exe -ArgumentList @('-projectPath', ('"' + $Project + '"'), '-importPackage', ('"' + $pkg.FullName + '"'))
  Write-Log 'WAOV-I44' "Unity opened on $Project with $($pkg.Name)"
  return $vcc
}
function Get-UnpackedSteps($Item, $Part) {
  $title = if ($Item.item -and $Item.item.title) { $Item.item.title } else { $Item.name }
  @(
    "1. WAIT   Unity opens your project and imports $title. The first open can take a few minutes.",
    "2. DRAG   the prefab $title onto your avatar in the Hierarchy.",
    "          PASS  it shows on your $($Part.label) ($($Part.role)) in the Scene view, as the Unity check proved.",
    "3. CLICK  VRChat SDK, Show Control Panel, sign in with YOUR VRChat account, then Builder.",
    "4. CLICK  Build and Publish. This click is always yours (VRChat rule)."
  )
}
