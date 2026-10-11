# Let's Cook

A Dockerized Discord-style rooms MVP with private access keys, invites, role-aware membership, chat-ready realtime infrastructure, and LiveKit screen-sharing infrastructure.

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

Open <http://localhost:4200>. The imported development account is:

- Username: `demo`
- Password: `demo`

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
share connects to `LIVEKIT_PUBLIC_URL`. If that value is absent, the same
on-demand media actions use the bundled local LiveKit server instead.

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

## Implemented foundation

- OIDC login through Keycloak
- Local username/password plus optional Google OAuth through Keycloak
- JWT-protected REST API
- Automatic local user profile synchronization from JWT claims
- Room creation with one-time display of a generated room access key
- Room access policies: invite, key, either, or both
- Room membership and host/co-host/member/viewer roles
- Search endpoint with PostgreSQL trigram indexes
- Dockerized PostgreSQL, Redis, Keycloak, LiveKit, backend, and frontend

LiveKit token issuance and browser screen capture are included. The next milestones are persistent chat/WebSocket events, friend requests, invite consumption, and production HTTPS/TURN deployment.

## UAT

```powershell
.\scripts\seed-uat-users.ps1
.\scripts\run-uat.ps1
```

See [docs/UAT.md](docs/UAT.md) for credentials, Google OAuth setup, secure same-email linking, and the manual test matrix.

