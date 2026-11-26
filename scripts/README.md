# Xynk script map

Run these from the repository root. Each app keeps its scripts under its own project directory:

For a complete local startup, run `./run.ps1`. It starts Compose, waits for health checks, builds Android with local URLs and the Electron desktop app with public Xynk URLs, then opens Windows, Android, and the web app. Use `./run.ps1 -DryRun` to preview its seven steps. An Android device or emulator must already be connected. `-SkipAndroid`, `-SkipWindows`, `-SkipBrowser`, and `-SkipBuild` are available when needed; use `-AndroidDevice <id>` if more than one device is connected. For public service after local health checks, run `./scripts/start-public.ps1` in a separate window; it keeps the named Cloudflare tunnel attached.

| Project | Run | Build | Additional scripts |
| --- | --- | --- | --- |
| Backend | `backend/scripts/dev/run.ps1` | `docker compose build backend` | `backend/scripts/dev/`, `backend/scripts/prod/` |
| Web | `frontend/scripts/dev/run.ps1` | `frontend/scripts/prod/build.ps1` | `frontend/scripts/` |
| Android | `mobile/scripts/dev/run.ps1` | `mobile/scripts/prod/build.ps1` | `mobile/scripts/dev/`, `mobile/scripts/prod/` |
| Windows | `windows_app/scripts/dev/run.ps1` | `windows_app/scripts/prod/build.ps1` | `windows_app/scripts/` |
| Shared infrastructure | — | `docker compose build` | `infra/scripts/dev/`, `infra/scripts/prod/` |

`dev` contains local setup, UAT, and diagnostics. `prod` contains credential and public-service configuration. Private values stay in the ignored local `.env` or the user's private secrets directory.
