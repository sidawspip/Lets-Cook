# 05 — Frontend App (Angular SPA)

**Scope:** bootstrap, structure, services, state management, template, polling.

## How it works

- **Single-component app**: no router; `app.component.ts` (1013 lines, ~100 signals)
  holds all UI state; "routing" = signals (`mainView`, `showPublicHome`, modals).
  Only deep link: `/invite/{code}` / `?invite=` handled manually
  (`app.component.ts:173`).
- **Bootstrap:** `main.ts:6-14` news up `AuthService`, awaits Keycloak init, then
  `bootstrapApplication` with bare `provideHttpClient()` — **no interceptors, no
  central 401 handling**.
- **Services** (`core/`): `api.service` (~45 REST methods, manual Bearer),
  `auth.service` (keycloak-js), `media.service` (LiveKit voice/screen), `watch-sync.service`
  + `notification-stream.service` (**two separate STOMP connections** to the same
  `/ws`), `youtube-player.service` (YT IFrame lazy loader).
- **State sync:** 9 `setInterval` pollers run forever while authenticated — social 5 s,
  DMs 2 s, rooms 10 s, public rooms 5 s, live room 3 s, watch 20 s, queue 2.5 s,
  heartbeat 5 s, discover 2 s, **player telemetry 500 ms** (`app.component.ts:177-188`).
  All cleared in `ngOnDestroy` (:194).
- Template `app.component.html` (303 lines) owns welcome / home / room / modals.

## What's good

- Signals + zoneless-style updates are clean; intervals are tracked and cleared.
- Optimistic UI + graceful degradation everywhere (silent catch → next poll retries).
- `visibilitychange` re-sync (`app.component.ts:196-203`) is a nice touch.
- No token leakage: no logging of tokens; bearer only in headers/CONNECT.

## Issues

| Severity | Issue | Where |
|---|---|---|
| Medium | **9 eternal pollers + 2 STOMP connections + 500 ms telemetry** — constant background load on client and server; the two STOMP services could share one client | `app.component.ts:177-188`, `watch-sync.service.ts`, `notification-stream.service.ts` |
| Medium | No HTTP interceptor / 401 handling — token refresh only happens when `token()` is called per request; expired-token failures surface as generic swallowed errors | `api.service.ts:204-206`, many `catch {}` |
| Low | Settings coercion bug (see room review) | `app.component.ts:404-410` |
| Low | WEB provider is a stub in-room (just "open in in-app browser"); NETFLIX/CRUNCHYROLL/TWITCH placeholders send a raw title as `mediaId`, which the backend 400-rejects | `app.component.ts:853-857` |
| Low | Hardcoded dev hosts (`:8080`, `:8180`) mixed with HTTPS-relative paths; placeholder still says `http://localhost:4200/invite/…` | `api.service.ts:90`, `auth.service.ts:9`, `app.component.html:211` |
| Low | Logout returns a never-resolving promise (intentional, but `loggingOut()` never resets) | `auth.service.ts:50-60` (uncommitted) |
| Low | Web search simplified to Google-only; DuckDuckGo button removed — functionality regression vs previous commit | `app.component.html:161,227` |

## Verdict

**Works, but is a mega-component.** The polling-heavy model is the main cost: merge
the two STOMP clients, move queue-watch updates onto WS events (backend currently
broadcasts none for queue changes), and drop the 500 ms telemetry to ~1 s or event-
driven. Add an HTTP interceptor for token refresh + 401.
