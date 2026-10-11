param(
    [string]$KeycloakUrl = 'http://localhost:8180',
    [string]$ApiUrl = 'http://localhost:8080',
    [string]$Realm = 'lets-cook',
    [string]$UatPassword = 'Uat@123'
)

$ErrorActionPreference = 'Stop'
$roomIds = [System.Collections.Generic.List[string]]::new()

function Get-UatToken([string]$Username, [string]$Password) {
    $response = Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/realms/$Realm/protocol/openid-connect/token" `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body @{ client_id = 'lets-cook-web'; grant_type = 'password'; username = $Username; password = $Password }
    return $response.access_token
}
function Headers([string]$Token) { return @{ Authorization = "Bearer $Token" } }
function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    Write-Output "PASS: $Name"
}
function Invoke-ExpectedError([string]$Method, [string]$Uri, [hashtable]$Headers, [string]$Body = $null) {
    try {
        $params = @{ Method = $Method; Uri = $Uri; Headers = $Headers }
        if ($null -ne $Body) {
            $params.ContentType = 'application/json'
            $params.Body = $Body
        }
        Invoke-WebRequest @params | Out-Null
        return 200
    } catch {
        if ($null -eq $_.Exception.Response) { throw }
        return [int]$_.Exception.Response.StatusCode
    }
}
function New-UatRoom([hashtable]$Headers, [string]$Name, [string]$Policy, [bool]$ApprovalRequired) {
    $body = @{
        name = $Name; description = 'Automated UAT room'; accessPolicy = $Policy
        approvalRequired = $ApprovalRequired; maxMembers = 10
    } | ConvertTo-Json
    $created = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms" -Headers $Headers `
        -ContentType 'application/json' -Body $body
    $roomIds.Add($created.room.id)
    return $created
}

