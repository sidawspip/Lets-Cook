# Windows scripts

`dev/run.ps1` launches the desktop app, with `-Local` for the local Compose endpoints. `prod/build.ps1` creates a release EXE by default; use `-Configuration Debug -Local` for local testing. The build script reads the app's ignored `build-config.psd1` when present.
