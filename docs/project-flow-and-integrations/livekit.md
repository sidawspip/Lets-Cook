# LiveKit setup: current and planned Internet deployment

## Purpose and traffic flow

The backend authorizes a room join and issues a short-lived LiveKit access token. The browser uses that token to connect directly to LiveKit for microphone, room audio, and screen sharing. Ordinary app requests (room data, watch-party queue and playback synchronization) continue through the backend. Cloudflare Tunnel publishes the web app but does not transport WebRTC media.

## Current repository setup

The default Compose stack runs a bundled LiveKit server. It is suitable for local development and LAN tests, not automatically for arbitrary Internet clients.

| File | Current role |
|---|---|
| `compose.yaml` | Runs `livekit/livekit-server`, exposes local signaling/media ports, loads the local LiveKit config, and gives the backend a default `ws://localhost:7880` URL and development credentials. |
| `infra/livekit/livekit.yaml` | Local/LAN config: signaling port 7880, media TCP 7881 and UDP 7882, Redis at `redis:6379`, and current LAN node IP `192.168.0.3`. |
| `compose.self-hosted-media.yaml` | Overlay that loads the public-media config and exposes UDP 3478 for TURN. |
| `infra/livekit/livekit-public.yaml` | Internet-oriented config with external-IP discovery and TURN UDP enabled. This config alone does not open router/firewall ports or guarantee reachability. |
| `backend/src/main/resources/application.yml` | Defines app LiveKit URL/key/secret properties. |
| `backend/src/main/java/com/letscook/platform/room/RoomService.java` | Builds LiveKit access tokens from the configured URL/key/secret and room/user grants. |
| `backend/src/main/java/com/letscook/platform/room/LiveRoomController.java` | Exposes live-room actions, including the protected media-token endpoint used by the frontend. |
| `backend/src/main/java/com/letscook/platform/room/RoomDtos.java` | Defines the media-token response shape (`url`, token, room name, and publish permission). |
| `frontend/src/app/core/media.service.ts` | Browser-side on-demand LiveKit connection and media controls. |
| `frontend/src/app/core/api.service.ts` | Calls the backend media-token endpoint and attaches the authenticated API token. |
| `frontend/nginx.conf` | Proxies local LiveKit signaling at `/livekit/` for HTTPS pages when the token returns a local endpoint. |
| `backend/pom.xml`, `frontend/package.json` | Include LiveKit server-token and browser-client libraries. |
| `scripts/configure-livekit-cloud.ps1` | Writes LiveKit Cloud URL/key/secret into the git-ignored project `.env`. |
| `scripts/start-global-uat.ps1` | Global UAT launcher; expects a public secure media endpoint when global media is required. |
| `scripts/start-self-hosted-internet-uat.ps1` | Guarded self-hosted Internet UAT launcher; requires explicit acknowledgement that router forwarding has been done. |

`LIVEKIT_MODE=cloud` selects the managed endpoint. `LIVEKIT_MODE=self-hosted` (or the `router` alias) selects the local/router endpoint. The backend resolves the matching URL/key/secret group when it starts, so switching providers does not require an app rebuild. Keep API secrets in `.env` or a secret manager; never put them in frontend source or commit them.

## Option A: LiveKit Cloud (simplest public media path)

1. Create a LiveKit Cloud project and obtain its secure WebSocket URL, API key, and API secret.
2. Run `.\scripts\configure-livekit-cloud.ps1` and enter those values. It stores them in the ignored `.env` file.
3. Start global UAT with `.\scripts\start-global-uat.ps1`.
4. Join from separate networks and validate audio/screen sharing. Keep web access and media connectivity as separate checks.

Implementation references: `scripts/configure-livekit-cloud.ps1`, `scripts/start-global-uat.ps1`, `compose.yaml`, `backend/src/main/java/com/letscook/platform/room/RoomService.java`, and `frontend/src/app/core/media.service.ts`.

## Option B: Self-host on a machine with a static public IP (planned/conditional)

Purchasing a static IP only gives a stable address if the ISP assigns a public address to this connection. Confirm it is not behind CGNAT and that inbound traffic is allowed. A stable DNS hostname is still needed, and TLS certificates plus firewall/router policy must be configured.

1. Confirm public static IPv4 allocation with the ISP and verify there is no upstream CGNAT. If blocked by CGNAT, choose LiveKit Cloud or a public VPS instead.
2. Reserve a stable LAN address for the host; configure DNS for a media hostname (for example `media.letscook.world`) to the public IP. Use Cloudflare DNS-only for a direct LiveKit endpoint unless a specifically supported proxy product is configured; standard HTTP proxying is not a generic WebRTC relay.
3. Configure router and host firewall rules for the exact ports/protocols supported by the selected LiveKit version and deployment. The current repo helper documents TCP 7881, UDP 7882, and UDP 3478; verify current LiveKit requirements before production because defaults may change. Ensure signaling endpoint port 7880 has an appropriate TLS reverse proxy/certificate path if exposed.
4. Set LiveKit external IP and TURN configuration appropriately, use a real TURN certificate/hostname and secure credentials, and validate from cellular/external networks.
5. Run `scripts/configure-livekit-self-hosted.ps1` with `wss://media.letscook.world` plus non-development credentials. This sets `LIVEKIT_MODE=self-hosted` and the protected self-hosted endpoint values. Restart the backend so it issues tokens for the public endpoint.
6. Test browser microphone, room audio, screen sharing, reconnect, and restrictive NAT networks. Monitor bandwidth, server health, and logs.

Current implementation references for this future path: `infra/livekit/livekit-public.yaml`, `compose.self-hosted-media.yaml`, `scripts/start-self-hosted-internet-uat.ps1`, `.env.example`, `backend/src/main/java/com/letscook/platform/room/RoomService.java`, and `frontend/src/app/core/media.service.ts`. A static-IP production setup is not complete merely because this overlay exists.

## Current versus updated target

- **Current:** local/LAN LiveKit by default; one environment flag switches between LiveKit Cloud and self-hosted/router media; the guarded public self-hosting overlay remains available.
- **Target after static IP purchase:** stable media DNS name, TLS signaling, reachable media and TURN ports, production secrets, hardened deployment and external-network tests.
- **Alternative:** LiveKit Cloud keeps the application domain on Cloudflare and uses the provider's media endpoint; no home-router media port forwarding is needed.
