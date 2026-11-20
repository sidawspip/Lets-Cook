param(
    [string]$KeycloakAdmin = 'admin',
    [string]$KeycloakPassword = 'admin',
    [string[]]$AllowedMail = @(),
    [switch]$RequireGlobalMedia,
    [switch]$SelfHostedInternetMedia,
    [ValidateRange(0, 8)]
    [int]$OpenIncognitoSessions = 0,
    [ValidateSet('Chrome', 'Edge')]
    [string]$TestBrowser = 'Chrome'
)

$ErrorActionPreference = 'Stop'
$containerName = 'xynk-cloudflare-uat'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$composeFiles = if ($env:COMPOSE_FILE) {
    @($env:COMPOSE_FILE -split ';' | Where-Object { $_ } | ForEach-Object {
        if ([IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $projectRoot $_ }
    })
} else {
    @((Join-Path $projectRoot 'compose.yaml'))
}
$composeArgs = @('--project-directory', $projectRoot)
foreach ($composeFile in $composeFiles) { $composeArgs += @('-f', $composeFile) }
function Invoke-ProjectCompose { & docker compose @composeArgs @args }

function Get-ConfiguredMedia {
    $composeConfig = Invoke-ProjectCompose config --format json 2>$null | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose configuration is invalid.' }
    $backendEnvironment = ($composeConfig | ConvertFrom-Json).services.backend.environment
    $mode = [string]$backendEnvironment.LIVEKIT_MODE
    $cloud = $mode -eq 'cloud'

    [pscustomobject]@{
        Mode = $mode
        Url = if ($cloud) { [string]$backendEnvironment.LIVEKIT_CLOUD_URL } else { [string]$backendEnvironment.LIVEKIT_SELF_HOSTED_URL }
        Key = if ($cloud) { [string]$backendEnvironment.LIVEKIT_CLOUD_API_KEY } else { [string]$backendEnvironment.LIVEKIT_SELF_HOSTED_API_KEY }
        Secret = if ($cloud) { [string]$backendEnvironment.LIVEKIT_CLOUD_API_SECRET } else { [string]$backendEnvironment.LIVEKIT_SELF_HOSTED_API_SECRET }
    }
}

$configuredMedia = Get-ConfiguredMedia
$globalMediaReady =
    $configuredMedia.Mode -in @('cloud', 'self-hosted', 'router') -and
    $configuredMedia.Url -match '^wss://[^/]+(?:/.*)?$' -and
    $configuredMedia.Url -notmatch '(?i)(localhost|127\.0\.0\.1|192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)' -and
    $configuredMedia.Key -and $configuredMedia.Key -ne 'devkey' -and
    $configuredMedia.Secret -and $configuredMedia.Secret -ne 'lets-cook-dev-livekit-secret-32-chars'

if ($RequireGlobalMedia -and -not $globalMediaReady) {
    throw @'
Global media needs a public wss:// URL and non-development credentials.
Configure LiveKit Cloud or a public self-hosted endpoint, then run:
  .\infra\scripts\dev\start-global-uat.ps1
'@
}

Write-Host '1/5 Building and starting Xynk...'
Invoke-ProjectCompose up -d --build
if ($LASTEXITCODE -ne 0) { throw 'Docker Compose failed to start.' }

Write-Host '2/5 Waiting for Keycloak...'
$ready = $false
# A cold Keycloak container augments the provider before serving the realm.
$realmDeadline = [DateTime]::UtcNow.AddMinutes(4)
while ([DateTime]::UtcNow -lt $realmDeadline) {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:8180/realms/xynk/.well-known/openid-configuration' -TimeoutSec 3 | Out-Null
        $ready = $true
        break
    } catch {
        Start-Sleep -Seconds 2
    }
}
if (-not $ready) { throw 'Keycloak did not become ready.' }

