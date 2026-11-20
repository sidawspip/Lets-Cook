param(
    [string]$KeycloakUrl = 'http://localhost:8180',
    [string]$Realm = 'xynk',
    [string]$SecureEnvironmentFile = (Join-Path $env:USERPROFILE '.letscook\secrets\native-google.env'),
    [string]$AdminUsername = 'admin',
    [string]$AdminPassword = 'admin'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $SecureEnvironmentFile)) {
    throw "Protected configuration was not found at $SecureEnvironmentFile"
}

$settings = @{}
Get-Content -LiteralPath $SecureEnvironmentFile | ForEach-Object {
    if ($_ -match '^([^#=]+)=(.*)$') { $settings[$matches[1]] = $matches[2] }
}
foreach ($required in 'GOOGLE_CLIENT_ID','GOOGLE_CLIENT_SECRET','KEYCLOAK_NATIVE_AUTH_CLIENT_ID','KEYCLOAK_NATIVE_AUTH_CLIENT_SECRET') {
    if (-not $settings[$required]) { throw "Missing $required in protected configuration." }
}

$admin = Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/realms/master/protocol/openid-connect/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ client_id='admin-cli'; grant_type='password'; username=$AdminUsername; password=$AdminPassword }
$headers = @{ Authorization = "Bearer $($admin.access_token)" }

function Set-ClientPictureMapper([string]$TargetClientId) {
    $matches = @(Invoke-RestMethod -Method Get `
        -Uri "$KeycloakUrl/admin/realms/$Realm/clients?clientId=$TargetClientId" -Headers $headers |
        Where-Object { $_.clientId -eq $TargetClientId })
    if ($matches.Count -eq 0) { throw "Keycloak client $TargetClientId was not found." }
    $clientUuid = $matches[0].id
    $base = "$KeycloakUrl/admin/realms/$Realm/clients/$clientUuid/protocol-mappers/models"
    $mapper = @{
        name='provider-picture'; protocol='openid-connect'
        protocolMapper='oidc-usermodel-attribute-mapper'; consentRequired=$false
        config=@{
            'user.attribute'='picture'; 'claim.name'='picture'; 'jsonType.label'='String'
            'id.token.claim'='true'; 'access.token.claim'='true'; 'userinfo.token.claim'='true'
        }
    }
    $existing = @(Invoke-RestMethod -Method Get -Uri $base -Headers $headers | Where-Object { $_.name -eq $mapper.name })
    if ($existing.Count -eq 0) {
        $body = $mapper | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Method Post -Uri $base -Headers $headers -ContentType 'application/json' -Body $body | Out-Null
    } else {
        $mapper.id = $existing[0].id
        $body = $mapper | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Method Put -Uri "$base/$($existing[0].id)" -Headers $headers -ContentType 'application/json' -Body $body | Out-Null
    }
}

$googleFirstLoginFlow = 'google verified email auto link'
$flowBaseUrl = "$KeycloakUrl/admin/realms/$Realm/authentication"
$flows = @(Invoke-RestMethod -Method Get -Uri "$flowBaseUrl/flows" -Headers $headers |
    Where-Object { $_.alias -eq $googleFirstLoginFlow })
if ($flows.Count -eq 0) {
    $flowBody = @{
        alias = $googleFirstLoginFlow
        description = 'Create new Google users or auto-link an existing account by Google verified email.'
        providerId = 'basic-flow'
        topLevel = $true
        builtIn = $false
    } | ConvertTo-Json
    Invoke-RestMethod -Method Post -Uri "$flowBaseUrl/flows" -Headers $headers `
        -ContentType 'application/json' -Body $flowBody | Out-Null
}

$encodedGoogleFlow = [Uri]::EscapeDataString($googleFirstLoginFlow)
$googleFlowSteps = @(
    @{ providerId = 'idp-create-user-if-unique'; requirement = 'ALTERNATIVE' },
    @{ providerId = 'idp-auto-link'; requirement = 'ALTERNATIVE' }
)
foreach ($step in $googleFlowSteps) {
    $executions = @(Invoke-RestMethod -Method Get `
        -Uri "$flowBaseUrl/flows/$encodedGoogleFlow/executions" -Headers $headers)
    $execution = $null
    foreach ($executionGroup in $executions) {
        foreach ($candidate in $executionGroup) {
            if ($candidate.providerId -eq $step.providerId) { $execution = $candidate; break }
        }
        if ($execution) { break }
    }
    if (-not $execution) {
        Invoke-RestMethod -Method Post -Uri "$flowBaseUrl/flows/$encodedGoogleFlow/executions/execution" `
            -Headers $headers -ContentType 'application/json' `
            -Body (@{ provider = $step.providerId } | ConvertTo-Json) | Out-Null
        $executions = @(Invoke-RestMethod -Method Get `
            -Uri "$flowBaseUrl/flows/$encodedGoogleFlow/executions" -Headers $headers)
        foreach ($executionGroup in $executions) {
            foreach ($candidate in $executionGroup) {
                if ($candidate.providerId -eq $step.providerId) { $execution = $candidate; break }
            }
            if ($execution) { break }
        }
    }
    if (-not $execution) { throw "Could not configure Google flow step $($step.providerId)." }
    if ($execution.requirement -ne $step.requirement) {
        $executionUpdate = @{
            id = $execution.id
            requirement = $step.requirement
        } | ConvertTo-Json
        Invoke-RestMethod -Method Put -Uri "$flowBaseUrl/flows/$encodedGoogleFlow/executions" `
            -Headers $headers -ContentType 'application/json' `
            -Body $executionUpdate | Out-Null
    }
}

