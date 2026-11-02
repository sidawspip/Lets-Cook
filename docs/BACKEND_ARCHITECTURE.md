# Backend architecture and development guide

This guide explains how the Spring Boot backend is organized, how a request moves through the code, and where to make changes. Paths are relative to the repository root.

## The rule to remember

Every backend feature follows this dependency direction:

```text
HTTP or STOMP request
        ↓
Controller
        ↓
Service interface
        ↓
Service implementation
        ↓
Repository
        ↓
PostgreSQL or an external provider
```

Dependencies only point downward. A repository must not call a controller, and a controller must not contain SQL.

### Responsibilities by layer

| Layer | Responsible for | Must not contain |
|---|---|---|
| Controller | Routes, path/query/body parsing, validation annotations, authentication principal, HTTP response construction | SQL, room policy logic, database transactions |
| Service interface | The use cases exposed by a domain | Spring MVC annotations, SQL |
| Service implementation | Validation, permissions, orchestration, transactions spanning repository operations, push/event publication | HTTP routing, raw SQL |
| Repository | SQL, row mapping, persistence, and provider-specific data access | HTTP routing |
| Models/DTOs | Request and response shapes passed between layers | Database or HTTP calls |

The `RoomRepository` also keeps several room invariants close to its transactional writes. Callers must still use `RoomService`; controllers never access the repository directly.

## Package layout

```text
backend/src/main/java/com/letscook/platform/
├── common/   current user, profile and personal media library
├── config/   security, CORS and WebSocket configuration
├── media/    safe resolution of public web video URLs
├── room/     rooms, invitations, presence, chat, playback and queue
├── search/   global user and room search
└── social/   friends, requests, blocks, DMs and notifications
```

## Feature-to-code map

| Feature | Controller | Service | Implementation | Repository/data gateway | Models |
|---|---|---|---|---|---|
| Current authenticated user | `ProfileController` | `CurrentUserService` | `CurrentUserServiceImpl` | `CurrentUserRepository` | `CurrentUser` |
| Profile, preferences, avatar | `ProfileController` | `ProfileService` | `ProfileServiceImpl` | `ProfileRepository` | `ProfileModels` |
| Personal history, likes, gallery | `MediaLibraryController` | `MediaLibraryService` | `MediaLibraryServiceImpl` | `MediaLibraryRepository` | `MediaLibraryModels` |
| Friends, requests, blocks and DMs | `SocialController` | `SocialService` | `SocialServiceImpl` | `SocialRepository` | `SocialModels` |
| Search | `SearchController` | `SearchService` | `SearchServiceImpl` | `SearchRepository` | `SearchModels` |
| Room lifecycle, privacy and invites | `RoomController`, `InviteController` | `RoomService` | `RoomServiceImpl` | `RoomRepository` | `RoomDtos` |
| Live presence and room chat | `LiveRoomController` | `LiveRoomService` | `LiveRoomServiceImpl` | `LiveRoomRepository` | `LiveRoomModels` |
| Synchronized playback | `WatchController` | `WatchService` | `WatchServiceImpl` | `WatchRepository`, `YoutubeCatalogRepository` | `WatchModels` |
| Queue, votes and deduplication | `WatchController` | `WatchQueueService` | `WatchQueueServiceImpl` | `WatchQueueRepository` | `WatchQueueModels` |
| Public web-video resolving | `WebMediaResolverController` | `WebMediaResolverService` | `WebMediaResolverServiceImpl` | `WebMediaResolverRepository` | Resolver request/response records |
| WebSocket room subscription access | `WatchWebSocketConfig` | Configuration interceptor | Configuration interceptor | `WebSocketAccessRepository` | STOMP headers |

All files from the table live under `backend/src/main/java/com/letscook/platform` in their corresponding package.

## Authentication flow

1. The web or Android client signs in through Keycloak.
2. Keycloak returns an access token.
3. The client sends `Authorization: Bearer <token>` to the API.
4. `SecurityConfig` verifies the JWT signature and accepted issuer.
5. A controller receives the verified `Jwt` through `@AuthenticationPrincipal`.
6. `CurrentUserService.synchronize(jwt)` maps the Keycloak subject to an `app_users` row and refreshes user claims.
7. The controller passes the resulting `CurrentUser` or user ID into the feature service.

All API routes require authentication except health/info, the WebSocket upgrade route, avatars and DM attachment downloads. STOMP authentication happens in the `CONNECT` frame, and room-topic subscriptions are checked against active membership.

## Important request flows

### Invite a user into a private room

```text
POST /api/rooms/{roomId}/invite-user/{userId}
  → RoomController
  → RoomService.inviteUser(...)
  → RoomServiceImpl
  → RoomRepository
      checks inviter membership
      checks blocks and invite restrictions
      activates the invited membership
      resolves the target Keycloak subject
  → targeted /user/queue/notifications ROOM_INVITE event
```

The invitation notification is ephemeral delivery. It is not stored as a permanent notification row. The invited membership is stored, so clicking the notification can navigate to the room and pass room authorization.

### Send a direct message

```text
POST /api/social/messages/{friendId}
  → SocialController
  → SocialService.send(...)
  → SocialServiceImpl
      requires an accepted, unblocked friendship
  → SocialRepository inserts direct_messages
  → targeted /user/queue/notifications DIRECT_MESSAGE event
```

DM history is persistent. The push event is a real-time delivery signal; the client reads the conversation from the API.

### Add and vote on a video

```text
POST /api/rooms/{roomId}/watch/queue
  → WatchController
  → WatchQueueService
  → WatchQueueServiceImpl
  → WatchQueueRepository
```

