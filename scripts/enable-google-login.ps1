param(
    [Parameter(Mandatory = $true)][string]$ClientId,
    [Parameter(Mandatory = $true)][string]$ClientSecret,
    [string]$KeycloakUrl = 'http://localhost:8180',
    [string]$Realm = 'lets-cook',
    [string]$AdminUsername = 'admin',
    [string]$AdminPassword = 'admin'
)

$ErrorActionPreference = 'Stop'
$token = Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/realms/master/protocol/openid-connect/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ client_id = 'admin-cli'; grant_type = 'password'; username = $AdminUsername; password = $AdminPassword }
$headers = @{ Authorization = "Bearer $($token.access_token)" }
$provider = @{
    alias = 'google'; displayName = 'Continue with Google'; providerId = 'google'; enabled = $true
    trustEmail = $true; storeToken = $false; linkOnly = $false; firstBrokerLoginFlowAlias = 'first broker login'
    config = @{
        clientId = $ClientId; clientSecret = $ClientSecret; defaultScope = 'openid profile email'
        syncMode = 'IMPORT'; useJwksUrl = 'true'
    }
} | ConvertTo-Json -Depth 5
$instanceUrl = "$KeycloakUrl/admin/realms/$Realm/identity-provider/instances/google"
$existing = Invoke-WebRequest -Method Get -Uri $instanceUrl -Headers $headers -SkipHttpErrorCheck
if ($existing.StatusCode -eq 404) {
    Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/admin/realms/$Realm/identity-provider/instances" `
        -Headers $headers -ContentType 'application/json' -Body $provider
    Write-Output 'Google login created.'
} else {
    Invoke-RestMethod -Method Put -Uri $instanceUrl -Headers $headers -ContentType 'application/json' -Body $provider
    Write-Output 'Google login updated.'
}
Write-Output "Authorized Google redirect URI: $KeycloakUrl/realms/$Realm/broker/google/endpoint"
Write-Output 'Matching emails require one secure existing-account authentication before linking.'

