# Xynk Windows app

This is the separate Windows desktop client for Xynk. It is intentionally
kept outside `mobile/`, while starting from the same tested Dart models, API
client, room state, theme, and screens.

## Current status

- Uses `https://xynk.in` for the API, authentication, and app links.
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
.\windows_app\scripts\prod\build.ps1
```

From the repository root, `./windows_app/scripts/dev/run.ps1` launches the Windows Flutter app against its configured production URLs. Use `./windows_app/scripts/dev/run.ps1 -Local` to connect to the local Compose stack. Extra Flutter arguments are forwarded.

`build.ps1` defaults to Release. Copy `windows_app/build-config.example.psd1` to ignored `windows_app/build-config.psd1` for machine-specific API, auth, and app URLs, or pass `-ApiBaseUrl`, `-AuthBaseUrl`, and `-AppBaseUrl`. Use `-Configuration Debug -Local` for local HTTP endpoints. `-DryRun` prints the command. The EXE needs the other files in its output directory.

The executable will be produced under
`build/windows/x64/runner/Release/Xynk.exe` for a release build.

## Desktop work remaining

1. Use a desktop OAuth redirect/loopback flow for Google and X sign-in.
2. Select a Windows video backend and verify HLS/direct-media playback.
3. Add native Windows notifications, taskbar/window controls, and optional
   always-on-top mini-player behavior.
4. Validate LiveKit microphone, camera, and screen sharing on Windows.
5. Add an MSIX installer, signing, auto-update strategy, and app icon assets.
