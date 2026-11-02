# Let's Cook for Windows

This is the separate Windows desktop client for Let's Cook. It is intentionally
kept outside `mobile/`, while starting from the same tested Dart models, API
client, room state, theme, and screens.

## Current status

- Uses `https://letscook.world` for the API, authentication, and app links.
- Local username/password sign-in and the shared social/room/profile code are
  present.
- Windows-safe fallbacks prevent Android notification and PiP method channels
  from blocking startup.
- A Windows WebView2 provider browser now includes provider navigation,
  address/search controls, isolated provider sign-in, and adding YouTube,
  public-cloud, direct-media, or provider pages to a room.
- The desktop window starts centered at 1280x800 with a 960x640 minimum size.
- The copied unit and widget tests pass.
- A native build requires Visual Studio with **Desktop development with C++**.

## Build

```powershell
flutter pub get
flutter test
flutter build windows
```

The executable will be produced under
`build/windows/x64/runner/Release/LetsCook.exe` for a release build.

## Desktop work remaining

1. Use a desktop OAuth redirect/loopback flow for Google and X sign-in.
2. Select a Windows video backend and verify HLS/direct-media playback.
3. Add native Windows notifications, taskbar/window controls, and optional
   always-on-top mini-player behavior.
4. Validate LiveKit microphone, camera, and screen sharing on Windows.
5. Add an MSIX installer, signing, auto-update strategy, and app icon assets.
