# Security Updates Needed — Let's Cook Platform

Based on full security reconnaissance (4 agents). Each finding includes location, severity, and minimal fix.

---

## Critical (Fix Immediately)

| # | Issue | Location | Fix |
|---|-------|----------|-----|
| **C1** | **Hardcoded secrets with defaults in compose** | `compose.yaml:53-55, 66-67` | Remove all `${VAR:-default}` for secrets. Require `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `KEYCLOAK_ADMIN_PASSWORD`, `POSTGRES_PASSWORD` from env. Add startup validation in backend that fails if missing. |
| **C2** | **No rate limiting on auth/public endpoints** | `SecurityConfig.java` (missing), controllers | Add `Bucket4j` or `Resilience4j` rate limiter. Protect: `/api/auth/**`, `/api/rooms` (POST), `/api/search`, `/api/media/resolve-web`, `/ws` CONNECT. Default: 10 req/s per IP, 100 req/min per user. |
| **C3** | **SSRF in WebMediaResolver — redirect re-validation missing** | `WebMediaResolverRepository.java:63-67, 219-233` | On each redirect (up to 3), re-run `validatePublicHttps()` on new URI. Resolve DNS once, connect by IP with `Host` header. Add domain allowlist config (default: deny all, explicit allow). |
| **C4** | **JWT algorithm confusion / missing validations** | `SecurityConfig.java:49-70` | Force RS256 only: `jwtDecoder.setJwsAlgorithmResolver(token -> "RS256")`. Add clock skew: `jwtDecoder.setClockSkew(Duration.ofSeconds(30))`. Track `jti` for replay prevention (Redis set with TTL). |

---

## High (Fix This Sprint)

| # | Issue | Location | Fix |
|---|-------|----------|-----|
| **H1** | **Unauthenticated static file serving** | `ProfileController.java:61`, `SocialController.java:66` | Add `@AuthenticationPrincipal Jwt jwt` to both `GET /api/me/avatar/{fileName}` and `GET /api/social/attachments/{fileName}`. Verify ownership/access before serving. |
| **H2** | **CORS misconfiguration — production origins missing** | `SecurityConfig.java:80-83` | Replace hardcoded localhost IPs with configurable allowed origins from env (`CORS_ALLOWED_ORIGINS`). Require `allowCredentials=true` only with specific origin (never `*`). |
| **H3** | **No input validation on media URLs — domain allowlist missing** | `WatchServiceImpl.java:278-294` | Add per-provider domain allowlist config:<br/>- YouTube: `youtube.com`, `youtu.be`, `googlevideo.com`<br/>- Direct: configurable allowlist<br/>- Web: deny by default, explicit allow only<br/>Reject URLs with non-ASCII, >2048 chars, suspicious patterns. |
| **H4** | **File upload — magic bytes only, no Content-Type enforcement on serve** | `ProfileServiceImpl.java:55-61`, `SocialServiceImpl.java:45-48, 53-54` | On upload: verify magic bytes + extension match. Store mapped extension. On serve: set `Content-Type` from stored extension, add `Content-Disposition: attachment` for avatars/attachments, `X-Content-Type-Options: nosniff`. |
| **H5** | **STOMP WebSocket — no token refresh mid-session** | `WatchWebSocketConfig.java:48-76` | On CONNECT, store token expiry in session attributes. Add heartbeat interceptor that checks expiry; if < 5 min, require re-auth or send disconnect with `TOKEN_EXPIRED` code. Frontend: handle reconnect with fresh token. |
| **H6** | **Keycloak Admin API — service account has `manage-users` (full realm access)** | `realm-export.json:161-168`, `NativeGoogleAuthService.java:204-216` | Create dedicated client with fine-grained roles: `view-users`, `manage-users` (only for linking), `query-groups`. Remove `manage-realm`, `manage-clients`. Use separate client for admin scripts. |
| **H7** | **Flyway migrations run as DB owner — supply chain risk** | `backend/src/main/resources/db/migration/V*.sql` (30 files) | Review all 30 migration files for: no `EXECUTE`, no `COPY FROM PROGRAM`, no `CREATE EXTENSION` with untrusted content. Pin Flyway version. Consider read-only migration user with limited grants. |
| **H8** | **LiveKit uses `latest` tag — unpinned image** | `compose.yaml:28` | Pin to specific version: `livekit/livekit-server:v1.9.0` (or current). Update via dependabot/renovate. |

---

## Medium (Fix Next Sprint)

| # | Issue | Location | Fix |
|---|-------|----------|-----|
| **M1** | **Plaintext defaults in `.env.example`** | `.env.example` | Replace all passwords with `CHANGE_ME_<SERVICE>_STRONG_PASSWORD` placeholders. Add comment: `# Generate with: openssl rand -base64 32` |
| **M2** | **No security headers on frontend** | `frontend/nginx.conf` (missing), `compose.yaml` | Add to nginx: `Strict-Transport-Security`, `Content-Security-Policy`, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy: camera=(), microphone=(), geolocation=()` |
| **M3** | **WebMediaResolver — HTML regex parsing errors** | `WebMediaResolverRepository.java:35-52, 38-52` | Replace regex-based HTML parsing with `jsoup` (whitelist tags/attrs). Limit parse depth. Add timeout on parsing. |
| **M4** | **Google ID token exchange — no nonce/Csrf protection** | `NativeGoogleAuthService.java:70-189` | Require `nonce` in ID token (store in session during auth initiation). Verify nonce matches. Add PKCE-like state parameter for mobile flow. |
| **M5** | **Room key — BCrypt cost 12, no pepper** | `SecurityConfig.java:72-75`, `RoomRepository.java` | Add pepper (env `ROOM_KEY_PEPPER`) appended before BCrypt. Rotate pepper annually. |
| **M6** | **No audit logging for sensitive actions** | All controllers/services | Add structured audit log (JSON) for: room create/delete, role changes, invite create/revoke, video access grant, block/unblock, token exchange, media resolution. Include: `actor_id`, `action`, `resource_type`, `resource_id`, `timestamp`, `ip` (from `X-Forwarded-For`). |
| **M7** | **Avatar/message uploads — no size quota per user** | `ProfileServiceImpl.java:55-61`, `SocialServiceImpl.java:45-48` | Track per-user storage in DB. Enforce soft limit (e.g., 50MB avatars, 500MB messages) + hard limit. Background cleanup job for orphaned files. |
| **M8** | **WebSocket — no connection limit per user** | `WatchWebSocketConfig.java` | Limit concurrent STOMP connections per user (max 3). Track in Redis with TTL. |

---

## Low (Fix When Convenient)

| # | Issue | Location | Fix |
|---|-------|----------|-----|
| **L1** | **Keycloak dev mode (`start-dev`) in compose** | `compose.yaml:18` | Document: production uses `start --import-realm` with external DB. Add `KC_HEALTH_ENABLED=true` (already there). |
| **L2** | **No TURN server configured for LiveKit** | `infra/livekit/livekit.yaml`, `compose.yaml` | Add Coturn container for production. Configure `external_turn_url` in `livekit.yaml`. Document NAT traversal requirements. |
| **L3** | **Frontend derives Keycloak URL from `window.location.protocol`** | `auth.service.ts:7-9` | Move to build-time env (`AUTH_BASE_URL`). Remove runtime protocol detection. |
| **L4** | **Mobile stores tokens in `flutter_secure_storage` — no hardware-backed option** | `mobile/lib/services/lets_cook_api.dart` | Add `AndroidOptions(encryptedSharedPreferences: true)` and `IOSOptions(accessible: .whenUnlockedThisDeviceOnly)`. |
| **L5** | **No dependency scanning / SBOM generation** | Build process | Add `cyclonedx-maven-plugin` (backend), `@cyclonedx/bom` (frontend), `cyclonedx` (Flutter). Scan in CI. |
| **L6** | **Docker volumes no size limits** | `compose.yaml:112-118` | Add tmpfs for avatar/message with size limit, or use bind mounts with quota. |
| **L7** | **No `Content-Security-Policy` on Keycloak** | `infra/keycloak/` | Configure Keycloak `spi-theme-static-max-age`, `http-headers.csp`. |
| **L8** | **Pre-production checklist not automated** | `PRE_PRODUCTION_CHECKLIST.md` | Convert to CI pipeline gates (test, security scan, config validation). |

---

## Deployment Validation Required (`needs_validation`)

These cannot be verified from source — must validate in target deployment:

| # | Control | Validation Method |
|---|---------|-------------------|
| **D1** | Production TLS certificates (valid, auto-renewal) | `openssl s_client -connect <host>:443 -servername <host>`; check Let's Encrypt renewal cron |
| **D2** | Keycloak production mode (not `start-dev`) | `kubectl get pods` / `docker ps` — verify command is `start` |
| **D3** | LiveKit TURN/TLS for NAT traversal | Connect from external network; verify ICE candidates include relay |
| **D4** | Managed PostgreSQL/Redis (encryption, backups, restore tested) | Cloud provider console; run restore test quarterly |
| **D5** | Pinned container images (no `latest`) | `docker images --digests` — verify all have SHA256 digests |
| **D6** | Resource limits (CPU, memory, disk) on all containers | `docker inspect` — check `HostConfig.NanoCpus`, `Memory`, `Tmpfs` |
| **D7** | Security headers present on all responses | `curl -I https://<host>` — verify HSTS, CSP, X-Frame-Options, etc. |
| **D8** | Rate limiting active on auth endpoints | Load test: `ab -n 200 -c 10 https://<host>/api/auth/...` — verify 429 responses |
| **D9** | Secret management (no plaintext in compose/env files) | `grep -r "password\|secret\|key" compose.yaml .env*` — verify only references to secret manager |
| **D10** | Audit logs captured and immutable | Verify log shipper (Loki/Elastic/CloudWatch) receives audit events; retention ≥ 1 year |

---

## Fix Priority Order

```
Week 1:  C1, C2, C3, C4, H1, H2
Week 2:  H3, H4, H5, H6, H7, H8
Week 3:  M1, M2, M3, M4, M5, M6, M7, M8
Week 4:  L1-L8 (parallel with D1-D10 validation)
```

---

## Files to Modify (Summary)

```
Backend:
├── compose.yaml                          # C1, C2, D2, D5, D6, H8
├── .env.example                          # M1
├── SecurityConfig.java                   # C2, C4, H2, H5
├── WebMediaResolverRepository.java       # C3, M3
├── WatchServiceImpl.java                 # H3
├── ProfileController.java                # H1
├── SocialController.java                 # H1
├── ProfileServiceImpl.java               # H4, M7
├── SocialServiceImpl.java                # H4, M7
├── WatchWebSocketConfig.java             # H5, M8
├── NativeGoogleAuthService.java          # H6, M4
├── Realm export (infra/keycloak/)        # H6

Frontend:
├── nginx.conf (new)                      # M2
├── auth.service.ts                       # L3

Mobile:
├── lets_cook_api.dart                    # L4
├── pubspec.yaml                          # L5 (add cyclonedx)

Infrastructure:
├── infra/livekit/livekit.yaml            # L2
├── compose.yaml (Keycloak command)       # L1

CI/CD:
├── GitHub Actions / pipeline             # L5, D1-D10 automation
```

---

## Testing Checklist After Fixes

| Test | Command |
|------|---------|
| Rate limiting works | `ab -n 200 -c 10 -H "Authorization: Bearer <token>" http://localhost:8080/api/search?q=test` → expect 429 |
| SSRF blocked | `curl -X POST http://localhost:8080/api/media/resolve-web -H "Authorization: Bearer <token>" -d '{"pageUrl":"http://169.254.169.254/latest/meta-data/"}'` → expect 400 |
| Static files require auth | `curl http://localhost:8080/api/me/avatar/test.png` → expect 401 |
| WebSocket token expiry handled | Connect with token expiring in 30s → verify disconnect + reconnect flow |
| CORS blocks unknown origin | `curl -H "Origin: https://evil.com" -i http://localhost:8080/api/me` → no `Access-Control-Allow-Origin` |
| File upload rejects polyglot | Upload `test.php.jpg` with PHP in magic bytes → reject |
| Security headers present | `curl -I https://localhost:4200` → verify CSP, HSTS, X-Frame-Options |