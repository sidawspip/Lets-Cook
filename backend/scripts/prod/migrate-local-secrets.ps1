param(
    [string]$SecureEnvironmentFile = $(if ($env:LETSCOOK_SECURE_ENV) { $env:LETSCOOK_SECURE_ENV } else { Join-Path $env:USERPROFILE '.letscook\secrets\native-google.env' })
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$envPath = Join-Path $projectRoot '.env'
if (-not (Test-Path -LiteralPath $envPath)) { throw 'Project .env was not found.' }
if (-not (Test-Path -LiteralPath $SecureEnvironmentFile)) { throw 'Private secrets file was not found.' }

$projectLines = @(Get-Content -LiteralPath $envPath)
$secureLines = [Collections.Generic.List[string]]::new()
foreach ($line in (Get-Content -LiteralPath $SecureEnvironmentFile)) { $secureLines.Add($line) }
$projectValues = @{}
foreach ($line in $projectLines) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') { $projectValues[$Matches[1]] = $Matches[2].Trim() }
}
$secureValues = @{}
foreach ($line in $secureLines) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') { $secureValues[$Matches[1]] = $Matches[2].Trim() }
}
function Set-PrivateValue([string]$name, [string]$value) {
    if (-not $value) { throw "Missing required local credential: $name" }
    for ($i = 0; $i -lt $secureLines.Count; $i++) {
        if ($secureLines[$i] -match "^\s*$([regex]::Escape($name))\s*=") {
            $secureLines[$i] = "$name=$value"
            $secureValues[$name] = $value
            return
        }
    }
    $secureLines.Add("$name=$value")
    $secureValues[$name] = $value
}

$dbPassword = if ($secureValues.POSTGRES_PASSWORD) { $secureValues.POSTGRES_PASSWORD } else { $projectValues.POSTGRES_PASSWORD }
$adminPassword = if ($secureValues.KEYCLOAK_ADMIN_PASSWORD) { $secureValues.KEYCLOAK_ADMIN_PASSWORD } else { $projectValues.KEYCLOAK_ADMIN_PASSWORD }
$liveKitKey = if ($secureValues.LIVEKIT_API_KEY) { $secureValues.LIVEKIT_API_KEY } else { $projectValues.LIVEKIT_API_KEY }
$liveKitSecret = if ($secureValues.LIVEKIT_API_SECRET) { $secureValues.LIVEKIT_API_SECRET } else { $projectValues.LIVEKIT_API_SECRET }
Set-PrivateValue 'POSTGRES_PASSWORD' $dbPassword
Set-PrivateValue 'SPRING_DATASOURCE_PASSWORD' $dbPassword
Set-PrivateValue 'KC_DB_PASSWORD' $dbPassword
Set-PrivateValue 'KEYCLOAK_ADMIN_PASSWORD' $adminPassword
Set-PrivateValue 'KC_BOOTSTRAP_ADMIN_PASSWORD' $adminPassword
Set-PrivateValue 'LIVEKIT_API_KEY' $liveKitKey
Set-PrivateValue 'LIVEKIT_API_SECRET' $liveKitSecret
Set-PrivateValue 'LIVEKIT_SELF_HOSTED_API_KEY' $liveKitKey
Set-PrivateValue 'LIVEKIT_SELF_HOSTED_API_SECRET' $liveKitSecret
Set-PrivateValue 'LIVEKIT_KEYS' "${liveKitKey}: $liveKitSecret"

Set-Content -LiteralPath $SecureEnvironmentFile -Value $secureLines -Encoding utf8NoBOM
$principal = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $SecureEnvironmentFile /inheritance:r /grant:r "${principal}:F" | Out-Null

$remove = @('POSTGRES_PASSWORD','KEYCLOAK_ADMIN_PASSWORD','LIVEKIT_API_KEY','LIVEKIT_API_SECRET','LIVEKIT_SELF_HOSTED_API_KEY','LIVEKIT_SELF_HOSTED_API_SECRET')
$cleanLines = @($projectLines | Where-Object {
    $line = $_
    -not ($remove | Where-Object { $line -match "^\s*$([regex]::Escape($_))\s*=" })
})
Set-Content -LiteralPath $envPath -Value $cleanLines -Encoding utf8NoBOM
Write-Output 'Local database, Keycloak, and self-hosted LiveKit credentials moved to the protected user secrets file.'
