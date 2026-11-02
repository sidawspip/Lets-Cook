# Let's Cook Mobile

Android-first Flutter client for Lets Cook watch parties. It reuses the existing
Spring API and Keycloak realm and defaults to the production deployment at
`https://letscook.world`.

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
cd mobile
flutter run
```

## Run against the local Docker stack

Android emulators reach the host through `10.0.2.2`:

```powershell
cd mobile
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api `
  --dart-define=AUTH_BASE_URL=http://10.0.2.2:8180 `
  --dart-define=APP_BASE_URL=http://10.0.2.2:4200
```

The debug manifest permits cleartext traffic for this local workflow. Release
builds retain the HTTPS production default.

## Verify and build

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.

## Before Play Store release

The dedicated `lets-cook-mobile` Keycloak client and PKCE callback are included.
Before release, disable direct password grants after any remaining local-account
login migration, configure Google/X production credentials, add verified Android
app links for invitations, and replace debug release signing.
