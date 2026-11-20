# XYNK — Flow Reviews

End-to-end review of each functionality, produced by tracing the codebase across
frontend (Angular), backend (Spring Boot), and infra (compose / Keycloak / LiveKit).

| File | Functionality | Verdict |
|---|---|---|
| [01-auth-flow.md](01-auth-flow.md) | Login / JWT / Keycloak / native Google / WS auth | Works, but loose edges (no `aud` check, dead X IdP) |
| [02-room-lifecycle.md](02-room-lifecycle.md) | Create / discover / join / invites / roles / live presence | Solid, one settings-coercion bug |
| [03-watch-queue-sync.md](03-watch-queue-sync.md) | Queue, voting, skip, STOMP playback sync | Good design, real race conditions |
| [04-media-search-resolve.md](04-media-search-resolve.md) | YouTube search + web-page → stream resolver | Works; SSRF TOCTOU + stale signed URLs |
| [05-frontend-app.md](05-frontend-app.md) | SPA structure, services, polling | Single-component mega-app; heavy polling |
| [06-infra-compose.md](06-infra-compose.md) | compose topology, secrets, Keycloak realm, schema | Dev-grade hardening needed before public |
| [07-video-player.md](07-video-player.md) | YouTube IFrame + direct MP4/HLS player & sync UX | **Good sync core, wasteful player lifecycle** |

Each file follows the same shape: **How it works → What's good → Issues (severity,
file:line) → Verdict**.
