<#
  make-keys.ps1  -  one time: makes the WAOV update signing key pair (2026-11-09).
  Private key: %USERPROFILE%\.waov-keys\waov-update.private.xml   (Chad's PC only, never in any repo, never uploaded)
  Public key:  launcher\waov-update.pub.xml                       (ships in every kit, used to verify updates)
  Refuses to overwrite an existing private key: losing it means old installers can no longer verify new releases.
#>
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:USERPROFILE '.waov-keys'
$priv = Join-Path $dir 'waov-update.private.xml'
if (Test-Path $priv) { throw "a private key already exists at $priv; not overwriting it" }
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider(3072)
$rsa.PersistKeyInCsp = $false
Set-Content -Path $priv -Value $rsa.ToXmlString($true) -Encoding ASCII
Set-Content -Path (Join-Path $PSScriptRoot 'launcher\waov-update.pub.xml') -Value $rsa.ToXmlString($false) -Encoding ASCII
"private key -> $priv"
"public key  -> launcher\waov-update.pub.xml"
