# Backend scripts

Use `dev/run.ps1` to start the local API. The scripts below can be called from the repository root or by absolute path.

## dev

- `seed-uat-users.ps1` and `run-uat.ps1`: local UAT accounts and API flows.
- `test-core-two-accounts.ps1`, `test-room-role-media.ps1`, and `test-notification-push.mjs`: room, role, and message checks.
- `create-voice-test-users.ps1`, `verify-voice-auth.ps1`, `verify-host-handoff.ps1`, and `verify-local-sync.mjs`: media and host checks.
- `migrate-youtube-secret.ps1`: one-time move of the local YouTube API key into private storage.

## prod

- `configure-livekit-cloud.ps1`, `configure-livekit-self-hosted.ps1`, and `setup-vm-livekit.ps1`: public LiveKit endpoints.
- `migrate-local-secrets.ps1`: one-time move of local service secrets into private storage.

The `prod` scripts change service configuration. Review their parameters and private environment before running them.
