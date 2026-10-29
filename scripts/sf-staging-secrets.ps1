<#
.SYNOPSIS
ShuttleForge staging secret values, operator-run. Overcast creates the shells only (INV-004);
this script writes their values without printing them or leaving them on disk.

.DESCRIPTION
  -Phase Prepare     G2, before `dbbootstrap sf-app-role`:
                     db-url-migration  = the schema-owner URL, taken from the current db-url
                                         (the owner password exists nowhere else; the July
                                         bootstrap temporary was spent), as postgresql+asyncpg://
                     dbbootstrap/shuttleforge-app-db-password = 64 random hex characters
  -Phase RuntimeUrl  G2, after sf-app-role has created shuttleforge_app_<env>:
                     db-url = the runtime URL for shuttleforge_app_<env> (AWSPREVIOUS keeps the
                     old owner URL)
  -Phase SfValues    Before G4: kek-ring-b64, listener-auth-hmac-key, lease-hmac-key,
                     operator-token

Every phase refuses to overwrite a secret that already holds a value, except RuntimeUrl, which
replaces db-url only while it still names the owner role.

Formats follow ShuttleForge at ad2668b: the KEK ring is standard base64 of
{"current":"v1","v1":"<base64 of 32 random bytes>"} (shuttleforge/models/secrets.py); the HMAC
keys are padded base64 of 32 random bytes and must differ (main.py); the operator token matches
^[A-Za-z0-9._~-]{16,}$ (auth/operator.py). Keep every KEK version: a database backup cannot be
decrypted without the ring that wrote it.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\sf-staging-secrets.ps1 -Phase Prepare
#>
param(
  [Parameter(Mandatory = $true)] [ValidateSet('Prepare', 'RuntimeUrl', 'SfValues')] [string] $Phase,
  [string] $Environment = 'staging'
)
$ErrorActionPreference = 'Stop'
$aws = 'C:\Program Files\Amazon\AWSCLIV2\aws.exe'
$region = 'us-east-1'
$db = "shuttleforge_$Environment"
$owner = $db
$app = "shuttleforge_app_$Environment"
$id = @{
  DbUrl          = "arclight/$Environment/shuttleforge/db-url"
  DbUrlMigration = "arclight/$Environment/shuttleforge/db-url-migration"
  AppPw          = "arclight/$Environment/dbbootstrap/shuttleforge-app-db-password"
  Kek            = "arclight/$Environment/shuttleforge/kek-ring-b64"
  ListenerHmac   = "arclight/$Environment/shuttleforge/listener-auth-hmac-key"
  LeaseHmac      = "arclight/$Environment/shuttleforge/lease-hmac-key"
  OperatorToken  = "arclight/$Environment/shuttleforge/operator-token"
}

function Get-RandomBytes([int] $n) {
  $b = New-Object byte[] $n
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  $rng.GetBytes($b)
  $rng.Dispose()
  return , $b
}

function ConvertTo-Hex([byte[]] $b) { -join ($b | ForEach-Object { $_.ToString('x2') }) }

function Get-VersionCount([string] $secretId) {
  $raw = & $aws secretsmanager describe-secret --region $region --secret-id $secretId --output json
  if ($LASTEXITCODE -ne 0) { throw "could not describe $secretId" }
  $j = ($raw -join "`n") | ConvertFrom-Json
  if ($null -eq $j.VersionIdsToStages) { return 0 }
  return @($j.VersionIdsToStages.PSObject.Properties).Count
}

function Assert-Empty([string] $secretId) {
  if ((Get-VersionCount $secretId) -ne 0) { throw "$secretId already holds a value; refusing to overwrite" }
}

function Read-Secret([string] $secretId) {
  $v = & $aws secretsmanager get-secret-value --region $region --secret-id $secretId --query SecretString --output text
  if ($LASTEXITCODE -ne 0) { throw "could not read $secretId" }
  return ($v -join '').Trim()
}

