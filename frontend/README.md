# Xynk web app

Angular frontend for Xynk. Its source is in `src/`; static files are in `public/`. The root `compose.yaml` builds this project through `frontend/Dockerfile` and serves it with `nginx.conf`.

From the repository root, `./frontend/scripts/dev/run.ps1` starts the web app and its required local services through the shared Compose stack.

`./frontend/scripts/prod/build.ps1` builds the production web assets under `frontend/dist/xynk-web/browser`. Use `-Configuration Development` for a development build or `-InstallDependencies` to run `npm ci` first. The web app derives API and auth URLs from the browser origin and the Nginx routes in `frontend/nginx.conf`; its build has no URL secrets or placeholders.

From this directory:

```powershell
npm ci
npm start
npm run build
npm run check
```

There is no configured web unit-test runner yet; `check` verifies the Angular development build.

See the root [project layout](../README.md#project-layout) for the other applications and shared services.
