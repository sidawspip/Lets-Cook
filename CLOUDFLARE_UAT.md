# Cloudflare Quick Tunnel UAT flow

Quick Tunnels provide a temporary, publicly trusted HTTPS URL without a Cloudflare account. They are intended only for testing. The generated hostname changes each time and anyone with the URL can access it unless email protection is enabled.

## Start

From the project directory:

```powershell
.\scripts\start-cloudflare-uat.ps1
```

The script starts/builds Docker, starts `cloudflare/cloudflared`, detects the generated `https://...trycloudflare.com` URL, and replaces Keycloak's redirect/origin lists with the local URLs plus that new tunnel URL. It registers both the exact origin (needed by logout) and its `/*` path form. Previous Quick Tunnel URLs are removed automatically rather than accumulated. The script then prints the new shareable URL.

To protect the tunnel with one-time PIN authentication:

```powershell
.\scripts\start-cloudflare-uat.ps1 -AllowedMail 'tester@example.com'
```

Multiple testers:

```powershell
.\scripts\start-cloudflare-uat.ps1 -AllowedMail 'one@example.com','two@example.com'
```

To start the tunnel and immediately open two independent Chrome Incognito
sessions for two-user testing:

```powershell
.\scripts\start-cloudflare-uat.ps1 -OpenIncognitoSessions 2
```

Each window receives a separate temporary browser profile, so it can stay
logged in as a different user. Opening two ordinary Incognito windows from the
same Chrome process can share one private session, which is why the launcher
uses isolated profiles.

To open test sessions later without restarting the tunnel:

```powershell
.\scripts\open-incognito-test-sessions.ps1 -Sessions 2
```

Edge InPrivate is also supported:

```powershell
.\scripts\open-incognito-test-sessions.ps1 -Sessions 2 -Browser Edge
```

## Stop

```powershell
.\scripts\stop-cloudflare-uat.ps1
```

The ordinary local application remains available at `http://localhost:4200`.

## Global voice and screen sharing

The Quick Tunnel publishes the web application, authentication, and API.
WebRTC audio/video still needs a publicly reachable media server. A Quick
Tunnel URL by itself cannot make the local LiveKit ICE/media ports reachable
from cellular or another network.

For Internet UAT, create a LiveKit Cloud project, copy its Project URL, API key,
and API secret, then run:

```powershell
.\scripts\configure-livekit-cloud.ps1
```

The script prompts for the secret without displaying it and stores all three
values in the local project `.env`, which is git-ignored. It produces:

```dotenv
LIVEKIT_PUBLIC_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your-project-key
LIVEKIT_API_SECRET=your-project-secret
```

Start the Internet-ready flow with:

```powershell
.\scripts\start-global-uat.ps1
```

Unlike the ordinary launcher, this command fails before starting if the media
URL is local or development credentials are still configured. Its final status
must say `Global media endpoint` before testing from cellular or another
network. Keep the API secret server-side; never put it in Angular code or send
it to users.

The local LiveKit container remains the default when these values are absent,
which is useful for localhost and same-Wi-Fi testing.

The app does not connect to LiveKit merely because somebody opens or watches an
OTT/YouTube room. Those rooms continue to use the laptop backend for chat,
presence, queue voting, and synchronized playback. A LiveKit connection is
created only when a user enables microphone/audio, starts screen sharing, or
explicitly joins voice and sharing. With the values above that connection goes
to LiveKit Cloud; without them it goes to the local container.

### Keep LiveKit on this laptop

The repository also includes a separate public-media profile that keeps the
LiveKit server on this laptop. It enables public ICE discovery and LiveKit's
embedded TURN/UDP service without changing the normal LAN configuration.

First forward these router ports to the laptop's LAN address and allow them in
the host firewall:

- TCP `7881` — WebRTC TCP fallback
- UDP `7882` — WebRTC media
- UDP `3478` — TURN/UDP fallback

Then run:

```powershell
.\scripts\start-self-hosted-internet-uat.ps1 -RouterPortsForwarded
```

This option requires a real public IP. It will not work behind ISP CGNAT,
because unsolicited Internet traffic cannot be forwarded to the laptop. The
Cloudflare Quick Tunnel continues to handle the HTTPS web app and secure
WebSocket signaling; WebRTC media reaches the forwarded laptop ports directly.

For reliable access from restrictive corporate networks, add a domain and
trusted certificate for TURN/TLS, or use LiveKit Cloud/public VPS hosting.

## Important limitations

- This is UAT only and has no uptime guarantee.
- The URL changes whenever a new Quick Tunnel is created.
- Quick Tunnels are limited to 200 in-flight requests and do not support SSE.
- Without `LIVEKIT_PUBLIC_URL`, Cloudflare tunnels the HTTPS/WebSocket signaling path while LiveKit media uses `192.168.0.3:7881-7882` directly. Mobile/laptop testers must then be on the same Wi-Fi. Cellular and remote networks require the public LiveKit configuration above.
- Do not use the Quick Tunnel issuer allowance or wildcard hostname model in production.
