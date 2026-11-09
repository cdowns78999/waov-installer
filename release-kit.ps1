<#
  release-kit.ps1  -  publishes a new WAOV kit version (2026-11-09). Run on Chad's PC only.
    powershell -NoProfile -ExecutionPolicy Bypass -File release-kit.ps1 -Bump -Notes "what changed"
    -Bump        1.0 -> 1.1 -> 1.2 (minor + 1)        -Version 2.0   set it exactly (must be higher)
    -DryRun      build, zip, sign and write dist\ only; no git, no GitHub release
  Steps: version up in launcher\Miles Installer and Updater.ps1 -> build-kit.ps1 (exe + bat) -> dist\waov-kit-{v}.zip
         -> SHA-256 + RSA signature (private key in %USERPROFILE%\.waov-keys, never uploaded) -> dist\latest.json
         -> git commit + push -> gh release create v{v} (zip + latest.json, marked latest) -> read latest.json back from GitHub.
  Every installer that opens after this reads that latest.json and updates itself.
  Last line printed is one JSON object, read by helper.py.
#>
param([switch]$Bump, [string]$Version = '', [switch]$DryRun, [string]$Notes = 'kit update')
$ErrorActionPreference = 'Stop'
$R = $PSScriptRoot
$Repo = 'cdowns78999/waov-installer'
$src = Join-Path $R 'launcher\Miles Installer and Updater.ps1'
$priv = Join-Path $env:USERPROFILE '.waov-keys\waov-update.private.xml'
if (-not (Test-Path $priv)) { throw "private key missing at $priv (run make-keys.ps1 once)" }
if (-not (Test-Path (Join-Path $R 'launcher\waov-update.pub.xml'))) { throw 'public key missing in launcher\' }

$text = Get-Content $src -Raw
$m = [regex]::Match($text, "(?m)^\`$KitVersion = '([\d\.]+)'")
if (-not $m.Success) { throw 'KitVersion line not found' }
$cur = [version]$m.Groups[1].Value
if ($Version) { $new = [version]$Version }
elseif ($Bump) { $new = [version]::new($cur.Major, $cur.Minor + 1) }
else { $new = $cur }

$released = $null
if (-not $DryRun) {
  $tag = (gh release list --repo $Repo --limit 1 --json tagName --jq '.[0].tagName' 2>$null)
  if ($tag) { $released = [version]($tag.TrimStart('v')) }
  if ($released -and $new -le $released) { throw "version $new is not higher than the released $released (use -Bump)" }
}
if ($new -ne $cur) {
  $text = $text.Substring(0, $m.Groups[1].Index) + $new.ToString() + $text.Substring($m.Groups[1].Index + $m.Groups[1].Length)
  [IO.File]::WriteAllText($src, $text, (New-Object Text.UTF8Encoding($true)))
}
$v = $new.ToString()

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $R 'build-kit.ps1') | Out-Null
if ($LASTEXITCODE) { throw 'build-kit.ps1 failed' }

$dist = Join-Path $R 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$zipName = "waov-kit-$v.zip"
$zip = Join-Path $dist $zipName
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $R 'launcher\*') -DestinationPath $zip
$sha = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.FromXmlString((Get-Content $priv -Raw))
$sig = [Convert]::ToBase64String($rsa.SignData([IO.File]::ReadAllBytes($zip), 'SHA256'))
$latest = [ordered]@{
  version = $v; file = $zipName
  url = "https://github.com/$Repo/releases/download/v$v/$zipName"
  sha256 = $sha; sig = $sig; notes = $Notes; published = (Get-Date -Format 'yyyy-MM-dd HH:mm')
}
$latestPath = Join-Path $dist 'latest.json'
$latest | ConvertTo-Json | Set-Content $latestPath -Encoding ASCII

$live = ''
if (-not $DryRun) {
  git -C $R add -A
  git -C $R commit -m "kit v${v}: $Notes" | Out-Null
  git -C $R push origin HEAD 2>&1 | Out-Null
  if ($LASTEXITCODE) { throw 'git push failed' }
  gh release create "v$v" $zip $latestPath --repo $Repo --title "Kit v$v" --notes $Notes --latest | Out-Null
  if ($LASTEXITCODE) { throw 'gh release create failed' }
  for ($i = 0; $i -lt 6 -and $live -ne $v; $i++) {
    Start-Sleep -Seconds 3
    try { $live = (Invoke-RestMethod "https://github.com/$Repo/releases/latest/download/latest.json" -TimeoutSec 15).version } catch { }
  }
}
[ordered]@{ ok = $true; version = $v; previous = $cur.ToString(); zip = $zip; sha256 = $sha; dryRun = [bool]$DryRun; liveVersion = $live } | ConvertTo-Json -Compress
