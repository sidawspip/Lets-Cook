# Xynk

A synchronized watch-party platform for enjoying YouTube videos together, with private rooms, shared queues, chat, voice, presence, and host-controlled playback.

## Project layout

Each application has its own build file, source tree, and README. Open [`XYNK.code-workspace`](XYNK.code-workspace) in VS Code to see them as separate projects.

| Project | Directory | Build entry point | Local launcher |
| --- | --- | --- | --- |
| Backend API | [`backend/`](backend/) | `backend/pom.xml` (Spring Boot) | `backend/scripts/dev/run.ps1` |
| Web app | [`frontend/`](frontend/) | `frontend/package.json` (Angular) | `frontend/scripts/dev/run.ps1` |
| Android app | [`mobile/`](mobile/) | `mobile/pubspec.yaml` (Flutter) | `mobile/scripts/dev/run.ps1` |
| Windows app | [`windows_app/`](windows_app/) | `windows_app/pubspec.yaml` (Flutter) | `windows_app/scripts/dev/run.ps1` |

Each client also has a `build.ps1`: `frontend/scripts/prod/build.ps1` for web assets, `mobile/scripts/prod/build.ps1` for an APK, and `windows_app/scripts/prod/build.ps1` for the Windows EXE. The native build scripts accept API, auth, and app URLs through parameters or a local ignored `build-config.psd1`; tracked `build-config.example.psd1` files show the defaults.

Shared deployment files live in `infra/` and the root `compose*.yaml` files. Each project has `scripts/dev/` and `scripts/prod/` for its own commands; root `scripts/README.md` is the command index. `docs/` contains architecture and UAT guides. Local build output and reverse-engineering artifacts are Git ignored.

Backend, web, and Keycloak have Dockerfiles. Android and Windows build as native Flutter applications. Their launchers accept `-Local` to use the laptop backend; omit it for the configured production URLs. For example, run `./mobile/scripts/dev/run.ps1 -Local` for an Android emulator or `./windows_app/scripts/dev/run.ps1 -Local` for Windows. The backend and web launchers use the shared root Compose stack.

Start `./backend/scripts/dev/run.ps1` before using either native launcher with `-Local`. Use `./frontend/scripts/dev/run.ps1` when the web app is also needed; it starts the backend through Compose.

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
.\run.ps1
```

This starts the local services, waits for readiness, builds and opens the Android and Windows debug clients, and opens <http://localhost:4200>. Start the Android emulator before running it. Preview the steps with `.\run.ps1 -DryRun`; include automated room and client checks with `.\run.ps1 -Test`. See [scripts/README.md](scripts/README.md) for skip options. The script reads the existing ignored local and private environment files; it does not create credentials. Local username/password accounts are created only when the UAT seed script is run explicitly.

Other local services:

- API: <http://localhost:8080>
- Keycloak: <http://localhost:8180> (`admin` / `admin` by default)
- LiveKit: `ws://localhost:7880`

For phone testing from cellular or any network outside the host LAN, configure
a LiveKit Cloud project and start the guarded global-UAT flow:

```powershell
.\backend\scripts\prod\configure-livekit-cloud.ps1
.\infra\scripts\dev\start-global-uat.ps1
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
.\infra\scripts\dev\start-self-hosted-internet-uat.ps1 -RouterPortsForwarded
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
.\backend\scripts\dev\seed-uat-users.ps1
.\backend\scripts\dev\run-uat.ps1
```

See [docs/UAT.md](docs/UAT.md) for credentials, social-login setup, secure same-email linking, and the manual test matrix.