An active queue item is unique by room, provider and media ID. Adding the same video reuses the existing card. Queue ordering places the highest-voted eligible item first; the selected-user identities are returned with each card.

### Synchronize playback

The host sends playback changes through REST or STOMP. `WatchServiceImpl` verifies membership and control permissions, stores a revisioned state through `WatchRepository`, and publishes the state to `/topic/rooms/{roomId}/watch`. Clients ignore stale revisions and extrapolate playing position from the server timestamp.

## Main API groups

| Prefix | Purpose |
|---|---|
| `/api/me` | Current user, profile, preferences, visibility and avatar |
| `/api/me/media` | Personal history, likes, gallery and sensitive-content setting |
| `/api/social` | Friends, requests, blocks, DMs, attachments and notification summaries |
| `/api/search` | User and accessible-room search |
| `/api/rooms` | Room lifecycle, privacy, invitations, members and media tokens |
| `/api/rooms/{roomId}/live` | Presence, participants, recent people and room chat |
| `/api/rooms/{roomId}/watch` | Playback, commands, settings, queue, votes and skip votes |
| `/api/invites` | Accept share-code invitations |
| `/api/media` | Resolve supported public HTTPS video pages |
| `/api/youtube/search` | YouTube catalogue search |

For the exact method and request shape, start at the relevant controller. Request/response records are in that feature's `Models` or `Dtos` file.

## Database and migrations

PostgreSQL is the source of truth. Flyway migrations are in:

```text
backend/src/main/resources/db/migration/
```

Never edit a migration that has already run in a shared environment. Add a new numbered migration instead.

| Migration range | Main area |
|---|---|
| `V1`–`V5` | Users, rooms, friendships, DMs, governance and room sessions |
| `V6`–`V14` | Playback, queue, live lifecycle, recent people and real-time state |
| `V15`–`V17` | Media library, profile preferences and visibility |
| `V18` | Unique active queue media |
| `V19`–`V21` | Notification indexes, DM attachments and user blocks |

Repositories use Spring `JdbcClient`; there is no JPA entity layer. Keep SQL and row mapping inside repository classes.

## Files and external providers

- Avatars are stored below `APP_AVATAR_DIRECTORY` and served through `/api/me/avatar/{fileName}`.
- DM images/videos are stored below `APP_MESSAGE_DIRECTORY` and served through `/api/social/attachments/{fileName}`.
- `YoutubeCatalogRepository` talks to the YouTube Data API when `YOUTUBE_API_KEY` is configured.
- `WebMediaResolverRepository` only resolves public HTTPS MP4/HLS sources and rejects private-network targets. It does not bypass DRM or provider login.
- `RoomService` issues short-lived LiveKit tokens. LiveKit carries microphone/screen-share media; PostgreSQL-backed room state and chat remain in the application API.

## Adding a new backend feature

Use this order:

1. Add request/response records to the domain's `Models` or `Dtos` file.
2. Add the use-case method to the service interface.
3. Implement validation and orchestration in the service implementation.
4. Add persistence methods to the repository. Put all SQL there.
5. Add the controller route and delegate to the service.
6. Add a new Flyway migration if the schema changes.
7. Test both the allowed path and authorization failures.

Example skeleton:

```java
@RestController
class ExampleController {
    private final ExampleService service;

    ExampleController(ExampleService service) {
        this.service = service;
    }
}

interface ExampleService {
    ExampleModels.Result run(UUID userId, ExampleModels.Command command);
}

@Service
class ExampleServiceImpl implements ExampleService {
    private final ExampleRepository repository;

    ExampleServiceImpl(ExampleRepository repository) {
        this.repository = repository;
    }
}

@Repository
class ExampleRepository {
    private final JdbcClient jdbc;

    ExampleRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }
}
```

## Running and testing

Start or rebuild the complete stack:

```powershell
docker compose up -d --build
```

Rebuild only the backend after Java changes:

```powershell
docker compose build backend
docker compose up -d --force-recreate backend
```

Run the two-account core integration suite:

```powershell
.\scripts\test-core-two-accounts.ps1
```

Run the targeted STOMP invitation test:

```powershell
node .\scripts\test-notification-push.mjs
```

Useful diagnostics:

```powershell
docker compose ps
docker compose logs -f backend
```

The integration suite uses `test/test` and `demo/demo`. It covers authentication, friendship visibility, DMs, private-room access, targeted invitations, presence, room chat, playback synchronization, host permissions, queue deduplication, voting and ephemeral cleanup.

## Configuration reference

The backend reads defaults from `backend/src/main/resources/application.yml`. Important environment variables are:

| Variable | Purpose |
|---|---|
| `SPRING_DATASOURCE_URL` | PostgreSQL JDBC URL |
| `SPRING_DATASOURCE_USERNAME` / `SPRING_DATASOURCE_PASSWORD` | PostgreSQL credentials |
| `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_JWK_SET_URI` | Keycloak signing-key endpoint |
| `APP_LIVEKIT_URL` | Client-visible LiveKit WebSocket URL |
| `APP_LIVEKIT_API_KEY` / `APP_LIVEKIT_API_SECRET` | LiveKit server credentials |
| `APP_AVATAR_DIRECTORY` | Avatar storage directory |
| `APP_MESSAGE_DIRECTORY` | DM attachment storage directory |
| `YOUTUBE_API_KEY` | YouTube catalogue API key |

Do not commit real production credentials. Keep environment-specific values in `.env` or the deployment secret manager.