# X does not guarantee an email claim. Reapply its dedicated first-login flow
# whenever UAT starts so a fresh/imported realm cannot fall back to Keycloak's
# default profile-review page and require an email from an X user.
$xOAuthEnvironmentFile = Join-Path $env:USERPROFILE '.letscook\secrets\x-oauth.env'
if (Test-Path -LiteralPath $xOAuthEnvironmentFile) {
    & (Join-Path $PSScriptRoot '..\prod\enable-x-login.ps1') `
        -SecureEnvironmentFile $xOAuthEnvironmentFile `
        -KeycloakUrl 'http://localhost:8180' `
        -Realm 'xynk' `
        -AdminUsername $KeycloakAdmin `
        -AdminPassword $KeycloakPassword
} else {
    Write-Warning "X OAuth credentials were not found at $xOAuthEnvironmentFile; X login was not refreshed."
}

Write-Host '3/5 Replacing any previous temporary tunnel...'
$existing = docker ps -a --filter "name=^/$containerName$" --format '{{.Names}}'
if ($existing -eq $containerName) {
    docker rm -f $containerName | Out-Null
}

$tunnelArgs = @(
    'run', '-d', '--name', $containerName,
    'cloudflare/cloudflared:latest',
    'tunnel', '--no-autoupdate', '--url', 'http://host.docker.internal:4200'
)
foreach ($mail in $AllowedMail) {
    if ($mail.Trim()) {
        $tunnelArgs += @('--allowed-mail', $mail.Trim())
    }
}
docker @tunnelArgs | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cloudflare Quick Tunnel failed to start.' }

Write-Host '4/5 Waiting for the temporary Cloudflare URL...'
$publicUrl = $null
for ($attempt = 1; $attempt -le 30; $attempt++) {
    # cloudflared writes its normal Quick Tunnel notice to stderr. With the
    # script's Stop preference, PowerShell otherwise treats that notice as a
    # terminating error before the URL can be parsed.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $logs = docker logs $containerName 2>&1 | Out-String
    $ErrorActionPreference = $previousErrorActionPreference
    $match = [regex]::Match($logs, 'https://[a-z0-9-]+\.trycloudflare\.com')
    if ($match.Success) {
        $publicUrl = $match.Value
        break
    }
    Start-Sleep -Seconds 2
}
if (-not $publicUrl) {
    docker logs $containerName
    throw 'Cloudflare did not provide a Quick Tunnel URL.'
}

Write-Host '5/5 Replacing old tunnel URLs in Keycloak with the new URL...'
Invoke-ProjectCompose exec -T keycloak /opt/keycloak/bin/kcadm.sh config credentials `
    --server http://localhost:8080 --realm master --user $KeycloakAdmin --password $KeycloakPassword | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not authenticate the Keycloak admin CLI.' }

$clientJson = Invoke-ProjectCompose exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients `
    -r xynk -q clientId=lets-cook-web --fields id,clientId
if ($LASTEXITCODE -ne 0) { throw 'Could not find the Keycloak web client.' }
$client = @($clientJson | ConvertFrom-Json)[0]
if (-not $client.id) { throw 'Keycloak client lets-cook-web was not found.' }

$redirects = '["http://localhost:4200","http://localhost:4200/*","http://192.168.0.3:4200","http://192.168.0.3:4200/*","https://xynk.in","https://xynk.in/*","https://www.xynk.in","https://www.xynk.in/*","' + $publicUrl + '","' + $publicUrl + '/*"]'
$origins = '["http://localhost:4200","http://192.168.0.3:4200","https://xynk.in","https://www.xynk.in","' + $publicUrl + '"]'
Invoke-ProjectCompose exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$($client.id)" `
    -r xynk -s "redirectUris=$redirects" -s "webOrigins=$origins"
if ($LASTEXITCODE -ne 0) { throw 'Could not register the Quick Tunnel URL in Keycloak.' }

# The update above deliberately replaces the complete arrays. It does not append,
# so a hostname generated by an earlier Quick Tunnel cannot remain authorized.

Write-Host ''
Write-Host 'Xynk UAT is ready:' -ForegroundColor Green
Write-Host $publicUrl -ForegroundColor Cyan
Write-Host 'Previous trycloudflare.com URLs have been removed from Keycloak.' -ForegroundColor DarkGray
Write-Host ''
$configuredMedia = Get-ConfiguredMedia
if ($SelfHostedInternetMedia) {
    Write-Host 'Global media endpoint: self-hosted LiveKit on this laptop' -ForegroundColor Green
    Write-Host 'Required router forwards: TCP 7881, UDP 7882, UDP 3478.' -ForegroundColor Yellow
    Write-Host 'Remote media works only when this connection has a public IP and those ports reach this laptop.' -ForegroundColor DarkGray
} elseif ($globalMediaReady) {
    Write-Host "Global media endpoint: $($configuredMedia.Url)" -ForegroundColor Green
    Write-Host 'Remote voice and screen sharing are configured for Internet UAT.' -ForegroundColor DarkGray
} else {
    Write-Warning 'The web app is global, but voice/screen media is LAN-only.'
    Write-Host 'Configure LiveKit Cloud or a public self-hosted endpoint in the private user secrets file, then rerun this script.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host 'Share this URL only with your testers. Press Ctrl+C does not stop the detached tunnel.'
Write-Host 'Run infra\scripts\dev\stop-cloudflare-uat.ps1 when testing is finished.'

if ($OpenIncognitoSessions -gt 0) {
    & "$PSScriptRoot\open-incognito-test-sessions.ps1" `
        -Sessions $OpenIncognitoSessions -Url $publicUrl -Browser $TestBrowser
}
