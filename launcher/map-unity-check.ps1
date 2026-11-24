<#
  map-unity-check.ps1  -  slider 3 UNITY CHECK runner (2026-11-14). Dot-sourced after map-verify.ps1.
  Makes a throwaway copy of the avatar project (Assets, Packages, ProjectSettings only), drops WAOVMapCheck.cs into it,
  runs Unity 2022.3 in batch mode, reads map-check.json, and deletes the copy. The real project is never opened or changed.
  Cases covered: Unity missing (E65), copy failed, Unity timed out (15 min), Unity crashed / no json, any red row (E69), pass (I46).
#>

function Invoke-UnityMapCheck([string]$Project, $Part, $Item, [int]$TimeoutMin = 15) {
  $fail = { param($n) @{ pass = $false; rows = @((New-Row 'Unity check' 'bad' $n 'WAOV-E69')) } }
  $exe = Get-UnityExe
  if (-not $exe) { Write-Log 'WAOV-E65' 'unity check: Unity 2022.3 not installed'; return (& $fail 'Unity 2022.3 is not installed (slider 1)') }

  $pkg = Get-ChildItem (Join-Path $Item.dir 'asset') -Recurse -Filter '*.unitypackage' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $pkg) { return (& $fail 'the item has no .unitypackage') }
  $prefab = [string]$Item.item.prefab
  if (-not $prefab) { return (& $fail 'item.json names no prefab') }

  $tmp = Join-Path $env:TEMP ('waov-mapcheck-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  $out = Join-Path $tmp 'map-check.json'
  try {
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    foreach ($d in 'Assets', 'Packages', 'ProjectSettings') {
      $src = Join-Path $Project $d
      if (Test-Path $src) { robocopy $src (Join-Path $tmp $d) /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null; if ($LASTEXITCODE -ge 8) { throw "copy of $d failed" } }
    }
    $ed = Join-Path $tmp 'Assets\WAOV\Editor'; New-Item -ItemType Directory -Path $ed -Force | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'unity\WAOVMapCheck.cs') $ed

    $off = (@($Part.offset) -join ',')
    $uargs = @('-batchmode', '-nographics', '-quit', '-projectPath', "`"$tmp`"", '-executeMethod', 'WAOVMapCheck.Run',
              '-waovPackage', "`"$($pkg.FullName)`"", '-waovPrefab', "`"$prefab`"", '-waovRole', [string]$Part.role,
              '-waovFallback', "`"$([string]$Part.fallback)`"", '-waovOffset', "`"$off`"", '-waovOut', "`"$out`"",
              '-logFile', "`"$(Join-Path $tmp 'unity.log')`"")
    Write-Log 'WAOV-I46' "unity check started on a temp copy: $tmp"
    $proc = Start-Process -FilePath $exe -ArgumentList $uargs -PassThru -WindowStyle Hidden
    if (-not $proc.WaitForExit($TimeoutMin * 60000)) { try { $proc.Kill() } catch { }; return (& $fail "Unity took longer than $TimeoutMin minutes") }

    if (-not (Test-Path $out)) {
      $tail = if (Test-Path (Join-Path $tmp 'unity.log')) { (Get-Content (Join-Path $tmp 'unity.log') -Tail 3) -join ' ' } else { 'no log' }
      Write-Log 'WAOV-E69' "unity check wrote no result: $tail"
      return (& $fail "Unity stopped without a result (exit $($proc.ExitCode))")
    }
    $res = Get-Content $out -Raw | ConvertFrom-Json
    $rows = @($res.rows | ForEach-Object { New-Row $_.label $_.state $_.note $(if ($_.state -eq 'bad') { 'WAOV-E69' } else { 'WAOV-I46' }) })
    if ($res.pass) { Write-Log 'WAOV-I46' "unity check passed: $($Part.role) / $($Item.name)" } else { Write-Log 'WAOV-E69' 'unity check found a red row' }
    return @{ pass = [bool]$res.pass; rows = $rows }
  } catch {
    Write-Log 'WAOV-E69' "unity check error: $($_.Exception.Message)"
    return (& $fail $_.Exception.Message)
  } finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

# The whole gate slider 3 calls before APPROVE: fast check first, Unity check only if the fast one has no red row.
function Test-MapAll([string]$Project, $Part, $Item) {
  $fast = @(Test-MapPicks $Project $Part $Item)
  if ($fast | Where-Object { $_.state -eq 'bad' }) { return @{ pass = $false; rows = $fast; stage = 'fast' } }
  $deep = Invoke-UnityMapCheck $Project $Part $Item
  return @{ pass = [bool]$deep.pass; rows = @($fast + $deep.rows); stage = 'unity' }
}


# ---------- BACKGROUND mode (2026-11-14): Unity runs hidden, the window keeps working ----------
# Start-UnityMapCheck returns a job object at once; the menu polls Read-UnityMapCheck every second.
function Start-UnityMapCheck([string]$Project, $Part, $Item) {
  $exe = Get-UnityExe
  if (-not $exe) { return @{ done = $true; result = @{ pass = $false; rows = @((New-Row 'Unity check' 'bad' 'Unity 2022.3 is not installed (slider 1)' 'WAOV-E65')) } } }
  $pkg = Get-ChildItem (Join-Path $Item.dir 'asset') -Recurse -Filter '*.unitypackage' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $pkg -or -not $Item.item.prefab) { return @{ done = $true; result = @{ pass = $false; rows = @((New-Row 'Unity check' 'bad' 'item has no package or prefab' 'WAOV-E67')) } } }
  $tmp = Join-Path $env:TEMP ('waov-mapcheck-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Path $tmp -Force | Out-Null
  $out = Join-Path $tmp 'map-check.json'; $log = Join-Path $tmp 'unity.log'
  # The copy itself also runs in the background: one hidden PowerShell does robocopy, then starts Unity and waits.
  $off = (@($Part.offset) -join ',')
  # every value lands inside single quotes in the helper script, so a ' in a path is doubled (PowerShell escape)
  $q = { param($v) ([string]$v).Replace("'", "''") }
  $Project = & $q $Project; $tmpQ = & $q $tmp; $outQ = & $q $out; $logQ = & $q $log; $exeQ = & $q $exe
  $pkgQ = & $q $pkg.FullName; $preQ = & $q $Item.item.prefab; $rootQ = & $q $PSScriptRoot
  $runText = @"
`$ErrorActionPreference = 'Stop'
foreach (`$d in 'Assets','Packages','ProjectSettings') { if (Test-Path '$Project\`$d') { robocopy '$Project\`$d' '$tmpQ\`$d' /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null } }
New-Item -ItemType Directory -Path '$tmpQ\Assets\WAOV\Editor' -Force | Out-Null
Copy-Item '$rootQ\unity\WAOVMapCheck.cs' '$tmpQ\Assets\WAOV\Editor'
Set-Content '$tmpQ\stage.txt' 'unity'
& '$exeQ' -batchmode -nographics -quit -projectPath '$tmpQ' -executeMethod WAOVMapCheck.Run -waovPackage '$pkgQ' -waovPrefab '$preQ' -waovRole '$($Part.role)' -waovFallback '$($Part.fallback)' -waovOffset '$off' -waovOut '$outQ' -logFile '$logQ' | Out-Null
Set-Content '$tmpQ\stage.txt' 'done'
"@
  $runner = Join-Path $tmp 'run.ps1'; Set-Content -Path $runner -Value $runText -Encoding UTF8
  Set-Content (Join-Path $tmp 'stage.txt') 'copy'
  $proc = Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$runner`"") -WindowStyle Hidden -PassThru
  Write-Log 'WAOV-I46' "unity check started in the background: $tmp"
  return @{ done = $false; tmp = $tmp; out = $out; log = $log; proc = $proc; started = Get-Date }
}

# Returns @{ done; stage; result } . stage is copy | unity | done. Cleans the temp copy when finished.
function Read-UnityMapCheck($Job, [int]$TimeoutMin = 15) {
  if ($Job.done) { return $Job }
  $stage = 'copy'; $sf = Join-Path $Job.tmp 'stage.txt'; if (Test-Path $sf) { $stage = (Get-Content $sf -Raw).Trim() }
  $elapsed = ((Get-Date) - $Job.started).TotalMinutes
  if (-not $Job.proc.HasExited -and $elapsed -lt $TimeoutMin) { return @{ done = $false; stage = $stage; minutes = [math]::Round($elapsed, 1) } }
  if (-not $Job.proc.HasExited) {
    try { Get-Process Unity -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$($Job.tmp)*" } | Stop-Process -Force } catch { }
    try { $Job.proc.Kill() } catch { }
    $res = @{ pass = $false; rows = @((New-Row 'Unity check' 'bad' "took longer than $TimeoutMin minutes" 'WAOV-E69')) }
  } elseif (Test-Path $Job.out) {
    $j = Get-Content $Job.out -Raw | ConvertFrom-Json
    $res = @{ pass = [bool]$j.pass; rows = @($j.rows | ForEach-Object { New-Row $_.label $_.state $_.note $(if ($_.state -eq 'bad') { 'WAOV-E69' } else { 'WAOV-I46' }) }) }
  } else {
    $tail = if (Test-Path $Job.log) { (Get-Content $Job.log -Tail 2) -join ' ' } else { 'no log' }
    Write-Log 'WAOV-E69' "unity check wrote no result: $tail"
    $res = @{ pass = $false; rows = @((New-Row 'Unity check' 'bad' 'Unity stopped without a result' 'WAOV-E69')) }
  }
  if ($res.pass) { Write-Log 'WAOV-I46' 'unity check passed (background)' } else { Write-Log 'WAOV-E69' 'unity check failed (background)' }
  Remove-Item $Job.tmp -Recurse -Force -ErrorAction SilentlyContinue
  return @{ done = $true; stage = 'done'; result = $res }
}
