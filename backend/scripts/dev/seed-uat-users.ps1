param(
    [string]$KeycloakUrl = 'http://localhost:8180',
    [string]$Realm = 'xynk',
    [string]$AdminUsername = 'admin',
    [string]$AdminPassword = 'admin',
    [string]$UatPassword = 'Uat@123'
)

$ErrorActionPreference = 'Stop'
$token = Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/realms/master/protocol/openid-connect/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ client_id = 'admin-cli'; grant_type = 'password'; username = $AdminUsername; password = $AdminPassword }
$headers = @{ Authorization = "Bearer $($token.access_token)" }
$users = @(
    @{ username = 'test';  email = 'test@uat.local';  firstName = 'Test';  lastName = 'User';   password = 'test' },
    @{ username = 'demo';  email = 'demo@example.com'; firstName = 'Demo';  lastName = 'User';   password = 'demo' },
    @{ username = 'ankit'; email = 'ankit@uat.local';  firstName = 'Ankit'; lastName = 'Jain';   password = $UatPassword },
    @{ username = 'rahul'; email = 'rahul@uat.local';  firstName = 'Rahul'; lastName = 'Sharma'; password = $UatPassword },
    @{ username = 'priya'; email = 'priya@uat.local';  firstName = 'Priya'; lastName = 'Rao';    password = $UatPassword }
)

foreach ($user in $users) {
    $encodedUsername = [Uri]::EscapeDataString($user.username)
    $existing = @(
        Invoke-RestMethod -Method Get `
            -Uri "$KeycloakUrl/admin/realms/$Realm/users?username=$encodedUsername&exact=true" -Headers $headers
    ) | Where-Object { $_ -and $_.username -eq $user.username }
    if ($existing.Count -eq 0) {
        $body = @{
            username = $user.username; email = $user.email; emailVerified = $true
            firstName = $user.firstName; lastName = $user.lastName; enabled = $true
        } | ConvertTo-Json
        Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/admin/realms/$Realm/users" `
            -Headers $headers -ContentType 'application/json' -Body $body
        $existing = @(
            Invoke-RestMethod -Method Get `
                -Uri "$KeycloakUrl/admin/realms/$Realm/users?username=$encodedUsername&exact=true" -Headers $headers
        ) | Where-Object { $_ -and $_.username -eq $user.username }
        Write-Output "Created UAT user: $($user.username)"
    } else {
        Write-Output "UAT user already exists: $($user.username)"
    }
    $userId = $existing[0].id
    $credential = @{ type = 'password'; value = $user.password; temporary = $false } | ConvertTo-Json
    $passwordUrl = '{0}/admin/realms/{1}/users/{2}/reset-password' -f $KeycloakUrl, $Realm, $userId
    Invoke-RestMethod -Method Put `
        -Uri $passwordUrl `
        -Headers $headers -ContentType 'application/json' -Body $credential
}
Write-Output 'UAT users are ready.'

