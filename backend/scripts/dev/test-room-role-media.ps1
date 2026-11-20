param([string]$ApiUrl='http://localhost:8080',[string]$KeycloakUrl='http://localhost:8180')
$ErrorActionPreference='Stop'
function Token($name) { (Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/realms/xynk/protocol/openid-connect/token" -ContentType 'application/x-www-form-urlencoded' -Body @{client_id='lets-cook-web';grant_type='password';username=$name;password=$name}).access_token }
function Expect($condition,$message) { if(-not $condition){throw "FAIL: $message"}; Write-Output "PASS: $message" }
function Status($method,$url,$headers,$body=$null) { try { $args=@{Method=$method;Uri=$url;Headers=$headers};if($null -ne $body){$args.ContentType='application/json';$args.Body=$body};Invoke-WebRequest @args|Out-Null;return 200 } catch { if($_.Exception.Response){return [int]$_.Exception.Response.StatusCode};throw } }
$hostHeaders=@{Authorization="Bearer $(Token 'demo')"}
$memberHeaders=@{Authorization="Bearer $(Token 'test')"}
$hostProfile=Invoke-RestMethod -Uri "$ApiUrl/api/me" -Headers $hostHeaders
$memberProfile=Invoke-RestMethod -Uri "$ApiUrl/api/me" -Headers $memberHeaders
Expect ($hostProfile.id -ne $memberProfile.id) 'Two distinct accounts authenticate'
$roomId=$null
try {
  $room=(Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms" -Headers $hostHeaders -ContentType 'application/json' -Body (@{name="Role flow $([Guid]::NewGuid().ToString('N').Substring(0,8))";accessPolicy='INVITE_ONLY';approvalRequired=$false;maxMembers=4;visibility='PRIVATE';ephemeral=$true}|ConvertTo-Json)).room
  $roomId=$room.id
  Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/live/join" -Headers $hostHeaders|Out-Null
  Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/invite-user/$($memberProfile.id)" -Headers $hostHeaders|Out-Null
  Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/live/join" -Headers $memberHeaders|Out-Null
  $initial=Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/media-token" -Headers $memberHeaders
  Expect (-not $initial.canPublish) 'Member cannot share before host grant'
  Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/screen-share-request" -Headers $memberHeaders|Out-Null
  $people=@(Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$roomId/live/participants" -Headers $hostHeaders)
  Expect (@($people|Where-Object {$_.userId -eq $memberProfile.id -and $_.screenShareRequested}).Count -eq 1) 'Host sees screen share request'
  Expect ((Status 'Post' "$ApiUrl/api/rooms/$roomId/members/$($hostProfile.id)/microphone-action" $memberHeaders '{"action":"MUTE"}') -eq 403) 'Member cannot control host microphone'
  Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/members/$($memberProfile.id)/screen-permission" -Headers $hostHeaders -ContentType 'application/json' -Body '{"allowed":true}'|Out-Null
  $approved=Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/media-token" -Headers $memberHeaders
  Expect ($approved.canPublish) 'Host grant enables member screen share token'
  Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/members/$($memberProfile.id)/microphone-action" -Headers $hostHeaders -ContentType 'application/json' -Body '{"action":"MUTE"}'|Out-Null
  Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/members/$($memberProfile.id)/microphone-action" -Headers $hostHeaders -ContentType 'application/json' -Body '{"action":"REQUEST_UNMUTE"}'|Out-Null
  Write-Output 'PASS: Host mic actions accepted'
  Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/members/$($memberProfile.id)/screen-permission" -Headers $hostHeaders -ContentType 'application/json' -Body '{"allowed":false}'|Out-Null
  $revoked=Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/media-token" -Headers $memberHeaders
  Expect (-not $revoked.canPublish) 'Revocation removes screen sharing from new token'
  Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/members/$($memberProfile.id)/leadership/CO_HOST" -Headers $hostHeaders|Out-Null
  $cohostToken=Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/media-token" -Headers $memberHeaders
  Expect (-not $cohostToken.canPublish) 'Co-host promotion does not auto-grant screen sharing'
  $cohostQueue=Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$roomId/watch/queue" -Headers $memberHeaders
  Expect (-not $cohostQueue.canAdd) 'Co-host promotion does not auto-grant video selection'
  Expect ((Status 'Post' "$ApiUrl/api/rooms/$roomId/members/$($hostProfile.id)/microphone-action" $memberHeaders '{"action":"MUTE"}') -eq 403) 'Co-host cannot control microphones'
  Expect ((Status 'Post' "$ApiUrl/api/rooms/$roomId/members/$($memberProfile.id)/video-permission" $memberHeaders '{"allowed":true}') -eq 403) 'Co-host cannot grant video selection'
  Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/members/$($memberProfile.id)/video-permission" -Headers $hostHeaders -ContentType 'application/json' -Body '{"allowed":true}'|Out-Null
  $grantedQueue=Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$roomId/watch/queue" -Headers $memberHeaders
  Expect ($grantedQueue.canAdd) 'Host can grant co-host video selection'
} finally { if($roomId){try{Invoke-RestMethod -Method Delete -Uri "$ApiUrl/api/rooms/$roomId" -Headers $hostHeaders|Out-Null}catch{}} }
