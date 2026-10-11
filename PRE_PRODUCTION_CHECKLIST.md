# Let's Cook — Pre-production checklist

The application currently runs over development HTTP. Production requires a separate, properly managed HTTPS deployment.

## Files that must be updated

| File | Required production change |
| --- | --- |
| `compose.yaml` | Add production TLS/networking, replace development commands/default secrets, and use production networking. |
| `frontend/nginx.conf` | Add the production hostname, trusted certificate strategy, redirects, proxy routes, and security headers. |
| `frontend/src/app/core/auth.service.ts` | Load the production Keycloak URL from environment/runtime configuration. |
| `frontend/src/app/core/api.service.ts` | Load the production API URL from environment/runtime configuration. |
| `frontend/src/app/core/media.service.ts` | Load the production LiveKit WSS URL from environment/runtime configuration. |
| `backend/src/main/java/com/letscook/platform/config/SecurityConfig.java` | Replace LAN issuers and CORS origins with exact production values. |
| `infra/keycloak/realm-export.json` | Replace UAT redirect URIs, origins, demo users, and OAuth placeholders. |
| `infra/livekit/livekit.yaml` | Replace the LAN node IP and configure production RTC/TURN networking. |
| `.env` or deployment secrets | Supply unique database, Keycloak, LiveKit, and Google OAuth secrets. |

## 1. Domain and TLS

- Choose production hostnames, for example `app.example.com` and `auth.example.com`.
- Use certificates from a publicly trusted certificate authority with automated renewal.
- Configure TLS termination through a production load balancer, ingress, or hardened reverse proxy.
- Redirect all production HTTP traffic to HTTPS.
- Add HSTS and appropriate security headers after HTTPS is verified.

## 2. Frontend runtime configuration

- Replace hostname/port inference in `auth.service.ts`, `api.service.ts`, and `media.service.ts` with production environment or runtime configuration.
- Configure the final public OAuth, API, and LiveKit URLs.
- Remove the LAN-specific authentication error text.
- Build Angular using the production configuration and enforce bundle budgets.

## 3. Keycloak

- Replace `start-dev` with Keycloak production mode (`start`).
- Configure Keycloak's public hostname and reverse-proxy settings for the real domain.
- Replace redirect URIs and web origins with exact production HTTPS origins.
- Remove `http://localhost:4200`, `http://192.168.0.3:4200`, and `https://192.168.0.3:4443` from the production client.
- Configure the real Google OAuth client ID, secret, callback URL, and consent screen.
- Disable direct-access password grants unless they are explicitly required.
- Disable the client's deprecated **Full scope allowed** setting and assign only required scopes.
- Create non-default administrator credentials and enable administrator MFA.

## 4. Backend security

- Replace the issuer allowlist in `SecurityConfig.java` with only the production HTTPS issuer.
- Replace the CORS allowlist with only the production frontend origin.
- Move all secrets to a managed secret store; do not use Compose defaults.
- Rotate database, Keycloak, LiveKit, and OAuth secrets before launch.
- Add rate limiting, request-size limits, security headers, audit logging, and centralized error monitoring.
- Verify authorization tests for owner, co-host, moderator, member, and non-member roles.

## 5. LiveKit and screen sharing

- Deploy LiveKit using a stable public hostname and trusted TLS.
- Replace `node_ip: 192.168.0.3` with the production-reachable node address.
- Configure TURN/TLS for users behind restrictive NATs and mobile networks.
- Open only the documented LiveKit TCP/UDP ports at the firewall.
- Load-test rooms, reconnection, simultaneous publishers, and screen-share permission changes.

## 6. Infrastructure and data

- Do not expose PostgreSQL or Redis directly to the public internet.
- Use managed or hardened PostgreSQL and Redis with authentication, encryption, backups, and restore tests.
- Pin container image versions and avoid `latest` tags.
- Add health checks, resource limits, restart policies, rolling deployment, and monitoring.
- Run database migrations as a controlled deployment step.
- Define retention and deletion policies for accounts, room records, messages, and logs.

## 7. Release verification

- Run automated backend, frontend, integration, and browser tests in CI.
- Test Google login and password login resolving to the same account when emails match under the approved account-linking policy.
- Test desktop Chrome screen sharing and supported mobile viewer behavior.
- Test invitations, keys, waiting-room approvals, room deletion, temporary chat deletion, friends, messages, presence, and host controls.
- Perform dependency, container, secret, and application security scans.
- Complete a staging test using production-like domains and certificates before deploying production.
