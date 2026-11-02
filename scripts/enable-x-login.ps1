param(
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$SecureEnvironmentFile = (Join-Path $env:USERPROFILE '.letscook\secrets\x-oauth.env'),
    [string]$KeycloakUrl = 'http://localhost:8180',
    [string]$Realm = 'lets-cook',
    [string]$AdminUsername = 'admin',
    [string]$AdminPassword = 'admin'
)

$ErrorActionPreference = 'Stop'
if ((-not $ClientId -or -not $ClientSecret) -and (Test-Path -LiteralPath $SecureEnvironmentFile)) {
    $settings = @{}
    Get-Content -LiteralPath $SecureEnvironmentFile | ForEach-Object {
        if ($_ -match '^([^#=]+)=(.*)$') { $settings[$matches[1]] = $matches[2] }
    }
    if (-not $ClientId) { $ClientId = $settings.X_CLIENT_ID }
    if (-not $ClientSecret) { $ClientSecret = $settings.X_CLIENT_SECRET }
}
if (-not $ClientId -or -not $ClientSecret) {
    throw "X OAuth credentials were not found in $SecureEnvironmentFile"
}

$token = Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/realms/master/protocol/openid-connect/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ client_id = 'admin-cli'; grant_type = 'password'; username = $AdminUsername; password = $AdminPassword }
$headers = @{ Authorization = "Bearer $($token.access_token)" }
$xFirstLoginFlow = 'x first broker login'
$flowBaseUrl = "$KeycloakUrl/admin/realms/$Realm/authentication"
$flows = @(Invoke-RestMethod -Method Get -Uri "$flowBaseUrl/flows" -Headers $headers)
$xFlow = $null
foreach ($flowGroup in $flows) {
    foreach ($candidate in $flowGroup) {
        if ($candidate.alias -eq $xFirstLoginFlow) { $xFlow = $candidate; break }
    }
    if ($xFlow) { break }
}
if (-not $xFlow) {
    $sourceFlow = [Uri]::EscapeDataString('first broker login')
    Invoke-RestMethod -Method Post -Uri "$flowBaseUrl/flows/$sourceFlow/copy" `
        -Headers $headers -ContentType 'application/json' `
        -Body (@{ newName = $xFirstLoginFlow } | ConvertTo-Json)
}

$encodedXFlow = [Uri]::EscapeDataString($xFirstLoginFlow)
$executions = @(Invoke-RestMethod -Method Get -Uri "$flowBaseUrl/flows/$encodedXFlow/executions" -Headers $headers)
$reviewProfile = $null
foreach ($executionGroup in $executions) {
    foreach ($candidate in $executionGroup) {
        if ($candidate.providerId -eq 'idp-review-profile') { $reviewProfile = $candidate; break }
    }
    if ($reviewProfile) { break }
}
if (-not $reviewProfile) {
    throw "The copied '$xFirstLoginFlow' flow does not contain the Review Profile execution."
}
$reviewConfig = @{
    alias = 'x review profile config'
    config = @{ 'update.profile.on.first.login' = 'off' }
}
if ($reviewProfile.authenticationConfig) {
    $reviewConfig.id = $reviewProfile.authenticationConfig
    Invoke-RestMethod -Method Put -Uri "$flowBaseUrl/config/$($reviewProfile.authenticationConfig)" `
        -Headers $headers -ContentType 'application/json' -Body ($reviewConfig | ConvertTo-Json -Depth 4)
} else {
    Invoke-RestMethod -Method Post -Uri "$flowBaseUrl/executions/$($reviewProfile.id)/config" `
        -Headers $headers -ContentType 'application/json' -Body ($reviewConfig | ConvertTo-Json -Depth 4)
}

$provider = @{
    alias = 'x'; displayName = 'Continue with X'; providerId = 'oauth2'; enabled = $true
    trustEmail = $false; storeToken = $false; linkOnly = $false; firstBrokerLoginFlowAlias = $xFirstLoginFlow
    config = @{
        clientId = $ClientId; clientSecret = $ClientSecret
        authorizationUrl = 'https://x.com/i/oauth2/authorize'
        tokenUrl = 'https://api.x.com/2/oauth2/token'
        userInfoUrl = 'https://api.x.com/2/users/me?user.fields=confirmed_email,profile_image_url,name'
        clientAuthMethod = 'client_secret_basic'; defaultScope = 'users.read tweet.read'
        pkceEnabled = 'true'; pkceMethod = 'S256'; syncMode = 'IMPORT'
        userIDClaim = 'data.id'; userNameClaim = 'data.username'; fullNameClaim = 'data.name'
        emailClaim = 'data.confirmed_email'
    }
} | ConvertTo-Json -Depth 5
$instanceUrl = "$KeycloakUrl/admin/realms/$Realm/identity-provider/instances/x"
$existing = Invoke-WebRequest -Method Get -Uri $instanceUrl -Headers $headers -SkipHttpErrorCheck
if ($existing.StatusCode -eq 404) {
    Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/admin/realms/$Realm/identity-provider/instances" `
        -Headers $headers -ContentType 'application/json' -Body $provider
    Write-Output 'X login created.'
} else {
    Invoke-RestMethod -Method Put -Uri $instanceUrl -Headers $headers -ContentType 'application/json' -Body $provider
    Write-Output 'X login updated.'
}
Write-Output "Authorized X callback URL: $KeycloakUrl/realms/$Realm/broker/x/endpoint"
Write-Output 'X uses OAuth 2.0 Authorization Code with PKCE through Keycloak.'
Write-Output "X first-time accounts use '$xFirstLoginFlow'; missing email does not open the profile form."
