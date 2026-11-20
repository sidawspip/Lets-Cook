$ErrorActionPreference = 'Stop'
$privateFile = 'C:\Users\siddh\.letscook\secrets\voice-test-credentials.json'
$users = Get-Content -LiteralPath $privateFile -Raw | ConvertFrom-Json
$tokens = @{}
foreach ($user in $users) {
  $auth = Invoke-RestMethod -Method Post -Uri 'https://xynk.in/realms/xynk/protocol/openid-connect/token' -ContentType 'application/x-www-form-urlencoded' -Body @{
    client_id = 'lets-cook-web'; grant_type = 'password'; username = $user.username; password = $user.password
  }
  $tokens[$user.role] = $auth.access_token
  $me = Invoke-RestMethod -Uri 'https://xynk.in/api/me' -Headers @{ Authorization = "Bearer $($auth.access_token)" }
  if ($me.username -ne $user.username) { throw "Profile mismatch for $($user.role)." }
  Write-Output "Authenticated $($user.role) through public app API."
}
$name = "Voice test $([Guid]::NewGuid().ToString('N').Substring(0, 8))"
$created = Invoke-RestMethod -Method Post -Uri 'https://xynk.in/api/rooms' -Headers @{ Authorization = "Bearer $($tokens.host)" } -ContentType 'application/json' -Body (@{
  name = $name; description = 'Temporary LiveKit voice test'; accessPolicy = 'OPEN'; approvalRequired = $false; maxMembers = 10; visibility = 'PUBLIC'; ephemeral = $true
} | ConvertTo-Json)
$roomId = $created.room.id
if (-not $roomId) { throw 'Room creation did not return an ID.' }
Write-Output "Created public temporary room $roomId."
foreach ($role in @('host', 'guest')) {
  $headers = @{ Authorization = "Bearer $($tokens[$role])" }
  if ($role -eq 'guest') {
    Invoke-RestMethod -Method Post -Uri "https://xynk.in/api/rooms/$roomId/unlock" -Headers $headers -ContentType 'application/json' -Body '{}' | Out-Null
  }
  Invoke-RestMethod -Method Post -Uri "https://xynk.in/api/rooms/$roomId/live/join" -Headers $headers | Out-Null
  $media = Invoke-RestMethod -Method Post -Uri "https://xynk.in/api/rooms/$roomId/media-token" -Headers $headers -ContentType 'application/json' -Body '{}'
  if ($media.url -ne 'wss://media.xynk.in' -or -not $media.token) { throw "Invalid media credentials for $role." }
  Write-Output "Issued VM LiveKit token for $role."
}
@{ roomId = $roomId; name = $name; users = @($users | Select-Object role,username) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath 'C:\Users\siddh\.letscook\secrets\voice-test-room.json' -Encoding utf8
