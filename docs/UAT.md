# UAT guide

## Local test accounts

| User | Email | Password | Purpose |
|---|---|---|---|
| `test` | `test@uat.local` | `test` | Mobile sign-in smoke testing |
| `demo` | `demo@example.com` | `demo` | Basic smoke testing |
| `ankit` | `ankit@uat.local` | `Uat@123` | Host and room owner |
| `rahul` | `rahul@uat.local` | `Uat@123` | Member and key-entry tests |
| `priya` | `priya@uat.local` | `Uat@123` | Waiting-room and strict-access tests |

These credentials are for local UAT only. Seed or refresh them without deleting Docker data:

```powershell
.\scripts\seed-uat-users.ps1
.\scripts\run-uat.ps1
```

The automated suite checks multiple local users, distinct accounts for distinct emails, correct and incorrect room keys, waiting-room status, and `INVITE_AND_KEY` enforcement. Temporary rooms are removed afterward.

## Google login

Create a Google Cloud Web application OAuth client and add this authorized redirect URI:

```text
http://localhost:8180/realms/lets-cook/broker/google/endpoint
```

Then configure the running UAT realm:

```powershell
.\scripts\enable-google-login.ps1 `
  -ClientId 'YOUR_GOOGLE_CLIENT_ID' `
  -ClientSecret 'YOUR_GOOGLE_CLIENT_SECRET'
```

Do not commit the client secret. The Google button appears on the Keycloak login screen after configuration.

## Same-email linking test

Google cannot use the fake `@uat.local` accounts. To test linking:

1. Register locally with the same real email as your Google account.
2. Verify the local email, or mark it verified in the local Keycloak admin console.
3. Sign out and choose **Continue with Google** using that email.
4. Confirm Google links the existing account automatically when both the Google email and existing Keycloak email are verified.
5. Confirm that the profile and rooms are unchanged.
6. Sign out and verify that either login method returns to that same profile.

Automatic linking is enabled only for Google's trusted, verified email claim. Native Android linking also refuses an existing Keycloak account whose email is not already verified. Do not reuse this flow for providers that do not guarantee verified email ownership.

## Manual test matrix

| ID | Scenario | Expected result |
|---|---|---|
| AUTH-01 | Login as each seeded user | Correct user appears; each has a separate profile |
| AUTH-02 | Enter a wrong password | Login is rejected |
| AUTH-03 | Google login with a new email | New account is created after the broker flow |
| AUTH-04 | Google login with an existing verified email | Existing account authentication is required once, then linked |
| AUTH-05 | Local login after linking | Original profile and rooms appear |
| AUTH-06 | Google login after linking | The same profile and rooms appear |
| ROOM-01 | Host creates `INVITE_OR_KEY` room | Access key appears once |
| ROOM-02 | Member enters wrong room key | Access is denied |
| ROOM-03 | Member enters correct room key | Member joins the room |
| ROOM-04 | Enter key for approval-required room | Membership remains pending |
| ROOM-05 | Enter only a key for `INVITE_AND_KEY` | Access is denied until an invite is also supplied |
| MEDIA-01 | Join the same room in two laptop Chrome profiles | Both connect to one LiveKit room |
| MEDIA-02 | Host selects Share screen and chooses a tab/window/screen | The viewer receives the screen track |
| MEDIA-03 | Stop through Chrome's sharing toolbar | The LIVE state ends without leaving the room |
| MEDIA-04 | Open on mobile Chrome with screen-capture support | Share button launches the platform capture prompt |
| MEDIA-05 | Open on a mobile browser without `getDisplayMedia()` | User can join as viewer and sees a clear unsupported message |

Browser capture requires a secure context. `localhost` qualifies on the laptop, but opening the app from a phone using a LAN IP over plain HTTP does not. Mobile-device UAT therefore needs an HTTPS UAT hostname or tunnel pointing at the Docker host, with ports for Keycloak and LiveKit reachable from that hostname.

## Production smoke test: web and Android

Use this short checklist after every production deployment. Do not use an administrator account for application testing.

### Test entry points

- Web: `https://letscook.world/`
- Android release APK: `mobile/build/app/outputs/flutter-apk/app-release.apk`
- For production smoke tests, use a dedicated provider-backed test account; no shared `demo / demo` account is enabled.
- Android OAuth callback: `world.letscook.app:/oauthredirect`

### Web flow

1. Open the web URL in a private browser window.
2. Sign in with the smoke account and verify Home, Profile, provider pages, History, Like, room creation, room join, and logout.
3. Choose **Continue with Google**. Complete the provider login manually and verify the browser returns to `letscook.world`, not a localhost URL.
4. Sign out, then choose **Continue with X**. Complete the provider login manually. X may not return an email; the X-specific first-login flow must create the account without opening Keycloak's **Update Account Information** form.
5. After each provider's first login, verify the profile is initialized from provider claims. Google should provide name, email, and avatar. X should provide its available name/handle, with email left empty when X does not supply one.
6. Edit the display name, sign out, and sign in again with the same provider. Verify the user's edited display name is preserved.

### Physical Android flow

1. Install the production-signed APK. If a debug-signed build with the same package is installed, uninstall it first; this deletes only that app's local device data.
2. Open the app and confirm the Google and X icons/buttons render.
3. Tap **Continue with Google**. Android must show its native account chooser over the app. Select the account manually and verify the app resumes after authentication.
4. Tap **Continue with X**. A secure Chrome Custom Tab is expected; the standalone Chrome app should not replace the app task. Complete login manually and verify the callback returns to the app.
5. Repeat the Home, Profile, provider History/Like, room, and logout checks from the web flow.
6. Join the same room from web and Android. Verify presence, audio state, queue changes, History, and Like actions stay synchronized.

### LiveKit network modes

Run each enabled deployment mode separately rather than mixing URLs in one session:

- Cloud mode: verify both devices can join while the phone uses mobile data.
- Router/static-IP mode: verify the advertised LiveKit URL resolves to the public/static address and the required TCP/UDP ports are forwarded.
- LAN mode: put the phone and host on the same Wi-Fi, use the host's LAN address, and verify the phone can reach the API, Keycloak, and LiveKit endpoints.

For every failed case, record the device, network mode, time, visible error, and relevant API/Keycloak/LiveKit logs. Never paste OAuth client secrets, access tokens, or passwords into the report.

