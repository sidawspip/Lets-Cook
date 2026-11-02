# Let's Cook

A synchronized watch-party platform for enjoying YouTube videos together, with private rooms, shared queues, chat, voice, presence, and host-controlled playback.

## Stack

- Angular 22 frontend
- Spring Boot 4 / Java 21 backend
- PostgreSQL + Flyway
- Redis
- Keycloak
- LiveKit
- Docker Compose

## Start

```powershell
Copy-Item .env.example .env
docker compose up --build
```

Open <http://localhost:4200> and sign in with Google or X. Local username/password
accounts are created only when the UAT seed script is run explicitly.

Other local services:

- API: <http://localhost:8080>
- Keycloak: <http://localhost:8180> (`admin` / `admin` by default)
- LiveKit: `ws://localhost:7880`

For phone testing from cellular or any network outside the host LAN, configure
a LiveKit Cloud project and start the guarded global-UAT flow:

```powershell
.\scripts\configure-livekit-cloud.ps1
.\scripts\start-global-uat.ps1
```

See [CLOUDFLARE_UAT.md](CLOUDFLARE_UAT.md) for the complete flow and security
notes. The ordinary Cloudflare Quick Tunnel only publishes the web application;
it does not make local WebRTC media ports globally reachable.

LiveKit is connected on demand. Joining an OTT/YouTube watch party uses the
laptop backend for presence, room chat, queues, voting, and playback sync but
does not open a LiveKit connection. Tapping microphone, room audio, or screen
share connects to the endpoint selected by `LIVEKIT_MODE`. Use `cloud` for
LiveKit Cloud, or `self-hosted`/`router` for your own server.

To keep LiveKit on the laptop instead, forward TCP `7881` and UDP `7882`/`3478`
from the router, then run:

```powershell
.\scripts\start-self-hosted-internet-uat.ps1 -RouterPortsForwarded
```

This requires a public IP and cannot bypass ISP CGNAT.

## Useful commands

```powershell
docker compose ps
docker compose logs -f backend
docker compose down
```

Use `docker compose down -v` only when you intentionally want to delete local PostgreSQL and Redis data.

## Android app

The Android-first Flutter client lives in [`mobile`](mobile). It shares the
existing Keycloak, room, synchronized-watch, queue, and chat APIs. See
[`mobile/README.md`](mobile/README.md) for production/local run commands and the
current mobile milestone.

## Documentation

- [Backend architecture and development guide](docs/BACKEND_ARCHITECTURE.md) — controller/service/repository structure, feature map, request flows, database migrations and testing.
- [Backend quick start](backend/README.md) — short build, run and code-convention reference.
- [Project flow and integrations](docs/project-flow-and-integrations/README.md) — Cloudflare, Keycloak, LiveKit and Redis setup.
- [UAT guide](docs/UAT.md) — test accounts, setup and manual validation.

## Implemented foundation

- OIDC login through Keycloak
- Local username/password plus optional Google and X login through Keycloak on web and Android
- JWT-protected REST API
- Automatic local user profile synchronization from JWT claims
- Room creation with one-time display of a generated room access key
- Room access policies: invite, key, either, or both
- Room membership and host/co-host/member/viewer roles
- Public, friends-only and invite-only room visibility
- Live presence, participants, recent people and ephemeral room chat
- Friend requests, blocking, direct messages and media attachments
- Targeted real-time room-invite and DM notifications
- Synchronized playback with revisioned room state
- Ranked, voted and deduplicated room queues
- Profile preferences, visibility, interests, connections and media gallery
- Search endpoint with PostgreSQL trigram indexes
- Dockerized PostgreSQL, Redis, Keycloak, LiveKit, backend, and frontend

LiveKit token issuance, room audio and screen sharing are included. Production HTTPS/TURN, external monitoring and managed secret rotation remain deployment concerns rather than missing application features.

## UAT

```powershell
.\scripts\seed-uat-users.ps1
.\scripts\run-uat.ps1
```

See [docs/UAT.md](docs/UAT.md) for credentials, social-login setup, secure same-email linking, and the manual test matrix.