try {
    $ankitHeaders = Headers (Get-UatToken 'ankit' $UatPassword)
    $rahulHeaders = Headers (Get-UatToken 'rahul' $UatPassword)
    $priyaHeaders = Headers (Get-UatToken 'priya' $UatPassword)
    $ankit = Invoke-RestMethod -Uri "$ApiUrl/api/me" -Headers $ankitHeaders
    $rahul = Invoke-RestMethod -Uri "$ApiUrl/api/me" -Headers $rahulHeaders
    $priya = Invoke-RestMethod -Uri "$ApiUrl/api/me" -Headers $priyaHeaders
    Assert-True ($ankit.username -eq 'ankit' -and $rahul.username -eq 'rahul' -and $priya.username -eq 'priya') 'multiple local users authenticate'
    Assert-True ($ankit.id -ne $rahul.id -and $rahul.id -ne $priya.id) 'different emails create different app accounts'

    $room = New-UatRoom $ankitHeaders 'UAT Key Room' 'INVITE_OR_KEY' $false
    Assert-True ([bool]$room.accessKey) 'host receives a one-time room key'
    $hostMedia = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$($room.room.id)/media-token" `
        -Headers $ankitHeaders
    Assert-True ([bool]$hostMedia.token -and [bool]$hostMedia.url -and $hostMedia.canPublish) 'active host receives a publishing LiveKit media token'
    $blockedMediaStatus = Invoke-ExpectedError 'Post' "$ApiUrl/api/rooms/$($room.room.id)/media-token" $priyaHeaders
    Assert-True ($blockedMediaStatus -eq 403) 'non-member cannot receive a media token'
    $search = Invoke-RestMethod -Uri "$ApiUrl/api/search?q=UAT%20Key" -Headers $priyaHeaders
    Assert-True (@($search.rooms | Where-Object { $_.id -eq $room.room.id }).Count -eq 1) 'another user can find a room by search'
    $invite = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$($room.room.id)/invites" `
        -Headers $ankitHeaders -ContentType 'application/json' -Body (@{ role = 'MEMBER'; maxUses = 5 } | ConvertTo-Json)
    Assert-True ([bool]$invite.code -and $invite.path -like '/invite/*') 'host creates a shareable invite link'
    $inviteJoin = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/invites/$($invite.code)/accept" `
        -Headers $priyaHeaders -ContentType 'application/json' -Body '{}'
    Assert-True ($inviteJoin.accessGranted -and $inviteJoin.status -eq 'ACTIVE') 'another user joins through the invite link'
    $wrongStatus = Invoke-ExpectedError 'Post' "$ApiUrl/api/rooms/$($room.room.id)/unlock" $rahulHeaders `
        (@{ accessKey = 'WRONG-KEY' } | ConvertTo-Json)
    Assert-True ($wrongStatus -eq 403) 'wrong room key is rejected'
    $joined = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$($room.room.id)/unlock" `
        -Headers $rahulHeaders -ContentType 'application/json' `
        -Body (@{ accessKey = $room.accessKey } | ConvertTo-Json)
    Assert-True ($joined.accessGranted -and $joined.status -eq 'ACTIVE') 'correct room key grants active membership'
    $memberMedia = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$($room.room.id)/media-token" `
        -Headers $rahulHeaders
    Assert-True ([bool]$memberMedia.token -and [bool]$memberMedia.url -and -not $memberMedia.canPublish) 'member can watch but cannot share under hosts-only policy'
    Invoke-RestMethod -Method Patch -Uri "$ApiUrl/api/rooms/$($room.room.id)/settings" -Headers $ankitHeaders -ContentType 'application/json' `
        -Body (@{ name = $room.room.name; visibility = 'PUBLIC'; accessPolicy = 'INVITE_OR_KEY'; approvalRequired = $false; screenSharePolicy = 'EVERYONE' } | ConvertTo-Json)
    $everyoneMedia = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$($room.room.id)/media-token" -Headers $rahulHeaders
    Assert-True ($everyoneMedia.canPublish) 'owner can allow everyone in the room to share'
    Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$($room.room.id)/live/join" -Headers $ankitHeaders
    Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$($room.room.id)/live/join" -Headers $rahulHeaders
    $livePeople = Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$($room.room.id)/live/participants" -Headers $ankitHeaders
    Assert-True (@($livePeople).Count -eq 2) 'live participant list contains only connected users'
    Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$($room.room.id)/live/messages" -Headers $ankitHeaders -ContentType 'application/json' -Body (@{ body='Temporary room chat' } | ConvertTo-Json)
    $roomMessages = Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$($room.room.id)/live/messages" -Headers $rahulHeaders
    Assert-True (@($roomMessages | Where-Object { $_.body -eq 'Temporary room chat' }).Count -eq 1) 'newly joined user receives current live-session chat'
    Invoke-RestMethod -Method Delete -Uri "$ApiUrl/api/rooms/$($room.room.id)/live/leave" -Headers $ankitHeaders
    Invoke-RestMethod -Method Delete -Uri "$ApiUrl/api/rooms/$($room.room.id)/live/leave" -Headers $rahulHeaders
    $chatCount = docker compose exec -T postgres psql -U letscook -d letscook -tAc "SELECT count(*) FROM room_session_messages WHERE room_id='$($room.room.id)'"
    Assert-True ([int]$chatCount -eq 0) 'temporary room chat clears when the last user leaves'

    $waitingRoom = New-UatRoom $ankitHeaders 'UAT Waiting Room' 'KEY_ONLY' $true
    $pending = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$($waitingRoom.room.id)/unlock" `
        -Headers $priyaHeaders -ContentType 'application/json' `
        -Body (@{ accessKey = $waitingRoom.accessKey } | ConvertTo-Json)
    Assert-True (-not $pending.accessGranted -and $pending.status -eq 'PENDING') 'waiting room creates pending membership'
    $joinRequests = Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$($waitingRoom.room.id)/requests" -Headers $ankitHeaders
    Assert-True (@($joinRequests | Where-Object { $_.userId -eq $priya.id }).Count -eq 1) 'host sees the pending join request'
    Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$($waitingRoom.room.id)/requests/$($priya.id)/approve" -Headers $ankitHeaders
    $approvedMedia = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$($waitingRoom.room.id)/media-token" -Headers $priyaHeaders
    Assert-True ([bool]$approvedMedia.token) 'host approval activates the requester membership'

    $strictRoom = New-UatRoom $ankitHeaders 'UAT Strict Room' 'INVITE_AND_KEY' $false
    $strictStatus = Invoke-ExpectedError 'Post' "$ApiUrl/api/rooms/$($strictRoom.room.id)/unlock" $priyaHeaders `
        (@{ accessKey = $strictRoom.accessKey } | ConvertTo-Json)
    Assert-True ($strictStatus -eq 403) 'invite-and-key room rejects key-only access'

    $deleteRoom = New-UatRoom $ankitHeaders 'UAT Unique Delete Room' 'KEY_ONLY' $false
    $duplicateBody = @{ name = '  uat unique delete room  '; description = 'duplicate'; accessPolicy = 'KEY_ONLY'; approvalRequired = $false; maxMembers = 10 } | ConvertTo-Json
    $duplicateStatus = Invoke-ExpectedError 'Post' "$ApiUrl/api/rooms" $rahulHeaders $duplicateBody
    Assert-True ($duplicateStatus -eq 409) 'room names are unique regardless of case or surrounding spaces'
    $nonOwnerDeleteStatus = Invoke-ExpectedError 'Delete' "$ApiUrl/api/rooms/$($deleteRoom.room.id)" $rahulHeaders
    Assert-True ($nonOwnerDeleteStatus -eq 403) 'non-owner cannot delete a room'
    Invoke-RestMethod -Method Delete -Uri "$ApiUrl/api/rooms/$($deleteRoom.room.id)" -Headers $ankitHeaders
    $deletedStatus = Invoke-ExpectedError 'Post' "$ApiUrl/api/rooms/$($deleteRoom.room.id)/media-token" $ankitHeaders
    Assert-True ($deletedStatus -eq 403 -or $deletedStatus -eq 404) 'owner permanently deletes the room'

    docker compose exec -T postgres psql -U letscook -d letscook -c "DELETE FROM friendships WHERE (requester_id = '$($ankit.id)' AND addressee_id = '$($rahul.id)') OR (requester_id = '$($rahul.id)' AND addressee_id = '$($ankit.id)' )" | Out-Null
    Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/social/friend-requests/$($rahul.id)" -Headers $ankitHeaders
    $friendRequests = Invoke-RestMethod -Uri "$ApiUrl/api/social/friend-requests" -Headers $rahulHeaders
    $friendRequest = @($friendRequests | Where-Object { $_.userId -eq $ankit.id })[0]
    Assert-True ([bool]$friendRequest.id) 'recipient sees an incoming friend request'
    Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/social/friend-requests/$($friendRequest.id)/accept" -Headers $rahulHeaders
    $friends = Invoke-RestMethod -Uri "$ApiUrl/api/social/friends" -Headers $ankitHeaders
    Assert-True (@($friends | Where-Object { $_.id -eq $rahul.id -and $_.online }).Count -eq 1) 'accepted friend appears with online presence'
    Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/social/messages/$($rahul.id)" -Headers $ankitHeaders -ContentType 'application/json' -Body (@{ body = 'UAT direct message' } | ConvertTo-Json)
    $messages = Invoke-RestMethod -Uri "$ApiUrl/api/social/messages/$($ankit.id)" -Headers $rahulHeaders
    Assert-True (@($messages | Where-Object { $_.body -eq 'UAT direct message' }).Count -eq 1) 'friends can send and receive direct messages'
    Write-Output 'All automated UAT checks passed.'
} finally {
    foreach ($roomId in $roomIds) {
        docker compose exec -T postgres psql -U letscook -d letscook -v ON_ERROR_STOP=1 `
            -c "DELETE FROM rooms WHERE id = '$roomId'" | Out-Null
    }
    if ($ankit -and $rahul) {
        docker compose exec -T postgres psql -U letscook -d letscook `
            -c "DELETE FROM direct_messages WHERE (sender_id = '$($ankit.id)' AND recipient_id = '$($rahul.id)') OR (sender_id = '$($rahul.id)' AND recipient_id = '$($ankit.id)')" | Out-Null
        docker compose exec -T postgres psql -U letscook -d letscook `
            -c "DELETE FROM friendships WHERE (requester_id = '$($ankit.id)' AND addressee_id = '$($rahul.id)') OR (requester_id = '$($rahul.id)' AND addressee_id = '$($ankit.id)')" | Out-Null
    }
    if ($roomIds.Count -gt 0) { Write-Output 'Temporary UAT rooms cleaned.' }
}

