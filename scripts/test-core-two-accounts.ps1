param(
    [string]$KeycloakUrl = 'http://localhost:8180',
    [string]$ApiUrl = 'http://localhost:8080',
    [string]$Realm = 'lets-cook',
    [int]$PushObservationSeconds = 25
)

$ErrorActionPreference = 'Stop'
$roomId = $null
$demoHeaders = $null
$testHeaders = $null
$directMessageIds = [System.Collections.Generic.List[string]]::new()
$mediaLibraryId = $null

function Get-Token([string]$Username, [string]$Password) {
    $response = Invoke-RestMethod -Method Post `
        -Uri "$KeycloakUrl/realms/$Realm/protocol/openid-connect/token" `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body @{
            client_id = 'lets-cook-web'
            grant_type = 'password'
            username = $Username
            password = $Password
        }
    return $response.access_token
}

function Headers([string]$Token) {
    return @{ Authorization = "Bearer $Token" }
}

function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    Write-Output "PASS: $Name"
}

function Expected-Status(
    [string]$Method,
    [string]$Uri,
    [hashtable]$RequestHeaders,
    [string]$Body = $null
) {
    try {
        $parameters = @{
            Method = $Method
            Uri = $Uri
            Headers = $RequestHeaders
        }
        if ($null -ne $Body) {
            $parameters.ContentType = 'application/json'
            $parameters.Body = $Body
        }
        Invoke-WebRequest @parameters | Out-Null
        return 200
    } catch {
        if ($null -eq $_.Exception.Response) { throw }
        return [int]$_.Exception.Response.StatusCode
    }
}

