$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$private = 'C:\Users\siddh\.letscook\secrets'
$secureEnv = Join-Path $private 'native-google.env'
$credentialFile = Join-Path $private 'voice-test-credentials.json'

$adminLine = Get-Content -LiteralPath $secureEnv | Where-Object { $_ -match '^KEYCLOAK_ADMIN_PASSWORD=' } | Select-Object -Last 1
if (-not $adminLine) { throw 'Missing private Keycloak admin password.' }
$adminPassword = $adminLine.Substring('KEYCLOAK_ADMIN_PASSWORD='.Length).Trim('"', "'")

Push-Location $repo
try {
  & docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password $adminPassword *> $null
  if ($LASTEXITCODE -ne 0) { throw 'Keycloak admin login failed.' }
  $suffix = [Guid]::NewGuid().ToString('N').Substring(0, 8)
  $users = @()
  foreach ($role in @('host', 'guest')) {
    $username = "voice-$role-$suffix"
    $password = [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(24)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    & docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh create users -r xynk -s "username=$username" -s 'enabled=true' -s "firstName=Voice" -s "lastName=$role" -s "email=$username@example.invalid" -s 'emailVerified=true' *> $null
    if ($LASTEXITCODE -ne 0) { throw "Could not create $role user." }
    & docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh set-password -r xynk --username $username --new-password $password --temporary=false *> $null
    if ($LASTEXITCODE -ne 0) { throw "Could not set $role password." }
    $users += [pscustomobject]@{ role = $role; username = $username; password = $password }
  }
  $users | ConvertTo-Json | Set-Content -LiteralPath $credentialFile -Encoding utf8
  Write-Output "Created $($users.Count) temporary users in xynk; credentials stored privately."
} finally {
  Pop-Location
}
