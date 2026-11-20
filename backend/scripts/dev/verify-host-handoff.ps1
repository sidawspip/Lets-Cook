$ErrorActionPreference = 'Stop'
$users = Get-Content 'C:\Users\siddh\.letscook\secrets\voice-test-credentials.json' -Raw | ConvertFrom-Json
$headers = @{}
$profiles = @{}
foreach ($user in $users) {
  $token = Invoke-RestMethod -Method Post -Uri 'https://xynk.in/realms/xynk/protocol/openid-connect/token' -ContentType 'application/x-www-form-urlencoded' -Body @{
    client_id = 'lets-cook-web'; grant_type = 'password'; username = $user.username; password = $user.password
  }
  $headers[$user.role] = @{ Authorization = "Bearer $($token.access_token)" }
  $profiles[$user.role] = Invoke-RestMethod -Uri 'https://xynk.in/api/me' -Headers $headers[$user.role]
}
$created = Invoke-RestMethod -Method Post -Uri 'https://xynk.in/api/rooms' -Headers $headers.host -ContentType 'application/json' -Body (@{
  name = "Handoff test $([Guid]::NewGuid().ToString('N').Substring(0, 8))"
  description = 'Temporary host-handoff test'; accessPolicy = 'OPEN'; approvalRequired = $false
  maxMembers = 4; visibility = 'PUBLIC'; ephemeral = $true
} | ConvertTo-Json)
$roomId = $created.room.id
try {
  Invoke-RestMethod -Method Post -Uri "https://xynk.in/api/rooms/$roomId/live/join" -Headers $headers.host | Out-Null
  Invoke-RestMethod -Method Post -Uri "https://xynk.in/api/rooms/$roomId/unlock" -Headers $headers.guest -ContentType 'application/json' -Body '{}' | Out-Null
  Invoke-RestMethod -Method Post -Uri "https://xynk.in/api/rooms/$roomId/live/join" -Headers $headers.guest | Out-Null
  Invoke-RestMethod -Method Delete -Uri "https://xynk.in/api/rooms/$roomId/live/leave" -Headers $headers.host | Out-Null

  $participants = @(Invoke-RestMethod -Uri "https://xynk.in/api/rooms/$roomId/live/participants" -Headers $headers.guest)
  $guestId = $profiles.guest.id
  $newHost = $participants | Where-Object { $_.userId -eq $guestId } | Select-Object -First 1
  if ($newHost.role -ne 'HOST' -or !$newHost.canShareScreen -or !$newHost.canAddVideos -or !$newHost.canViewVideo) {
    throw "Promoted host permissions: role=$($newHost.role), share=$($newHost.canShareScreen), add=$($newHost.canAddVideos), view=$($newHost.canViewVideo), count=$($participants.Count)."
  }
  Write-Output 'PASS: present guest became host with viewing, queue, and sharing permissions.'

  $media = Invoke-RestMethod -Method Post -Uri "https://xynk.in/api/rooms/$roomId/media-token" -Headers $headers.guest -ContentType 'application/json' -Body '{}'
  if ($media.url -ne 'wss://media.xynk.in' -or !$media.canPublish -or !$media.token) { throw 'New host did not receive media publishing token.' }
  Write-Output 'PASS: new host received VM voice/screen publishing token.'

  $state = Invoke-RestMethod -Method Put -Uri "https://xynk.in/api/rooms/$roomId/watch" -Headers $headers.guest -ContentType 'application/json' -Body (@{
    provider = 'DIRECT_MP4'; sourceType = 'DIRECT'; mediaId = 'handoff-smoke'; sourceUrl = 'https://example.com/handoff-smoke.mp4'
    title = 'Handoff smoke test'; playing = $false; positionSeconds = 0; playbackRate = 1
  } | ConvertTo-Json)
  if ($state.mediaId -ne 'handoff-smoke') { throw 'New host could not control playback.' }
  Write-Output 'PASS: new host controlled playback.'

  Invoke-RestMethod -Method Patch -Uri "https://xynk.in/api/rooms/$roomId/settings" -Headers $headers.guest -ContentType 'application/json' -Body '{"name":"Handoff ownership verified"}' | Out-Null
  Write-Output 'PASS: new host changed owner-only room settings.'
} finally {
  Invoke-RestMethod -Method Delete -Uri "https://xynk.in/api/rooms/$roomId" -Headers $headers.guest | Out-Null
}
