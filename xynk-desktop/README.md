# XYNK Windows desktop

The Windows client uses Electron, React, TypeScript, and the existing XYNK API at `https://xynk.in/api`. Android remains a separate Flutter client.

## Run and build

From this directory:

```powershell
npm ci
npm run dev
npm run type-check
npm run build
```

The Windows build script compiles `media_resolver/bin/resolve_youtube.dart` with the Dart SDK, builds the Electron main process and React renderer, then writes `release-local-*/win-unpacked/XYNK.exe`. These release directories and the generated resolver executable are ignored by Git.

## Media flow

- Provider sites open inside an Electron webview using a persistent provider profile.
- A YouTube watch or Shorts selection enters the room through the shared queue API. A bundled Dart helper using `youtube_explode_dart` resolves the stream; the room uses XYNK controls.
- Public Web pages use `/api/media/resolve-web` to obtain a direct MP4 or HLS source. HLS is played through Shaka Player.
- LiveKit handles room voice and screen sharing. The API issues media tokens.
- Crunchyroll's protected player is still under development and should not be treated as verified playback.

## Configuration

The renderer defaults to `https://xynk.in/api` and the `xynk` realm. Optional build-time variables are `VITE_API_BASE`, `VITE_AUTH_BASE`, and `VITE_CLIENT_ID`. Keep secrets outside this directory.

## Boundaries

The Electron preload exposes only the IPC functions required by the renderer. The app does not run a local Dart HTTP server. The Dart code here is solely the packaged YouTube stream resolver.
