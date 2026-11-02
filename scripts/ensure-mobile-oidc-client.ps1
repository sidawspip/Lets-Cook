param(
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
$clients = Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/clients?clientId=lets-cook-mobile" -Headers $headers
$client = @{
    clientId = 'lets-cook-mobile'; name = "Let's Cook Mobile"; enabled = $true; publicClient = $true
    standardFlowEnabled = $true; directAccessGrantsEnabled = $true
    redirectUris = @('world.letscook.app:/oauthredirect'); webOrigins = @()
    attributes = @{ 'pkce.code.challenge.method' = 'S256' }
} | ConvertTo-Json -Depth 5
if ($clients.Count -eq 0) {
    Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/admin/realms/$Realm/clients" -Headers $headers -ContentType 'application/json' -Body $client
    Write-Output 'Mobile OIDC client created.'
} else {
    Invoke-RestMethod -Method Put -Uri "$KeycloakUrl/admin/realms/$Realm/clients/$($clients[0].id)" -Headers $headers -ContentType 'application/json' -Body $client
    Write-Output 'Mobile OIDC client updated.'
}
