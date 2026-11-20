# 01 — Authentication Flow

**Scope:** frontend Keycloak bootstrap → OIDC login → JWT on REST + STOMP → backend
validation → Keycloak realm/infra → native Google (mobile) flow.

## How it works

1. `frontend/src/main.ts:6-11` constructs `AuthService` outside DI and awaits
   `keycloak.init({onLoad:'check-sso', pkceMethod:'S256'})` **before** the app boots.
2. `core/auth.service.ts:6-12` — public client `lets-cook-web`, realm `lets-cook`;
   Keycloak URL = same origin on HTTPS (nginx proxies `/realms` → keycloak), else
   `http://<hostname>:8180` for LAN dev. Login buttons pass `idpHint` (google/x).
3. No HTTP interceptor: `core/api.service.ts:204-206` attaches
   `Authorization: Bearer <token>` per request; `auth.service.ts:62-68` refreshes
   if <30 s remain (`updateToken(30)`).
4. WebSocket: two STOMP clients (`watch-sync.service.ts:24`,
   `notification-stream.service.ts:12`) send the Bearer token in CONNECT headers.
5. Backend: `config/SecurityConfig.java:32-47` — CSRF off, `oauth2ResourceServer(jwt)`,
   permitAll only for `/actuator/health|info`, `/ws(/**)`, `POST /api/auth/google/native`,
   `GET /api/me/avatar/**`, `GET /api/social/attachments/**`. JWT decoder = single JWKS
   URI + expiry + issuer allowlist (`SecurityConfig.java:49-70`).
6. Identity upsert: `common/CurrentUserServiceImpl.java:25-35` keys `app_users` on
   `jwt.sub`.
7. WS auth: `config/WatchWebSocketConfig.java:49-76` requires Bearer on CONNECT and
   checks active room membership on SUBSCRIBE.
8. Native Google (mobile): `auth/NativeGoogleAuthController.java` (permitAll) →
   `NativeGoogleAuthService` verifies the Google ID token against Google JWKS
   (iss + aud + email_verified), provisions/links the Keycloak user via the
   confidential `lets-cook-native-google` service account, then does the RFC 7523
   jwt-bearer grant.
9. Logout (uncommitted): `auth.service.ts:50-60` — `clearToken()` + full-page redirect
   to `createLogoutUrl`, so `signOut()`'s promise never resolves (intentional).

## What's good

- Auth code + PKCE S256 on a public client; tokens in memory only.
- Same-origin Keycloak behind nginx on prod (`frontend/nginx.conf`) — no token in URL.
- WS upgrade is permitAll at HTTP level but hard-gated by Bearer-on-CONNECT +
  per-subscription membership check — reasonable layering.
- Native Google flow verifies tokens properly and guards against linking
  differently-owned subs and unverified pre-existing accounts (409s).
- No hardcoded secrets in tracked files; realm export uses `${ENV}` placeholders.

## Issues

| Severity | Issue | Where |
|---|---|---|
| High | **No `aud` validation** — any token from any realm client (web/mobile/native) grants full API access (client confusion) | `SecurityConfig.java:66-68` |
| Medium | Issuer allowlist includes regex `*.trycloudflare.com` — fine only because one JWKS is pinned; comment it | `SecurityConfig.java:65` |
| Medium | Fake refresh token literal `"native-google"` returned to native clients | `NativeGoogleAuthService.java:187` |
| Medium | WS endpoint `setAllowedOriginPatterns("*")` | `WatchWebSocketConfig.java:44` |
| Medium | permitAll file serving `/api/me/avatar/**`, `/api/social/attachments/**` needs traversal/IDOR review | `SecurityConfig.java:42-43` |
| Medium | `error.include-message: always` leaks internal messages | `application.yml:7` |
| Low | X IdP `enabled:false` and custom `XPrivateEmailMapper` jar never registered, but UI still shows "Continue with X" | `realm-export.json`, `app.component.html:19` |
| Low | `directAccessGrantsEnabled:true` on public clients (ROPC surface) | `realm-export.json` |
| Low | Google IdP allows assertion reuse up to 3600 s | `realm-export.json` (~line 120) |
| Low | PKCE S256 impossible on plain-HTTP LAN origins → login fails there despite being allowlisted | `auth.service.ts:23-26` |
| Low | Hardcoded LAN IPs + `C:/Users/siddh/...` env path; bootstrap admin `admin/admin` | `SecurityConfig.java`, `compose.yaml:40,42-43` |

## Verdict

**Sound foundation, tighten before public launch.** The bearer + PKCE + JWKS-pinning
core is correct; the gaps are validation breadth (aud/iss), dead X-login UI, and
dev conveniences (admin/admin, trycloudflare wildcard, error message leakage).
