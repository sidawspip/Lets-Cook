# Domain and Cloudflare setup

## Xynk domain (active)

The application is named **Xynk** and its primary public origin is
`https://xynk.in`; `https://www.xynk.in` also serves the app. GoDaddy delegates
the zone to Cloudflare nameservers `henry.ns.cloudflare.com` and
`magdalena.ns.cloudflare.com`. Both hostnames have proxied CNAMEs to the
existing named tunnel. Google and X broker callback
URLs include the new origin. Google and X sign-in reach their provider account
or authorization screens on the new domain; a complete X grant was not tested.

## Purpose

Cloudflare owns the public DNS answers and its Tunnel provides an outbound connection from the app machine to Cloudflare. This lets web traffic reach the local frontend without opening an inbound web port on the router. The Tunnel carries HTTP(S) web requests; it does not carry LiveKit's WebRTC media packets.

## Current state in this project

- Public web hostnames are `xynk.in` and `www.xynk.in`.
- DNS zone is managed in Cloudflare. The apex and `www` records are proxied CNAMEs targeting the named Tunnel's `cfargotunnel.com` hostname.
- The machine runs `cloudflared` with a named tunnel. Its configuration is at `.cloudflared/config.yml`; that path and credentials are local/ignored and must not be committed or shared.
- The tunnel forwards the Xynk hostnames to Angular/Nginx on `http://localhost:4200`.
- `frontend/nginx.conf` routes `/api/` to the backend and `/realms/`, `/resources/` and `/admin/` to Keycloak. Preserve any existing mail-related DNS records when editing DNS.

The DNS/tunnel dashboard configuration may change outside the repository. Check the Cloudflare dashboard and the local tunnel config before applying future changes.

## Traffic flow

1. A visitor opens `https://xynk.in` or `https://www.xynk.in`.
2. Cloudflare DNS resolves the hostname to the proxied Cloudflare edge.
3. The named Tunnel connects the edge request to the local service at port 4200.
4. Nginx serves the Angular app and proxies API/auth paths to their Docker services.
5. The browser continues to use HTTPS at the public hostname, including for Keycloak redirects.

## Setup and implementation references

| Step | What to configure and why | Where it is implemented |
|---|---|---|
| 1. Add the zone | `xynk.in` is delegated from GoDaddy to Cloudflare. Preserve unrelated TXT and other DNS records when editing the zone. | Cloudflare and GoDaddy dashboards; state is external to the repo |
| 2. Create tunnel | Authenticate `cloudflared`, create a named Tunnel, and install/run its connector on the host that can reach the frontend. A named tunnel provides stable hostname routing; Quick Tunnels are temporary testing URLs. | Local `.cloudflared/config.yml`; local credentials JSON; `infra/scripts/dev/start-cloudflare-uat.ps1` is the separate temporary Quick Tunnel UAT flow |
| 3. Add DNS routes | Route apex and `www` to the named tunnel target as proxied CNAMEs. Avoid replacing unrelated MX, TXT, or verification records. | Cloudflare dashboard; tunnel hostname rules in `.cloudflared/config.yml` |
| 4. Route inside app | Send `/api` to Spring Boot, and Keycloak realm/resource/admin paths to Keycloak, while serving frontend files from Nginx. | `frontend/nginx.conf` |
| 5. Set public auth URL | Keycloak must generate redirects with the public HTTPS origin. Its proxy-header and hostname settings must match the actual proxy chain. | `compose.yaml` Keycloak environment; `infra/keycloak/realm-export.json`; `frontend/src/app/core/auth.service.ts` |
| 6. Validate | Open both hostnames, inspect certificate/redirect behavior, sign in, and call an authenticated API endpoint. | `infra/scripts/dev/start-cloudflare-uat.ps1` validates the temporary UAT path; named tunnel validation is operational/manual |

## Other Cloudflare-related files and flows

- `CLOUDFLARE_UAT.md` documents the temporary Quick Tunnel, access restrictions, LiveKit choices, and cleanup. It is a UAT guide, not the named-tunnel production configuration.
- `infra/scripts/dev/start-cloudflare-uat.ps1` creates a detached Docker Quick Tunnel, discovers its temporary URL, and updates the Keycloak web client's allowed redirects/origins.
- `infra/scripts/dev/start-global-uat.ps1` wraps that Quick Tunnel flow and requires a public media endpoint for global media UAT.
- `infra/scripts/dev/start-self-hosted-internet-uat.ps1` wraps the Quick Tunnel flow with the self-hosted LiveKit Compose overlay after router port forwarding is acknowledged.
- `infra/scripts/dev/stop-cloudflare-uat.ps1` removes the temporary UAT tunnel container; it does not stop/manage the machine's named Tunnel service.
- `infra/scripts/dev/open-incognito-test-sessions.ps1` opens temporary tunnel UAT URLs for browser testing.
- `frontend/nginx.conf` is the internal reverse-proxy layer reached by Cloudflare. It is not a Cloudflare Tunnel config.
- `CLOUDFLARE_UAT.md` and the helper scripts are primarily Quick Tunnel workflows; `.cloudflared/config.yml` is the separate machine-local named Tunnel route.

## Current versus planned

**Current:** Cloudflare Tunnel publishes the web app; the tunnel config is not checked in. The UAT helper script creates a temporary Quick Tunnel and updates the Keycloak client for that temporary origin. Do not use that script as the persistent named-tunnel manager.

**Planned hardening:** run the named connector as a managed service with restart-on-boot, keep credentials in a protected machine secret store, restrict Cloudflare Access/admin paths if appropriate, and document a tested recovery procedure. Production Keycloak should use explicit public hostname/proxy settings and non-development admin credentials.

## Important boundary

The web domain being reachable does not make voice/screen sharing reachable. Browser media goes directly to LiveKit. A static IP can help with a self-hosted LiveKit endpoint, but you still need a DNS name, correct router/firewall rules, reachable UDP/TCP ports, and possibly TURN. If the ISP uses CGNAT, a purchased/static address at the router may not be available; confirm the ISP allocation and inbound connectivity first. LiveKit Cloud avoids operating that network path yourself.
