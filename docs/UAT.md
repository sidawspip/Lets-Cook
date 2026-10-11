# UAT guide

## Local test accounts

| User | Email | Password | Purpose |
|---|---|---|---|
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
4. Confirm the link and authenticate the existing local account when prompted.
5. Confirm that the profile and rooms are unchanged.
6. Sign out and verify that either login method returns to that same profile.

The re-authentication step is intentional. Silent linking based only on an email claim can permit account takeover with an untrusted provider or unverified address.

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

