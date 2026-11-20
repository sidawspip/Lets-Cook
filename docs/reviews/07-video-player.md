# 07 — Video Player Review (verdict included)

**Scope:** the in-room player: YouTube IFrame player, direct MP4/HLS `<video>` player,
custom controls, and the sync logic that drives them.
Files: `frontend/src/app/core/youtube-player.service.ts`,
`frontend/src/app/app.component.ts:855-967`, `app.component.html:151-156`.

## Architecture

One surface, `#youtubeSurface` (`app.component.html:155`), hosting one of:

- **YouTube IFrame API player** for `provider==='YOUTUBE'`
  (`youtube-player.service.ts:29-36`: `controls:0, disablekb:1, rel:0, playsinline:1,
  origin:location.origin`, custom controls rendered over it).
- **Native `<video>` + lazy hls.js** for `DIRECT_MP4` / `DIRECT_HLS`
  (`app.component.ts:881-890`; Safari native HLS via `canPlayType`).
- **Nothing** for `WEB` (stub: "open this in the in-app browser").

Server state (`room_watch_state`: provider, mediaId, sourceUrl, playing,
positionSeconds, playbackRate, revision, transitionUntil) is the single source of
truth; STOMP pushes events, 20 s REST poll reconciles.

## What's good 👍

- **Sync core is well designed**: server-authoritative position with revision;
  viewers hard-seek only when drift > 3.5 s and > 5 s since last seek — the comment
  at `app.component.ts:867-868` shows they hit and fixed the "iframe buffer discards
  and looks frozen" problem. Host force-applies play/pause/seek.
- **Echo-loop prevention**: `applyingYoutubeState` guard
  (`app.component.ts:920`) stops applied state from bouncing back as commands.
- **Optimistic host controls** with 1.8 s revert timer (`:928-944`) — feels instant.
- **Autoplay-gesture handling**: `playbackNeedsGesture` overlay + `resumeSynchronizedPlayback()`
  (`:153, :861-876, :899-903`).
- **Auto-advance dedup** via `handledEndedMediaKey` (`:927`); both `onended` (YT) and
  `<video>.onended` route to `advanceAfterPlaybackEnded()`.
- **Transition countdown** (8–10 s) so the room starts the next video together
  (`:858`, `app.component.html:155`).
- **Local vs synced controls correctly separated** — volume/mute/quality/captions are
  per-device; play/pause/seek/rate are room-wide (`:842`, `:947-948`).
- Loading overlay wired to real media events (`:884`); `visibilitychange` re-sync (`:196-203`);
  hls.js only imported when needed (`:885`).

## What's not good 👎

| Severity | Issue | Where |
|---|---|---|
| **High** | **Player recreated on every sync event**: WS handler calls `syncYoutube(true)` (`:695`), and `ensureYoutubePlayer(videoId, force=true)` *destroys and rebuilds the iframe* because the `force` flag bypasses the same-video early-return (`:906-909`). Every host PLAY/PAUSE/SEEK → all viewers reload the whole video (buffer loss, flicker, position jump). Should only recreate on media change (LOAD); otherwise apply incrementally. | `app.component.ts:695, 904-912` |
| **High** | **Direct-media host controls break when WS is down**: `publishYoutubePosition` only works with `youtubePlayer` (`:956-961`); when the direct `<video>` is active the YT player is destroyed (`:884`), so the REST fallback for PLAY/PAUSE/SEEK on DIRECT_* silently no-ops. | `app.component.ts:937, 946, 955-967` vs `:881-890` |
| Medium | **No error handling on the direct player**: `<video>` has no `onerror`; if `sourceUrl` is expired (backend never re-resolves — see review 04), the launch overlay stays up forever with no message. | `app.component.ts:884` |
| Medium | Drift-correction is moot when `force=true` (see above) — the careful 3.5 s/5 s guards at `:870` are bypassed on the WS path. | `app.component.ts:870` |
| Low | 500 ms telemetry interval drives change detection forever (`:187, :951`) — drop to 1 s or event-driven `timeupdate`. | `app.component.ts:187` |
| Low | `disablekb:1` + no own keyboard shortcuts (space/k/arrows) — accessibility gap. | `youtube-player.service.ts:33` |
| Low | WS event handler refetches full state over REST even though the event already carries it (`:695` → `syncYoutube` → `api.watchState`). Use the payload, keep REST as poll only. | `app.component.ts:695, 857` |
| Low | Seek bar is host-only (`<input range>`) vs member `<progress>` — by design, but members can't scrub; fine for sync, note it. | `app.component.html:156` |
| Low | No PiP button; fullscreen via wrapper `:949`. | `app.component.html:156` |

## Verdict

**The sync design is genuinely good — the player lifecycle management is not.**
As it stands, the room "works" (state converges, drift is handled, UX is thoughtful),
but every host action currently costs each viewer a full player reload, direct-URL
playback has no failure path, and the REST fallback is broken for direct media.

**Fix order:** (1) make `syncYoutube(false)` the WS path and recreate the player only
when `mediaId` changes — then the drift thresholds actually do their job;
(2) route direct-player host actions through a WS-publish-then-REST fallback that reads
`directPlayer.currentTime`; (3) add `onerror` → show message + trigger re-resolve/skip;
(4) throttle telemetry to 1 s. After those four, this player is solid.
