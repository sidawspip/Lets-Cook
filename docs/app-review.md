# XYNK — App Review (all flows)

Date: 2026-11-04 · Reviewed across frontend (Angular), backend (Spring Boot), infra (compose/Keycloak/LiveKit).
Detail per flow lives in `docs/reviews/01..07`.

## TL;DR

The app is a coherent watch-party platform: Keycloak SSO + JWT everywhere, rooms with
key/invite/approval join, a server-authoritative watch queue synced over STOMP, YouTube
plus a web-page→stream resolver, LiveKit for voice/screen. **Architecture is sound;
execution has concurrency, freshness, and lifecycle bugs.** Nothing found is
unfixable; the list below is ordered by impact.

## Flow-by-flow

### 1. Auth — works, loose edges
PKCE S256 public client, single-JWKS pinning, bearer on REST + STOMP CONNECT, native
Google (RFC 7523) for mobile. Issues: **no `aud` validation** (any realm client's token
= full API access), wildcard `*.trycloudflare.com` issuer, fake `"native-google"`
refresh token, dead X IdP (disabled but button still shown), `admin/admin` Keycloak
bootstrap, `error.include-message: always`.

### 2. Room lifecycle — good
Clear room/live-session/watch-state split; roles enforced server-side; LiveKit token
1 h and grant-scoped. Issue: **`saveRoomSettings()` silently coerces `accessPolicy` to
OPEN/INVITE_ONLY and drops `approvalRequired`** (`app.component.ts:404-410,537`) — can
downgrade a key-protected room to open. Dead endpoints: `watch/access-request`,
`members/{id}/video-access`, `api.shareRoomVideo()`.

### 3. Watch queue & sync — good design, real races
Single-row `room_watch_state` + monotonic revision + idempotent commands + STOMP
broadcast; partial unique index makes enqueue race-safe; drift-threshold seeking.
Issues: **no row locking** on `command()`/`nextPersonalPosition` (check-then-act races,
`WatchServiceImpl.java:78-106`, `WatchQueueRepository.java:169`), double broadcast on
NEXT, skip-with-empty-queue doesn't broadcast, queue changes have no WS push (2.5 s
polling), skip votes never cleared, **expired stream URLs never re-resolved** (V28
`source_url` stored but `streamExpiry` unused).

### 4. Media search & resolve — mostly safe
YouTube Data API search (uncached, key from env); web resolver with a real SSRF guard
(HTTPS-only, port 443, private-IP rejection, redirect re-validation, 2 MB cap).
Uncommitted diff fixes a CDN suffix-match bypass (good). Issues: **DNS-rebinding
TOCTOU** (validate resolves DNS, HttpClient re-resolves), no rate limit, provider-
specific hacks inside the generic resolver, latent string-concatenated SQL in
`MediaLibraryRepository` (currently literal-only callers).

### 5. Frontend — mega-component, polling-heavy
No router; 1013-line component with ~100 signals; no HTTP interceptor/401 handling;
**9 eternal `setInterval`s + two separate STOMP connections + 500 ms telemetry**
(`app.component.ts:177-188`). Silent `catch {}` everywhere. Hardcoded dev hosts.

### 6. Infra — dev-grade behind a public tunnel
`livekit-server:latest` unpinned; Redis published with no password; Postgres with dev
creds; Keycloak `start-dev` + `admin/admin`; TURN 3478/udp review needed; committed
Windows path `C:/Users/siddh/...` as env default; no CI. Schema itself is good
(28 migrations, partial unique indexes, V28 id/URL split).

## Video player — verdict

**Sync core: good. Player lifecycle: not good.**

Good: server-authoritative position/revision via STOMP; viewers hard-seek only on
>3.5 s drift with a 5 s min interval (avoids the frozen-iframe bug); echo-loop guard;
optimistic host controls with revert; autoplay-gesture overlay; auto-advance dedup;
8–10 s group-start countdown; local vs synced controls correctly separated.

Not good:
1. **Every WS sync event recreates the entire player** — `syncYoutube(true)` from the
   WS handler (`app.component.ts:695`) + `force` bypassing the same-video early-return
   (`:906-909`) means each host pause/seek reloads the video on every viewer.
2. **Direct MP4/HLS has no error path and a broken REST fallback** — no `onerror`
   (`:884`); `publishYoutubePosition` only reads the YT player (`:956-961`) so direct-
   media host controls no-op when WS is down; expired URLs are never re-resolved.
3. Minor: 500 ms telemetry, WS events trigger redundant REST refetch, no keyboard
   shortcuts despite `disablekb:1`.

Fix order: WS path → `syncYoutube(false)`, recreate player only on media change; direct-
player REST fallback reading `directPlayer.currentTime`; `onerror` → re-resolve/skip;
telemetry → 1 s. Then it's solid.

## Top fixes (impact order)

1. Lock `room_watch_state` writes (`FOR UPDATE` / conditional update on revision) — fixes command & position races. (review 03)
2. Stop recreating the player on every sync event; recreate only on `mediaId` change. (review 07)
3. Add `aud` validation + remove trycloudflare wildcard issuer; drop `admin/admin`, put auth on Redis, pin livekit, `include-message: never`. (reviews 01, 06)
4. Fix `saveRoomSettings()` coercing access policy / approval. (review 02)
5. Close the resolver TOCTOU (IP pinning) + rate-limit `resolve-web`; persist and enforce stream expiry with re-resolve. (review 04)
6. Wire or delete dead endpoints; merge the two STOMP clients; move queue updates to WS events; add an HTTP interceptor for 401/refresh. (reviews 02, 05)