try {
    $testHeaders = Headers (Get-Token 'test' 'test')
    $demoHeaders = Headers (Get-Token 'demo' 'demo')
    $testUser = Invoke-RestMethod -Uri "$ApiUrl/api/me" -Headers $testHeaders
    $demoUser = Invoke-RestMethod -Uri "$ApiUrl/api/me" -Headers $demoHeaders
    Assert-True ($testUser.username -eq 'test' -and $demoUser.username -eq 'demo') 'test/test and demo/demo authenticate'
    Assert-True ($testUser.id -ne $demoUser.id) 'both accounts map to different users'

    $testFriends = @(Invoke-RestMethod -Uri "$ApiUrl/api/social/friends" -Headers $testHeaders)
    $demoFriends = @(Invoke-RestMethod -Uri "$ApiUrl/api/social/friends" -Headers $demoHeaders)
    Assert-True (@($testFriends | Where-Object { $_.id -eq $demoUser.id }).Count -eq 1) 'Demo User appears in Test User friends'
    Assert-True (@($demoFriends | Where-Object { $_.id -eq $testUser.id }).Count -eq 1) 'Test User appears in Demo User friends'

    $mediaLibraryId = "library-independence-$([Guid]::NewGuid().ToString('N'))"
    Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/me/media/history" -Headers $testHeaders `
        -ContentType 'application/json' -Body (@{
            mediaId = $mediaLibraryId; provider = 'YOUTUBE'; title = 'Library independence test'
            thumbnailUrl = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'; watchSeconds = 2
        } | ConvertTo-Json) | Out-Null
    Invoke-RestMethod -Method Put -Uri "$ApiUrl/api/me/media/like" -Headers $testHeaders `
        -ContentType 'application/json' -Body (@{ mediaId = $mediaLibraryId; enabled = $true } | ConvertTo-Json) | Out-Null
    Invoke-RestMethod -Method Delete `
        -Uri "$ApiUrl/api/me/media/history?mediaId=$([Uri]::EscapeDataString($mediaLibraryId))" `
        -Headers $testHeaders | Out-Null
    $mediaDashboard = Invoke-RestMethod -Uri "$ApiUrl/api/me/media" -Headers $testHeaders
    Assert-True (-not ($mediaDashboard.history.mediaId -contains $mediaLibraryId)) 'removing history hides the video from History'
    Assert-True ($mediaDashboard.likes.mediaId -contains $mediaLibraryId) 'removing history preserves the independent Like'

    $marker = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $testToDemoText = "Core test $marker from test to demo"
    $testToDemo = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/social/messages/$($demoUser.id)" `
        -Headers $testHeaders -ContentType 'application/json' `
        -Body (@{ body = $testToDemoText } | ConvertTo-Json)
    $directMessageIds.Add($testToDemo.id)
    $demoConversation = @(Invoke-RestMethod -Uri "$ApiUrl/api/social/messages/$($testUser.id)" -Headers $demoHeaders)
    Assert-True (@($demoConversation | Where-Object { $_.id -eq $testToDemo.id -and $_.body -eq $testToDemoText }).Count -eq 1) 'demo receives a DM from test'

    $demoToTestText = "Core test $marker from demo to test"
    $demoToTest = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/social/messages/$($testUser.id)" `
        -Headers $demoHeaders -ContentType 'application/json' `
        -Body (@{ body = $demoToTestText } | ConvertTo-Json)
    $directMessageIds.Add($demoToTest.id)
    $testConversation = @(Invoke-RestMethod -Uri "$ApiUrl/api/social/messages/$($demoUser.id)" -Headers $testHeaders)
    Assert-True (@($testConversation | Where-Object { $_.id -eq $demoToTest.id -and $_.body -eq $demoToTestText }).Count -eq 1) 'test receives a DM from demo'

    $roomName = "Core Both $marker"
    $created = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms" -Headers $demoHeaders `
        -ContentType 'application/json' -Body (@{
            name = $roomName
            description = 'Temporary two-account core test'
            accessPolicy = 'INVITE_ONLY'
            approvalRequired = $false
            maxMembers = 10
            visibility = 'PRIVATE'
            ephemeral = $true
        } | ConvertTo-Json)
    $roomId = $created.room.id
    Assert-True ($created.room.accessPolicy -eq 'INVITE_ONLY' -and $created.room.visibility -eq 'PRIVATE') 'demo creates a private invite-only room'
    Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/live/join" -Headers $demoHeaders | Out-Null
    Assert-True $true 'demo enters the room before inviting test'

    foreach ($audience in @(
        @{ Visibility = 'PUBLIC'; Policy = 'OPEN'; Label = 'public' },
        @{ Visibility = 'FRIENDS'; Policy = 'OPEN'; Label = 'friends-only' },
        @{ Visibility = 'PRIVATE'; Policy = 'INVITE_ONLY'; Label = 'invite-only' }
    )) {
        Invoke-RestMethod -Method Patch -Uri "$ApiUrl/api/rooms/$roomId/settings" `
            -Headers $demoHeaders -ContentType 'application/json' -Body (@{
                visibility = $audience.Visibility
                accessPolicy = $audience.Policy
                approvalRequired = $false
            } | ConvertTo-Json) | Out-Null
        $updatedRoom = @(Invoke-RestMethod -Uri "$ApiUrl/api/rooms" -Headers $demoHeaders) |
            Where-Object { $_.id -eq $roomId } | Select-Object -First 1
        Assert-True ($updatedRoom.visibility -eq $audience.Visibility -and $updatedRoom.accessPolicy -eq $audience.Policy) `
            "host can set the room to $($audience.Label)"
    }

    $testRoomsBefore = @(Invoke-RestMethod -Uri "$ApiUrl/api/rooms" -Headers $testHeaders)
    $testPublicBefore = @(Invoke-RestMethod -Uri "$ApiUrl/api/rooms/public-live" -Headers $testHeaders)
    $encodedRoomName = [Uri]::EscapeDataString($roomName)
    $testSearchBefore = Invoke-RestMethod -Uri "$ApiUrl/api/search?q=$encodedRoomName" -Headers $testHeaders
    Assert-True (@($testRoomsBefore | Where-Object { $_.id -eq $roomId }).Count -eq 0) 'test cannot see the room before invitation'
    Assert-True (@($testPublicBefore | Where-Object { $_.id -eq $roomId }).Count -eq 0) 'private room is absent from public discovery'
    Assert-True (@($testSearchBefore.rooms | Where-Object { $_.id -eq $roomId }).Count -eq 0) 'private room is absent from search'
    $blockedStatus = Expected-Status 'Post' "$ApiUrl/api/rooms/$roomId/media-token" $testHeaders
    Assert-True ($blockedStatus -eq 403) 'test cannot enter before invitation'

    $initialWatch = Invoke-RestMethod -Method Put -Uri "$ApiUrl/api/rooms/$roomId/watch" `
        -Headers $demoHeaders -ContentType 'application/json' -Body (@{
            provider = 'YOUTUBE'
            sourceType = 'YOUTUBE'
            mediaId = 'dQw4w9WgXcQ'
            sourceUrl = $null
            title = 'Core sync test video'
            playing = $true
            positionSeconds = 7.0
            durationSeconds = 213.0
            playbackRate = 1.0
        } | ConvertTo-Json)
    Assert-True ($initialWatch.mediaId -eq 'dQw4w9WgXcQ' -and $initialWatch.playing) 'demo starts synchronized room playback'

    Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/invite-user/$($testUser.id)" `
        -Headers $demoHeaders -ContentType 'application/json' -Body '{}' | Out-Null
    Write-Output "PUSH_WINDOW: demo invited test to room $roomId; observing Android for $PushObservationSeconds seconds"
    # Ephemeral rooms are intentionally omitted after their 45-second live
    # presence expires. Keep the simulated host alive while a human/emulator
    # observes and opens the notification, just as the running app does.
    $remainingObservation = $PushObservationSeconds
    while ($remainingObservation -gt 0) {
        $slice = [Math]::Min(10, $remainingObservation)
        Start-Sleep -Seconds $slice
        Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/live/heartbeat" `
            -Headers $demoHeaders -ContentType 'application/json' -Body '{}' | Out-Null
        $remainingObservation -= $slice
    }

    $testRoomsAfter = @(Invoke-RestMethod -Uri "$ApiUrl/api/rooms" -Headers $testHeaders)
    Assert-True (@($testRoomsAfter | Where-Object {
        $_.id -eq $roomId -and $_.accessPolicy -eq 'INVITE_ONLY' -and $_.visibility -eq 'PRIVATE'
    }).Count -eq 1) 'invited test account sees the private room with correct policy'

    $testMedia = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/media-token" -Headers $testHeaders
    Assert-True ([bool]$testMedia.token -and -not $testMedia.canPublish) 'invited test account receives a viewer media token'

    Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/live/join" -Headers $testHeaders | Out-Null
    $participants = @(Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$roomId/live/participants" -Headers $demoHeaders)
    Assert-True (@($participants | Where-Object { $_.userId -eq $demoUser.id }).Count -eq 1) 'demo is present in the live room'
    Assert-True (@($participants | Where-Object { $_.userId -eq $testUser.id }).Count -eq 1) 'test is present in the live room'
    $joinedTimeline = @(Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$roomId/live/messages" -Headers $demoHeaders)
    Assert-True (@($joinedTimeline.type | Where-Object { $_ -eq 'JOIN' }).Count -ge 2) 'room timeline includes participant join events'
    $memberSettingsStatus = Expected-Status 'Patch' "$ApiUrl/api/rooms/$roomId/settings" $testHeaders `
        (@{ visibility = 'PUBLIC'; accessPolicy = 'OPEN'; approvalRequired = $false } | ConvertTo-Json)
    Assert-True ($memberSettingsStatus -eq 403) 'non-host cannot change the room audience'

    $testWatch = Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$roomId/watch" -Headers $testHeaders
    Assert-True ($testWatch.mediaId -eq $initialWatch.mediaId -and $testWatch.playing -and $testWatch.positionSeconds -ge 7) 'test receives the synchronized playing state'
    $memberControlStatus = Expected-Status 'Put' "$ApiUrl/api/rooms/$roomId/watch" $testHeaders `
        (@{
            provider = 'YOUTUBE'; sourceType = 'YOUTUBE'; mediaId = 'dQw4w9WgXcQ'
            title = 'Unauthorized update'; playing = $false; positionSeconds = 0; playbackRate = 1
        } | ConvertTo-Json)
    Assert-True ($memberControlStatus -eq 403) 'non-host cannot overwrite synchronized playback'

    $demoRoomText = "Room test $marker from demo"
    $demoRoomMessage = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/live/messages" `
        -Headers $demoHeaders -ContentType 'application/json' -Body (@{ body = $demoRoomText } | ConvertTo-Json)
    $testRoomMessages = @(Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$roomId/live/messages" -Headers $testHeaders)
    Assert-True (@($testRoomMessages | Where-Object { $_.id -eq $demoRoomMessage.id }).Count -eq 1) 'test receives demo room chat'

    $testRoomText = "@demo Room reply $marker from test"
    $testRoomMessage = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/live/messages" `
        -Headers $testHeaders -ContentType 'application/json' `
        -Body (@{ body = $testRoomText; replyToId = $demoRoomMessage.id } | ConvertTo-Json)
    $demoRoomMessages = @(Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$roomId/live/messages" -Headers $demoHeaders)
    Assert-True (@($demoRoomMessages | Where-Object { $_.id -eq $testRoomMessage.id }).Count -eq 1) 'demo receives test room chat'
    Assert-True ($testRoomMessage.replyTo.id -eq $demoRoomMessage.id -and $testRoomMessage.body -like '@demo*') 'room reply retains quoted message and mention tag'
    $reactedMessage = Invoke-RestMethod -Method Post `
        -Uri "$ApiUrl/api/rooms/$roomId/live/messages/$($testRoomMessage.id)/reactions" `
        -Headers $demoHeaders -ContentType 'application/json' -Body (@{ reaction = '🔥' } | ConvertTo-Json)
    Assert-True (@($reactedMessage.reactions | Where-Object { $_.reaction -eq '🔥' -and $_.count -eq 1 -and $_.reactedByMe }).Count -eq 1) 'room message reactions toggle and return viewer state'

    $queueBody = @{
        provider = 'YOUTUBE'
        mediaId = '9bZkp7q19f0'
        title = 'Core queue test video'
        thumbnailUrl = 'https://i.ytimg.com/vi/9bZkp7q19f0/hqdefault.jpg'
    } | ConvertTo-Json
    $memberQueueStatus = Expected-Status 'Post' "$ApiUrl/api/rooms/$roomId/watch/queue" $testHeaders $queueBody
    Assert-True ($memberQueueStatus -eq 403) 'host-only queue mode blocks member additions'
    $queued = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/watch/queue" `
        -Headers $demoHeaders -ContentType 'application/json' -Body $queueBody
    $duplicateQueued = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/watch/queue" `
        -Headers $demoHeaders -ContentType 'application/json' -Body $queueBody
    $testQueue = Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$roomId/watch/queue" -Headers $testHeaders
    Assert-True (@($testQueue.items | Where-Object { $_.id -eq $queued.id }).Count -eq 1) 'test sees the host queue item'
    Assert-True ($duplicateQueued.id -eq $queued.id -and @($testQueue.items | Where-Object {
        $_.provider -eq 'YOUTUBE' -and $_.mediaId -eq '9bZkp7q19f0'
    }).Count -eq 1) 'duplicate media reuses one queue card'
    Assert-True (@($testQueue.items | Where-Object { $_.id -eq $queued.id -and $_.pickers.userId -contains $demoUser.id }).Count -eq 1) 'queue exposes the host selector avatar identity'

    $secondQueueBody = @{
        provider = 'YOUTUBE'
        mediaId = 'M7lc1UVf-VE'
        title = 'Queue ranking test video'
        thumbnailUrl = 'https://i.ytimg.com/vi/M7lc1UVf-VE/hqdefault.jpg'
    } | ConvertTo-Json
    $secondQueued = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/watch/queue" `
        -Headers $demoHeaders -ContentType 'application/json' -Body $secondQueueBody
    Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/watch/queue/$($secondQueued.id)/vote" `
        -Headers $testHeaders | Out-Null
    Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/watch/queue/$($secondQueued.id)/vote" `
        -Headers $demoHeaders | Out-Null
    $rankedQueue = Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$roomId/watch/queue" -Headers $testHeaders
    Assert-True ($rankedQueue.items[0].id -eq $secondQueued.id -and $rankedQueue.items[0].voteCount -ge 2) 'highest-voted video moves to the first queue position'

    Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/watch/queue/$($queued.id)/vote" `
        -Headers $testHeaders | Out-Null
    Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/watch/queue/$($queued.id)/vote" `
        -Headers $demoHeaders | Out-Null
    $demoQueue = Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$roomId/watch/queue" -Headers $demoHeaders
    Assert-True (@($demoQueue.items | Where-Object { $_.id -eq $queued.id -and $_.voteCount -ge 2 }).Count -eq 1) 'test vote is visible to demo'
    Assert-True (@($demoQueue.items | Where-Object { $_.id -eq $queued.id -and $_.pickers.userId -contains $testUser.id }).Count -eq 1) 'queue exposes all users who selected the video'
    $nextWatch = Invoke-RestMethod -Method Post -Uri "$ApiUrl/api/rooms/$roomId/watch/queue/next" `
        -Headers $demoHeaders -ContentType 'application/json' -Body (@{ queueId = $queued.id } | ConvertTo-Json)
    $testNextWatch = Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$roomId/watch" -Headers $testHeaders
    Assert-True ($nextWatch.mediaId -eq '9bZkp7q19f0' -and $testNextWatch.mediaId -eq $nextWatch.mediaId) 'host queue selection synchronizes to test account'
    $videoTimeline = @(Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$roomId/live/messages" -Headers $testHeaders)
    Assert-True (@($videoTimeline | Where-Object { $_.type -eq 'VIDEO' -and $_.mediaId -eq '9bZkp7q19f0' }).Count -eq 1) 'room timeline records videos played in the session'

    Invoke-RestMethod -Method Delete -Uri "$ApiUrl/api/rooms/$roomId/live/leave" -Headers $testHeaders | Out-Null
    $leaveTimeline = @(Invoke-RestMethod -Uri "$ApiUrl/api/rooms/$roomId/live/messages" -Headers $demoHeaders)
    Assert-True (@($leaveTimeline | Where-Object { $_.type -eq 'LEAVE' -and $_.senderId -eq $testUser.id }).Count -eq 1) 'room timeline includes participant leave events'
    Invoke-RestMethod -Method Delete -Uri "$ApiUrl/api/rooms/$roomId/live/leave" -Headers $demoHeaders | Out-Null
    $roomChatCount = docker compose exec -T postgres psql -U letscook -d letscook -tAc `
        "SELECT count(*) FROM room_session_messages WHERE room_id='$roomId'"
    Assert-True ([int]$roomChatCount -eq 0) 'ephemeral room chat clears after both accounts leave'

    Write-Output 'RESULT: all two-account core checks passed.'
} finally {
    if ($roomId -and $demoHeaders) {
        try {
            Invoke-RestMethod -Method Delete -Uri "$ApiUrl/api/rooms/$roomId" -Headers $demoHeaders | Out-Null
        } catch {
            docker compose exec -T postgres psql -U letscook -d letscook -v ON_ERROR_STOP=1 `
                -c "DELETE FROM rooms WHERE id='$roomId'" | Out-Null
        }
    }
    if ($directMessageIds.Count -gt 0) {
        $quotedIds = ($directMessageIds | ForEach-Object { "'$_'" }) -join ','
        docker compose exec -T postgres psql -U letscook -d letscook -v ON_ERROR_STOP=1 `
            -c "DELETE FROM direct_messages WHERE id IN ($quotedIds)" | Out-Null
    }
    if ($mediaLibraryId -and $testUser) {
        docker compose exec -T postgres psql -U letscook -d letscook -v ON_ERROR_STOP=1 `
            -c "DELETE FROM user_media_history WHERE user_id='$($testUser.id)' AND media_id='$mediaLibraryId'" | Out-Null
    }
    if ($roomId) { Write-Output "CLEANUP: removed temporary room $roomId and test messages." }
}