function Write-Secret([string] $secretId, [string] $value) {
  # Through a short-lived file in the user's temp folder, never the command line.
  $tmp = [System.IO.Path]::GetTempFileName()
  try {
    [System.IO.File]::WriteAllText($tmp, $value, (New-Object System.Text.UTF8Encoding $false))
    $vid = & $aws secretsmanager put-secret-value --region $region --secret-id $secretId --secret-string "file://$tmp" --query VersionId --output text
    if ($LASTEXITCODE -ne 0) { throw "could not write $secretId" }
  }
  finally { Remove-Item -Force $tmp }
  Write-Host "wrote $secretId (version $vid)"
}

function Split-PgUrl([string] $url) {
  $m = [regex]::Match($url, '^postgres(?:ql)?(?:\+asyncpg)?://([^:@/]+):(.+)@([^@:/?]+)(?::(\d+))?/([^?/]+)')
  if (-not $m.Success) { throw 'not a postgres URL with user, password, host and database' }
  $port = '5432'
  if ($m.Groups[4].Success) { $port = $m.Groups[4].Value }
  return @{ User = $m.Groups[1].Value; Host = $m.Groups[3].Value; Port = $port; Db = $m.Groups[5].Value }
}

switch ($Phase) {
  'Prepare' {
    Assert-Empty $id.DbUrlMigration
    Assert-Empty $id.AppPw
    $cur = Read-Secret $id.DbUrl
    $p = Split-PgUrl $cur
    if ($p.User -ne $owner -or $p.Db -ne $db) {
      throw "db-url names $($p.User) on $($p.Db), not $owner on $db; has it already been rewritten?"
    }
    $mig = ($cur -replace '^postgres(?:ql)?(?:\+asyncpg)?://', 'postgresql+asyncpg://') -replace '\?.*$', ''
    Write-Secret $id.DbUrlMigration $mig
    Write-Secret $id.AppPw (ConvertTo-Hex (Get-RandomBytes 32))
    Write-Host "Prepare done: owner URL for $owner@$($p.Host):$($p.Port)/$db. Next: run dbbootstrap sf-app-role, then -Phase RuntimeUrl."
  }
  'RuntimeUrl' {
    $p = Split-PgUrl (Read-Secret $id.DbUrlMigration)
    if ($p.User -ne $owner -or $p.Db -ne $db) { throw "db-url-migration does not name $owner on $db" }
    $cur = Split-PgUrl (Read-Secret $id.DbUrl)
    if ($cur.User -ne $owner) { throw "db-url already names $($cur.User); nothing to do" }
    $appPw = Read-Secret $id.AppPw
    if ($appPw -notmatch '^[0-9a-f]{64}$') { throw 'the app password is not the 64-hex value Prepare wrote' }
    Write-Secret $id.DbUrl ("postgresql+asyncpg://{0}:{1}@{2}:{3}/{4}" -f $app, $appPw, $p.Host, $p.Port, $db)
    Write-Host "RuntimeUrl done: db-url now names $app."
  }
  'SfValues' {
    foreach ($k in 'Kek', 'ListenerHmac', 'LeaseHmac', 'OperatorToken') { Assert-Empty $id[$k] }
    $ringJson = '{"current":"v1","v1":"' + [Convert]::ToBase64String((Get-RandomBytes 32)) + '"}'
    Write-Secret $id.Kek ([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ringJson)))
    $listener = [Convert]::ToBase64String((Get-RandomBytes 32))
    do { $lease = [Convert]::ToBase64String((Get-RandomBytes 32)) } while ($lease -eq $listener)
    Write-Secret $id.ListenerHmac $listener
    Write-Secret $id.LeaseHmac $lease
    Write-Secret $id.OperatorToken (ConvertTo-Hex (Get-RandomBytes 32))
    Write-Host 'SfValues done. Never delete or overwrite kek-ring-b64: backups need every KEK version.'
  }
}