$provider = @{
    alias='google'; displayName='Continue with Google'; providerId='google'; enabled=$true
    trustEmail=$true; storeToken=$false; linkOnly=$false; firstBrokerLoginFlowAlias=$googleFirstLoginFlow
    config=@{
        clientId=$settings.GOOGLE_CLIENT_ID; clientSecret=$settings.GOOGLE_CLIENT_SECRET
        defaultScope='openid profile email'; syncMode='IMPORT'; useJwksUrl='true'; prompt='select_account'
        issuer='https://accounts.google.com'; jwksUrl='https://www.googleapis.com/oauth2/v3/certs'
        jwtAuthorizationGrantEnabled='true'; jwtAuthorizationGrantAssertionReuseAllowed='true'
        jwtAuthorizationGrantMaxAllowedAssertionExpiration='3600'; jwtAuthorizationGrantLimitAccessTokenExp='true'
    }
} | ConvertTo-Json -Depth 6
$providerUrl = "$KeycloakUrl/admin/realms/$Realm/identity-provider/instances/google"
$providerCheck = Invoke-WebRequest -Method Get -Uri $providerUrl -Headers $headers -SkipHttpErrorCheck
if ($providerCheck.StatusCode -eq 404) {
    Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/admin/realms/$Realm/identity-provider/instances" `
        -Headers $headers -ContentType 'application/json' -Body $provider | Out-Null
} else {
    Invoke-RestMethod -Method Put -Uri $providerUrl -Headers $headers -ContentType 'application/json' -Body $provider | Out-Null
}

$googlePictureMapper = @{
    name='google-picture'; identityProviderAlias='google'
    identityProviderMapper='oidc-user-attribute-idp-mapper'
    config=@{ claim='picture'; 'user.attribute'='picture'; syncMode='FORCE' }
}
$mapperBase = "$KeycloakUrl/admin/realms/$Realm/identity-provider/instances/google/mappers"
$existingGoogleMappers = @(Invoke-RestMethod -Method Get -Uri $mapperBase -Headers $headers)
$existingGooglePicture = @($existingGoogleMappers | Where-Object { $_.name -eq $googlePictureMapper.name })
if ($existingGooglePicture.Count -eq 0) {
    $googlePictureBody = $googlePictureMapper | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Method Post -Uri $mapperBase -Headers $headers -ContentType 'application/json' -Body $googlePictureBody | Out-Null
} else {
    $googlePictureMapper.id = $existingGooglePicture[0].id
    $googlePictureBody = $googlePictureMapper | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Method Put -Uri "$mapperBase/$($existingGooglePicture[0].id)" -Headers $headers -ContentType 'application/json' -Body $googlePictureBody | Out-Null
}

