# 04 — Media Search & Web Resolution

**Scope:** YouTube search → room; web page URL → server-side resolve → DIRECT_MP4/HLS
→ queue/play; history persistence.

## How it works

1. **YouTube search:** `GET /api/youtube/search?q=&pageToken=` → `WatchController.java:164`
   → `YoutubeCatalogRepository.java:30-82` → two YouTube Data API v3 calls
   (`search` + `videos` for durations), filters Shorts, caps at 20. API key from env
   `YOUTUBE_API_KEY` (`application.yml:59-60`) — no hardcoded key anywhere. Each
   debounced keystroke costs up to 100+ quota units (no caching).
2. **Web resolve:** `POST /api/media/resolve-web {pageUrl}` →
   `WebMediaResolverRepository.resolve()` (:59-101): HTTPS-only, port 443,
   DNS-resolved private/loopback/link-local rejection (SSRF guard :219-233),
   manual redirect loop ≤3 with re-validation, 2 MB HTML cap, regex extraction of
   mp4/m3u8 from og:video / `<video>` / JSON, ad-host denylist + xhamster CDN
   allowlist, mobile-quality ranking → `ResolvedWebMedia{sourceUrl, sourceType,
   streamExpiry, sources[]}`.
3. **Queue/play:** resolved media enqueued like any provider; V28 stores `source_url`;
   history via `user_media_history` (V15, V26 canonicalizes rotating CDN URLs).

## What's good

- SSRF guard is genuinely thoughtful (DNS pinning attempt, redirect re-validation,
  size cap, timeouts).
- The uncommitted diff **fixes a real vuln**: xhamster CDN match went from
  `endsWith("xhcdn.com")` (bypassable by `notxhcdn.com`) to exact/`.domain` matching,
  with a regression test (`acceptsObservedMediaCdnButRejectsLookalikeHost`).
- All repository SQL is parameterized; no injection found.
- Resolver returns ordered `sources[]` with per-source headers + expiry — good API shape.

## Issues

| Severity | Issue | Where |
|---|---|---|
| High | **DNS-rebinding TOCTOU**: `validatePublicHttps` resolves DNS once, `HttpClient` re-resolves at connect — no pinning. Plus no rate limit; any authenticated user can make the server fetch arbitrary public HTTPS URLs (2 MB each) | `WebMediaResolverRepository.java:219-233` vs `fetch` |
| Medium | **`streamExpiry` never persisted or acted on** — queue/history replay can hand players an expired signed URL | resolver :303-322, `user_media_history` (V15) |
| Medium | Provider-specific logic (xhamster allowlist, ad blacklist, mobile-quality heuristics) baked into the generic resolver; `expandMobileTemplate` is dead code so template pages just 422 | `WebMediaResolverRepository.java:153-217` |
| Low | YouTube API key sent as URL query param (normal but lands in proxy logs); search uncached | `YoutubeCatalogRepository.java:39-51` |
| Low | `MediaLibraryRepository.java:194,202` concatenate filter/column/limit into SQL — safe only because all callers pass literals; make it non-concatenable | `MediaLibraryRepository.java` |
| Low | Dev-default secrets in config (DB `letscook_dev`, LiveKit devkey/secret) — ok only if env always overrides | `application.yml:15,54-55` |

## Verdict

**Useful and mostly safe, but close the TOCTOU hole** (pin the resolved IP or resolve
once and connect by IP with Host header/SNI care), add rate limiting, cache search
results briefly, and make expiry enforceable (re-resolve on 401/403 from the player).
