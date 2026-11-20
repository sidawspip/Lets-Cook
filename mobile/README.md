# Xynk Android app

Android-first Flutter client for XYNK watch parties. It reuses the existing
Spring API and Keycloak realm and defaults to the production deployment at
`https://xynk.in`.

## Included in this milestone

- Keycloak username/password plus Google/X Authorization Code + PKCE sign-in with secure access/refresh-token storage
- public room discovery, room join, presence heartbeat, chat, and queue APIs
- automatic return to the active room after an app restart
- inline YouTube playback through the official IFrame Player API
- custom play, seek, volume, mute, fullscreen, queue, and settings controls
- sound enabled by default (subject to Android/YouTube autoplay policy)
- persistent mini-player while queue and suggestions remain open
- queue/suggestion/current-video deduplication
- animated thumbnail-derived ambient background
- interactive preview mode for testing the UI without an account

## Run against production

```powershell
.\mobile\scripts\dev\run.ps1
```

## Run against the local Docker stack

Android emulators reach the host through `10.0.2.2`:

```powershell
.\mobile\scripts\dev\run.ps1 -Local
```

The launcher runs from the Android project directory and forwards extra Flutter arguments. For example, `./mobile/scripts/dev/run.ps1 -Local -Device emulator-5554` selects an emulator.

The debug manifest permits cleartext traffic for this local workflow. Release
builds retain the HTTPS production default.

## Verify and build

```powershell
flutter analyze
flutter test
.\mobile\scripts\prod\build.ps1
.\mobile\scripts\prod\build.ps1 -Configuration Release
```

The default command creates `mobile/build/app/outputs/flutter-apk/app-debug.apk`. Release requires the private signing file and HTTPS endpoints. Copy `mobile/build-config.example.psd1` to ignored `mobile/build-config.psd1` to set the API, auth, and app URLs for this machine, or pass `-ApiBaseUrl`, `-AuthBaseUrl`, and `-AppBaseUrl` directly. `-Local` selects emulator URLs for a Debug build. `-DryRun` prints the Flutter command without building.

## Before Play Store release

The dedicated `lets-cook-mobile` Keycloak client and PKCE callback are included.
Before release, disable direct password grants after any remaining local-account
login migration, configure Google/X production credentials, add verified Android
app links for invitations, and replace debug release signing.
