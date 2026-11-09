<#
  ci-release.ps1  -  runs inside the GitHub Action (release.yml). Not for local use; locally run release-kit.ps1.
  1. Puts the signing key from the WAOV_SIGNING_KEY secret where release-kit.ps1 expects it.
  2. Runs release-kit.ps1 -Bump and turns each STEP line into a live row on the backdoor tile
     (build, sign, push, release, live), posted to waov.art and signed with the same key.
  3. Any failure posts a red row with the reason and a link to this run.
#>
$ErrorActionPreference = 'Stop'
$Api = 'https://waov.art/.netlify/functions/installer-control'
$JobId = $env:JOB_ID
$Rows = @('build', 'sign', 'push', 'release', 'live')
$Words = @{ build = 'building the exe and bat'; sign = 'signing'; push = 'syncing to GitHub'; release = 'publishing the release'; live = 'checking GitHub' }

if (-not $env:WAOV_SIGNING_KEY) { throw 'repo secret WAOV_SIGNING_KEY is missing' }
$keyDir = Join-Path $env:USERPROFILE '.waov-keys'
New-Item -ItemType Directory -Path $keyDir -Force | Out-Null
Set-Content -Path (Join-Path $keyDir 'waov-update.private.xml') -Value $env:WAOV_SIGNING_KEY -Encoding ASCII
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.FromXmlString($env:WAOV_SIGNING_KEY)

function Post([string]$Row, [string]$State, [string]$Field, [string]$Fail = '', [switch]$Done) {
  if (-not $JobId) { return }
  $p = [ordered]@{ jobId = $JobId; row = $Row; state = $State; field = $Field; ts = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) }
  if ($Fail) { $p.fail = $Fail; $p.restored = $false }
  if ($Done) { $p.done = $true }
  $payload = $p | ConvertTo-Json -Compress
  $sig = [Convert]::ToBase64String($rsa.SignData([Text.Encoding]::UTF8.GetBytes($payload), 'SHA256'))
  $body = @{ op = 'helper.progress'; payload = $payload; sig = $sig } | ConvertTo-Json -Compress
  try { Invoke-RestMethod -Uri $Api -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 20 | Out-Null } catch { Write-Host "progress post failed: $($_.Exception.Message)" }
}

git config user.name 'waov-release-bot'
git config user.email 'waov-release-bot@users.noreply.github.com'

$done = @()
Post 'build' 'run' $Words.build
try {
  $ErrorActionPreference = 'Continue'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'release-kit.ps1') -Bump -Notes $env:NOTES 2>&1 | ForEach-Object {
    $line = "$_"
    Write-Host $line
    if ($line -match '^STEP:(\w+)\s*(.*)$' -and $Rows -contains $Matches[1]) {
      $row = $Matches[1]; $field = $Matches[2]
      Post $row 'ok' $field
      $script:done += $row
      $i = $Rows.IndexOf($row)
      if ($i + 1 -lt $Rows.Count) { Post $Rows[$i + 1] 'run' $Words[$Rows[$i + 1]] }
    }
  }
  $code = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($code -ne 0 -or $done -notcontains 'live') { throw "release-kit stopped (exit $code)" }
  Post 'live' 'ok' 'LIVE' -Done
} catch {
  $failed = ($Rows | Where-Object { $done -notcontains $_ } | Select-Object -First 1)
  if (-not $failed) { $failed = 'live' }
  Post $failed 'fail' '' ("$($_.Exception.Message). Run log: $env:RUN_URL") -Done
  throw
}
