# 06 — Infra, Compose & Schema

**Scope:** `compose.yaml`, services, Keycloak realm + custom provider, config/secrets,
Flyway migrations, docs audit note.

## Topology

```
Cloudflare tunnel (xynk.in) → host:4200 frontend (nginx)
   ├─ /api, /ws        → backend:8080 (also published on host)
   ├─ /realms,/resources,/admin → keycloak:8180 (published)
   └─ /livekit/        → livekit:7880
backend → postgres:5432 (published, dev creds) · redis:6379 (published, NO password)
livekit → redis
override compose.self-hosted-media.yaml adds TURN 3478/udp
```

Keycloak runs a **custom image** (`infra/keycloak/Dockerfile`) adding
`lets-cook-x-email-mapper.jar` (X IdP email mapper — currently unregistered/dead).
Realm `lets-cook` imported via `--import-realm` with `${ENV}` placeholders.

## What's good

- Images pinned except one; healthchecks on postgres/redis; secrets via env files
  (gitignored, `.env.example` tracked); no secrets in tracked files (verified by grep).
- nginx does the right proxying incl. WS upgrade headers and `X-Forwarded-Proto`.
- Schema is well thought out: 28 migrations, `pg_trgm` indexes, partial unique
  indexes for queue/session invariants; V28 cleanly separates stable media id from
  expiring `source_url`.

## Issues

| Severity | Issue | Where |
|---|---|---|
| High | **Publicly tunneled but dev-grade**: Keycloak `start-dev` with bootstrap `admin/admin`; Redis published with no auth; Postgres published with dev creds | `compose.yaml` |
| High | `livekit-server:latest` **unpinned**; TURN 3478/udp exposed without credential review (possible open relay) | `compose.yaml`, `infra/livekit/livekit-public.yaml` |
| Medium | Machine-specific default `C:/Users/siddh/.letscook/secrets/native-google.env` committed | `compose.yaml:40,89` |
| Medium | `KC_PROXY_HEADERS: xforwarded` + direct host port 8180 → clients can spoof `X-Forwarded-*` | `compose.yaml` |
| Medium | `server.error.include-message: always` leaks internals; only 2 exception types mapped to problem details | `application.yml:7`, `ApiExceptionHandler` |
| Low | No healthchecks for keycloak/livekit/backend/frontend; backend waits only `service_started` | `compose.yaml` |
| Low | Frontend Dockerfile `npm install` without lockfile copy; no `.dockerignore` in backend/frontend → fat build contexts | `frontend/Dockerfile` etc. |
| Low | No CI/CD (no `.github/`); secrets are env-file based | repo root |

## Verdict

**Fine for LAN dev, not for the public tunnel.** Before exposing xynk.in:
pin livekit, put auth on redis, stop publishing DB/admin ports, remove admin/admin,
turn off `start-dev`, set `include-message: never`, and review TURN credentials.