$clientId = $settings.KEYCLOAK_NATIVE_AUTH_CLIENT_ID
$client = @{
    clientId=$clientId; name="Let's Cook Native Google Broker"; enabled=$true
    publicClient=$false; secret=$settings.KEYCLOAK_NATIVE_AUTH_CLIENT_SECRET
    standardFlowEnabled=$false; directAccessGrantsEnabled=$false; serviceAccountsEnabled=$true
    protocol='openid-connect'; attributes=@{
        'oauth2.jwt.authorization.grant.enabled'='true'
        'oauth2.jwt.authorization.grant.idp'='google'
    }
} | ConvertTo-Json -Depth 5
$clients = @(Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/clients?clientId=$clientId" -Headers $headers |
    Where-Object { $_.clientId -eq $clientId })
if ($clients.Count -eq 0) {
    Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/admin/realms/$Realm/clients" `
        -Headers $headers -ContentType 'application/json' -Body $client | Out-Null
    $clients = @(Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/clients?clientId=$clientId" -Headers $headers |
        Where-Object { $_.clientId -eq $clientId })
} else {
    $existingClientUuid = $clients[0].id
    if (-not $existingClientUuid) {
        throw "Keycloak returned the native Google client without an internal UUID."
    }
    Write-Output "Updating existing native Google client UUID $existingClientUuid"
    Invoke-RestMethod -Method Put -Uri "$KeycloakUrl/admin/realms/$Realm/clients/$existingClientUuid" `
        -Headers $headers -ContentType 'application/json' -Body $client | Out-Null
}

$clientUuid = $clients[0].id
Set-ClientPictureMapper 'lets-cook-web'
Set-ClientPictureMapper 'lets-cook-mobile'
Set-ClientPictureMapper $clientId
$serviceUser = Invoke-RestMethod -Method Get `
    -Uri "$KeycloakUrl/admin/realms/$Realm/clients/$clientUuid/service-account-user" -Headers $headers
$realmManagementMatches = @(Invoke-RestMethod -Method Get `
    -Uri "$KeycloakUrl/admin/realms/$Realm/clients?clientId=realm-management" -Headers $headers |
    Where-Object { $_.clientId -eq 'realm-management' })
if ($realmManagementMatches.Count -eq 0) {
    throw 'Keycloak realm-management client was not found.'
}
$realmManagement = $realmManagementMatches[0]
$approvedRoleNames = @('manage-users','query-users','view-users')
$roles = @($approvedRoleNames | ForEach-Object {
    $encodedRoleName = [Uri]::EscapeDataString($_)
    Invoke-RestMethod -Method Get `
        -Uri "$KeycloakUrl/admin/realms/$Realm/clients/$($realmManagement.id)/roles/$encodedRoleName" `
        -Headers $headers
})
if ($roles.Count -ne $approvedRoleNames.Count) {
    throw "Expected the three approved realm-management roles, but Keycloak returned: $($roles.name -join ', ')"
}
$roleMappingUrl = "$KeycloakUrl/admin/realms/$Realm/users/$($serviceUser.id)/role-mappings/clients/$($realmManagement.id)"
$currentRoles = @(Invoke-RestMethod -Method Get -Uri $roleMappingUrl -Headers $headers)
$currentRoleIds = @($currentRoles | ForEach-Object { $_.id })
$missingRoles = @($roles | Where-Object { $_.id -notin $currentRoleIds })
if ($missingRoles.Count -gt 0) {
    $missingRoleBody = ConvertTo-Json -InputObject @($missingRoles) -Depth 5
    Invoke-RestMethod -Method Post -Uri $roleMappingUrl `
        -Headers $headers -ContentType 'application/json' -Body $missingRoleBody | Out-Null
}

[Environment]::SetEnvironmentVariable('LETSCOOK_SECURE_ENV', $SecureEnvironmentFile, 'User')
Write-Output 'Native Google identity provider, confidential broker client, and least-privilege service roles are configured.'
