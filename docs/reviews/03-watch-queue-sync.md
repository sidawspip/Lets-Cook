# 03 — Watch Queue & Synchronized Playback

**Scope:** enqueue/votes/reorder → advance/skip → `room_watch_state` → STOMP broadcast →
client player sync. Backend `WatchController`/`WatchServiceImpl`/`WatchQueueServiceImpl`/
repositories + frontend `watch-sync.service.ts` + player sync in `app.component.ts`.

## How it works

- **Sync mechanism:** STOMP over `/ws` (broker `/topic`,`/queue`; app `/app`; user
  `/user`). Server broadcasts `WatchEvent{state, commandId}` to
  `/topic/rooms/{id}/watch` (`WatchServiceImpl.broadcast`, ~:325). Clients publish
  commands to `/app/rooms/{id}/watch/command` with `commandId` UUID +
  `expectedRevision` (`watch-sync.service.ts:31-35`). REST polling is the
  fallback/reconciliation: watch state every 20 s, queue every 2.5 s, host heartbeat
  every 5 s (`app.component.ts:183-185`). LiveKit is **not** used for sync.
- **State:** one `room_watch_state` row per room (PK `room_id`), monotonic `revision`,
  server-side position extrapolation (`position += elapsed*rate`), `transition_until`
  for the 8–10 s pre-roll. Commands are idempotent via `room_watch_commands` PK.
- **Queue:** `room_watch_queue` with partial unique index on
  `(room_id, provider, media_id) WHERE status='QUEUED'` (V18); dedup re-queues as a
  vote. Modes: HOSTS_ONLY / PERMISSION / VOTE. Next = most-voted candidate
  (`nextCandidates` joins votes). Skip threshold = `max(1, active/2+1)` from the 45 s
  presence window. V28 (uncommitted) adds `source_url` so the stable media identity is
  separate from the short-lived resolved stream URL.

## What's good

- Server-authoritative single-row state + revision counter + idempotent commands —
  the right model for sync.
- Partial unique index makes queue insert race-safe; votes are one-per-user (V12).
- Client-side drift threshold (>3.5 s, min 5 s between hard seeks) avoids iframe
  buffer thrash (`app.component.ts:867-872` — comment shows this was learned).
- Transition countdown lets everyone start the next video together.
- Optimistic host UI with timed revert (`app.component.ts:928-944`).

## Issues

| Severity | Issue | Where |
|---|---|---|
| High | **Check-then-act race, no locking**: `command()` validates `expectedRevision` then saves under READ_COMMITTED with no `FOR UPDATE` — two concurrent commands with the same revision both save; last writer wins | `WatchServiceImpl.java:78-106`, `WatchRepository.java:54-79` |
| High | Same race in `nextPersonalPosition` — two of a user's items can get the same `personal_position` | `WatchQueueRepository.java:169` |
| Medium | **Double broadcast on NEXT** — `playNextInternal` broadcasts, then `command` broadcasts again; client only drops `revision < current`, so equal-revision events re-apply | `WatchServiceImpl.java:89-94`, `app.component.ts:695` |
| Medium | **Skip with empty queue stops without broadcasting** — viewers learn only via the 20 s poll. No WS events at all for queue add/vote/remove/reorder (2.5 s polling) | `WatchServiceImpl.java:150-153` |
| Medium | **Stale resolved URLs**: `streamExpiry` is computed but never persisted/acted on; `takeNext` has no failure handling if a stored `source_url` expired (no re-resolve, no auto-skip); frontend sends the volatile signed CDN URL as `mediaId`, so the V28 identity/URL split isn't actually used by the web flow | `WatchQueueServiceImpl`, `app.component.ts:750,612` |
| Medium | Skip votes never cleared (`room_watch_skip_votes` keyed by media_id) — re-queued media inherits old votes | V11 schema |
| Medium | Client-supplied `sourceUrl` is only scheme+host validated, then pushed to every member's player | `WatchQueueServiceImpl.java:212` |
| Low | `room_watch_commands` grows unbounded (only `created_at` index, no cleanup job); `reorder` = N single-row updates; `item()` re-runs the full queue query | `WatchQueueRepository` |
| Low | Dead code: `isRoomCandidate`, `expandMobileTemplate`, unreachable 409 branch in `takeNext` (PLAYABLE==QUEUE providers), duplicate javadoc | `WatchQueueRepository.java`, `WebMediaResolverRepository.java:199` |
| Low | Two writers of `room_watch_state`: queue `takeNext` and direct `PUT /watch` (no markPlayed/dedup) | `WatchServiceImpl.java:60` |

## Verdict

**Design is good, concurrency is not.** Add `SELECT ... FOR UPDATE` (or optimistic
revision rejection via conditional UPDATE) on `room_watch_state`, broadcast on every
state change including stop, and persist/act on `streamExpiry` (re-resolve + auto-skip
on failure).
