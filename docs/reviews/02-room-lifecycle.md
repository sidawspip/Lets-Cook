# 02 — Room Lifecycle

**Scope:** create → discover/search → join (key/invite) → membership & roles →
live presence → media token → leave/delete. Backend `room/` package + frontend room UI.

## How it works (endpoint map)

`RoomController` (`/api/rooms`): `GET /` list mine · `GET /public-live` · `POST /`
create · `POST /{id}/unlock` (room key) · `POST /{id}/invites` · `POST /{id}/media-token`
(LiveKit, 1 h, role-aware grants — `RoomRepository.java:475-509`) · `DELETE /{id}` ·
`GET /{id}/requests` + `POST /{id}/requests/{userId}/{decision}` · `GET /{id}/members` ·
`POST /{id}/members/{userId}/screen-permission` · `DELETE /{id}/members/{userId}` (kick) ·
`POST /{id}/invite-user/{userId}` · `POST /{id}/members/{userId}/leadership/{action}`
(co-host / transfer).

`InviteController`: `POST /api/invites/{code}/accept`.

`LiveRoomController` (`/api/rooms/{id}/live`): join / heartbeat / leave / participants /
recent-people / messages / messages/video / reactions. Presence window is 45 s
(`room_live_presence`), used by skip-vote math.

Access policies: `OPEN`, `KEY_ONLY`, `INVITE_ONLY`, `INVITE_AND_KEY` (key = bcrypt
`key_verifier`, `BCryptPasswordEncoder(12)`), plus `approvalRequired`. Frontend deep
link: `/invite/{code}` or `?invite=` (`app.component.ts:173`). Active-room restore via
`sessionStorage` (`app.component.ts:971-983`).

## What's good

- Clear separation: room (persistent) vs live session (presence/heartbeat) vs watch state.
- Role model (HOST / CO_HOST / MEMBER) enforced server-side on every mutating endpoint;
  leadership transfer + co-host promotion are explicit endpoints.
- Invite links + room keys + approval requests cover the real join scenarios; UI modal
  explains which combination is required (`app.component.html:211-214`).
- LiveKit token is short-lived (1 h) and grant-scoped (mic only for members under
  HOSTS_ONLY screen policy).
- Switching rooms while live is guarded by a confirm modal (`app.component.html:197-198`).

## Issues

| Severity | Issue | Where |
|---|---|---|
| Medium | **Settings save coerces access policy**: `saveRoomSettings()` forces `OPEN`/`INVITE_ONLY` and `approvalRequired:false`, silently dropping `KEY_ONLY`/`INVITE_AND_KEY` and approval flags; same coercion in `createRoom` | `app.component.ts:404-410, 537` |
| Medium | Queue-add permission endpoints `POST .../watch/access-request` and `POST .../members/{userId}/video-access` exist on the backend but the frontend never calls them (dead surface) | `WatchController.java:148,154` vs `api.service.ts` |
| Low | `ApiService.shareRoomVideo()` has no caller | `api.service.ts:174` |
| Low | Room name has case-insensitive unique constraint (V2) but error UX on conflict not verified | migrations V2 |
| Low | Public room listing depends on `room_live_presence` 45 s window — rooms vanish from discover quickly after everyone leaves | `RoomServiceImpl` |

## Verdict

**Good.** The lifecycle is coherent and the authz is consistently enforced at the
service layer. Fix the settings-coercion bug (it can silently downgrade a key-protected
room to open) and either wire up or delete the dead permission endpoints.
