param(
    [Parameter(Mandatory = $true)][string]$LanHost,
    [string]$KeycloakUrl = 'http://localhost:8180',
    [string]$Realm = 'xynk',
    [string]$AdminUsername = 'admin',
    [string]$AdminPassword = 'admin'
)

$ErrorActionPreference = 'Stop'
$token = Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/realms/master/protocol/openid-connect/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ client_id = 'admin-cli'; grant_type = 'password'; username = $AdminUsername; password = $AdminPassword }
$headers = @{ Authorization = "Bearer $($token.access_token)" }
$matches = Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/clients?clientId=lets-cook-web" -Headers $headers
if ($matches.Count -ne 1) { throw 'Could not uniquely resolve the lets-cook-web client.' }
$client = Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/clients/$($matches[0].id)" -Headers $headers
$origin = "http://${LanHost}:4200"
$client.redirectUris = @($client.redirectUris + $origin + "$origin/*" | Sort-Object -Unique)
$client.webOrigins = @($client.webOrigins + $origin | Sort-Object -Unique)
$postLogoutUris = @()
if ($client.attributes.'post.logout.redirect.uris') {
    $postLogoutUris += $client.attributes.'post.logout.redirect.uris' -split '##'
}
$postLogoutUris += $origin
$postLogoutUris += "$origin/*"
$client.attributes.'post.logout.redirect.uris' = ($postLogoutUris | Sort-Object -Unique) -join '##'
$body = $client | ConvertTo-Json -Depth 20
Invoke-RestMethod -Method Put -Uri "$KeycloakUrl/admin/realms/$Realm/clients/$($matches[0].id)" `
    -Headers $headers -ContentType 'application/json' -Body $body
Write-Output "Keycloak web login and logout now accept $origin."
